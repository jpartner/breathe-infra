# =============================================================================
# Monitoring — external dependency alerting
# =============================================================================
#
# These policies exist because of a specific failure: our address lookup
# provider ceased trading after losing a legal case and we learned about it from
# a customer report. Nothing in the system distinguished "nobody used this
# today" from "this has been broken for weeks".
#
# The metrics are published by the backend (io.unifeed.core.telemetry.ExternalCall):
#
#   custom.googleapis.com/external.call.total              CUMULATIVE  volume + outcomes
#   custom.googleapis.com/external.call.last.success.age   GAUGE       seconds since last success
#   custom.googleapis.com/external.call                    DISTRIBUTION latency
#
# ORDERING: a Cloud Monitoring alert policy can only reference a metric
# descriptor that already exists, and descriptors are created on first write.
# So the backend must be deployed with METRICS_EXPORT_ENABLED=true and have
# pushed at least once before these policies will apply cleanly. Apply the
# service change first, wait a step interval (60s), then apply these.

variable "alert_email" {
  description = <<-EOT
    Where dependency alerts go. A shared address rather than an individual's
    inbox on purpose: an alert that only one person receives, and that arrives
    from Google's alerting sender so is a candidate for the spam folder,
    reproduces the single point of failure that let the last provider outage run
    unnoticed.
  EOT
  type        = string
  default     = "dev@breathebranding.co.uk"
}

variable "provider_stale_threshold_seconds" {
  description = <<-EOT
    How long a provider may go without a single successful call before we are
    told. Six hours is chosen for a dev environment where feeds run on a daily
    cycle and nothing is customer-facing; a provider on the checkout path wants
    minutes, not hours, and should get its own policy rather than a lower value
    here.
  EOT
  type        = number
  default     = 21600
}

resource "google_monitoring_notification_channel" "dependency_alerts" {
  project      = var.project_id
  display_name = "Unifeed dependency alerts (${var.environment})"
  type         = "email"

  labels = {
    email_address = var.alert_email
  }
}

# -----------------------------------------------------------------------------
# 1. A provider has not succeeded in a long time
# -----------------------------------------------------------------------------
# The one that would have caught getAddress.io. Note this fires whether the
# provider is erroring, timing out, returning empty bodies, or being served
# entirely from our cache — none of those reset the last-success clock.
#
# REDUCE_MIN across instances is deliberate: with several Cloud Run instances,
# if *any* of them got a successful answer recently then the provider is alive.
# Taking the max would page us every time an instance cold-started onto a code
# path it had not exercised yet.
resource "google_monitoring_alert_policy" "provider_stale" {
  project      = var.project_id
  display_name = "Unifeed ${var.environment} — external provider has not succeeded recently"
  combiner     = "OR"

  documentation {
    content   = <<-EOT
      An external provider has gone $${var.provider_stale_threshold_seconds}s
      without a single successful call from unifeed-backend.

      This is the alert we did not have when our address lookup provider ceased
      trading. Treat it as "this dependency is dead until proven otherwise",
      not as a blip.

      Check, in order:
        1. Is the provider's own status page or website up at all?
        2. Are we erroring, timing out, or getting empty 200s? Break down
           custom.googleapis.com/external.call.total by the `outcome` label.
        3. If outcome is `cached`, we have not actually reached them since the
           cache warmed — the cache is masking the outage.
        4. Have our credentials expired, or has the provider changed its API?
    EOT
    mime_type = "text/markdown"
  }

  conditions {
    display_name = "No successful call in threshold window"

    condition_threshold {
      filter = join(" AND ", [
        "metric.type = \"custom.googleapis.com/external.call.last.success.age\"",
        "resource.type = \"generic_task\"",
        "metric.labels.env = \"${var.environment}\"",
      ])

      comparison      = "COMPARISON_GT"
      threshold_value = var.provider_stale_threshold_seconds
      duration        = "300s"

      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_MAX"
        cross_series_reducer = "REDUCE_MIN"
        group_by_fields      = ["metric.labels.provider"]
      }

      trigger { count = 1 }
    }
  }

  notification_channels = [google_monitoring_notification_channel.dependency_alerts.id]

  alert_strategy {
    auto_close = "604800s"
  }
}

# -----------------------------------------------------------------------------
# 2. A provider is failing outright
# -----------------------------------------------------------------------------
# Faster than policy 1 and complementary: this catches a provider that has
# started erroring in the last few minutes, where the staleness clock has not
# yet run out. `empty` counts as a failure here on purpose — HTTP 200 with no
# content is how a dying supplier usually presents.
resource "google_monitoring_alert_policy" "provider_failing" {
  project      = var.project_id
  display_name = "Unifeed ${var.environment} — external provider failing"
  combiner     = "OR"

  documentation {
    content   = <<-EOT
      Calls to an external provider are failing (outcome error, timeout, or
      empty). Break down custom.googleapis.com/external.call.total by `provider`
      and `outcome` to see which and how.

      `empty` means the call succeeded at the transport level and returned
      nothing usable. Do not dismiss it as noise — it is the most common
      signature of a supplier that has stopped serving real data.
    EOT
    mime_type = "text/markdown"
  }

  conditions {
    display_name = "Failed external calls in a 5 minute window"

    condition_threshold {
      filter = join(" AND ", [
        "metric.type = \"custom.googleapis.com/external.call.total\"",
        "resource.type = \"generic_task\"",
        "metric.labels.env = \"${var.environment}\"",
        "metric.labels.outcome = one_of(\"error\", \"timeout\", \"empty\", \"server_error\")",
      ])

      comparison      = "COMPARISON_GT"
      threshold_value = 5
      duration        = "300s"

      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_DELTA"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields      = ["metric.labels.provider", "metric.labels.outcome"]
      }

      trigger { count = 1 }
    }
  }

  notification_channels = [google_monitoring_notification_channel.dependency_alerts.id]

  alert_strategy {
    auto_close = "86400s"
  }
}

# -----------------------------------------------------------------------------
# 3. The backend has stopped reporting at all
# -----------------------------------------------------------------------------
# Without this the other two policies are worthless: a metric that stops being
# written cannot breach a threshold, so a backend that crashes, loses its
# metrics-writer permission, or has export switched off looks exactly like a
# backend where everything is fine. This is the alert that watches the alerting.
#
# Deliberately not grouped by provider — a single provider going quiet is
# policy 1's job, and grouping here would fire on every supplier whose sync
# simply has not run today.
resource "google_monitoring_alert_policy" "metrics_pipeline_silent" {
  project      = var.project_id
  display_name = "Unifeed ${var.environment} — external call metrics have stopped arriving"
  combiner     = "OR"

  documentation {
    content   = <<-EOT
      unifeed-backend has published no external.call metrics for an hour.

      This does not mean a dependency is down — it means we have lost the
      ability to tell. Until it is resolved, treat the two dependency alert
      policies as offline.

      Check: is the backend running and serving traffic? Is
      METRICS_EXPORT_ENABLED still true? Does the backend service account still
      hold roles/monitoring.metricWriter? Did a deploy roll back the telemetry
      change?
    EOT
    mime_type = "text/markdown"
  }

  conditions {
    display_name = "No external call metrics for an hour"

    condition_absent {
      filter = join(" AND ", [
        "metric.type = \"custom.googleapis.com/external.call.total\"",
        "resource.type = \"generic_task\"",
        "metric.labels.env = \"${var.environment}\"",
      ])

      duration = "3600s"

      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_DELTA"
        cross_series_reducer = "REDUCE_SUM"
      }

      trigger { count = 1 }
    }
  }

  notification_channels = [google_monitoring_notification_channel.dependency_alerts.id]

  alert_strategy {
    auto_close = "86400s"
  }
}

variable "metrics_export_enabled" {
  description = <<-EOT
    Whether the backend pushes metrics to Cloud Monitoring.

    False since 2026-08-14: enabling it crashed the JVM at startup in a native
    gRPC/tcnative frame, taking every new revision down. Kept as a variable
    rather than a hardcoded false so that re-enabling it after the transport is
    fixed is a one-line change and an obvious thing to review, rather than an
    edit buried in a container block.

    Back on since 2026-08-14 after the cause was fixed: the crash was the Alpine
    base image loading a glibc-only netty tcnative, not the registry itself. The
    backend entrypoint now forces JDK SSL, verified by reproducing the segfault
    in that exact image and confirming the flag prevents it.

    Still worth knowing what this being true does and does not prove. It proves
    the registry initialises. Whether Cloud Monitoring is actually receiving data
    is answered by the descriptors existing, not by this flag.
  EOT
  type        = bool
  default     = true
}
