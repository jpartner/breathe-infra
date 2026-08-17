# =============================================================================
# Monitoring — business outcomes and deploy health
# =============================================================================
#
# monitoring.tf watches our dependencies. This file watches us.
#
# The distinction matters because a dead third party is only one way for revenue
# to stop. A bad deploy, an expired credential, a failed migration or a
# storefront that stopped calling the backend all produce exactly the same
# silence with every dependency perfectly healthy.
#
# Everything here alerts on ABSENCE. Nothing indicates a problem by going up.
# That is what makes these the only alerts that catch a failure nobody
# anticipated: they do not require us to have predicted the mechanism, only to
# know that orders should not be zero for a day.
#
# Metrics come from io.unifeed.core.telemetry.BusinessEvent:
#   custom.googleapis.com/business/event/total  CUMULATIVE  {event, outcome, tenant}

variable "business_absence_window" {
  description = <<-EOT
    How long a business event may be absent before we are told.

    Deliberately generous for dev, where traffic is synthetic and intermittent —
    a tighter window here would train everyone to ignore the alert, which is
    worse than not having it. Production wants this driven by the observed floor
    of real traffic per event, and it should be revisited once there is a week
    of data to look at rather than guessed a second time.

    Capped by the API, not by choice: Cloud Monitoring rejects an absence
    duration longer than 23h30m, so "no orders for a full day" is not directly
    expressible and 84600s is the closest available. Worth knowing before
    someone tries to widen this and gets a 400 from an apply that has already
    created half the policies.
  EOT
  type        = string
  default     = "84600s"
}

# -----------------------------------------------------------------------------
# 4. Orders have stopped
# -----------------------------------------------------------------------------
# Grouped by tenant on purpose. One storefront going quiet while the others keep
# trading is the failure most likely to go unnoticed, and an aggregate count
# would hide it completely.
resource "google_monitoring_alert_policy" "orders_absent" {
  project      = var.project_id
  display_name = "Unifeed ${var.environment} — no orders placed"
  combiner     = "OR"

  documentation {
    content   = <<-EOT
      No order has been placed for a tenant in
      $${var.business_absence_window}. Covers both paths — basket checkout and
      quote acceptance are counted as separate events, so check which.

      This alert does not tell you what is broken, only that the outcome we
      exist to produce has stopped. That is the point: it fires for causes we
      never thought to write an alert for.

      Start with: is the storefront up and reaching the backend? Did a deploy
      land recently? Is Stripe configured for that tenant? Then check the
      dependency alerts — a provider outage will usually have fired first.
    EOT
    mime_type = "text/markdown"
  }

  conditions {
    display_name = "No order.placed or quote.accepted events"

    condition_absent {
      filter = join(" AND ", [
        "metric.type = \"custom.googleapis.com/business/event/total\"",
        "resource.type = \"generic_task\"",
        "metric.labels.env = \"${var.environment}\"",
        "metric.labels.outcome = \"success\"",
        "metric.labels.event = one_of(\"order.placed\", \"quote.accepted\")",
      ])

      duration = var.business_absence_window

      aggregations {
        alignment_period     = "3600s"
        per_series_aligner   = "ALIGN_DELTA"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields      = ["metric.labels.tenant", "metric.labels.event"]
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
# 5. Stripe has stopped talking to us
# -----------------------------------------------------------------------------
# Distinct from the order alert and not redundant with it. This one does not
# depend on us successfully calling anything — Stripe pushes to us — so it stays
# a valid signal even when the platform is otherwise broken. It is also the only
# thing that would catch a webhook endpoint that has been misconfigured, moved,
# or had its signature secret rotated out from under it.
resource "google_monitoring_alert_policy" "payment_webhooks_absent" {
  project      = var.project_id
  display_name = "Unifeed ${var.environment} — no payment webhooks received"
  combiner     = "OR"

  documentation {
    content   = <<-EOT
      No verified Stripe webhook has reached us in
      $${var.business_absence_window}.

      Either no card payments are being attempted — check whether the orders
      alert has also fired, which would point at a platform problem rather than
      a Stripe one — or Stripe cannot deliver to us.

      For the latter: check the endpoint URL registered in the Stripe dashboard,
      Stripe's own delivery attempt log, and whether the tenant webhook secret
      in Secret Manager still matches. Note that a signature that no longer
      verifies is recorded as a failed webhook_events row, so the events table
      is worth reading before assuming Stripe went quiet.
    EOT
    mime_type = "text/markdown"
  }

  conditions {
    display_name = "No verified Stripe webhooks"

    condition_absent {
      filter = join(" AND ", [
        "metric.type = \"custom.googleapis.com/business/event/total\"",
        "resource.type = \"generic_task\"",
        "metric.labels.env = \"${var.environment}\"",
        "metric.labels.event = \"payment.webhook.received\"",
      ])

      duration = var.business_absence_window

      aggregations {
        alignment_period     = "3600s"
        per_series_aligner   = "ALIGN_DELTA"
        cross_series_reducer = "REDUCE_SUM"
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
# 6. A Cloud Run deploy is failing
# -----------------------------------------------------------------------------
# Added after backend deploys were broken for roughly half an hour on
# 2026-08-14 and were discovered only because an unrelated Terraform apply
# happened to trip over the failure. Cloud Run keeps serving the last healthy
# revision when a new one fails its startup probe, which is the right behaviour
# and also the reason nobody notices: the service stays up and every subsequent
# deploy silently changes nothing.
#
# This is a log-matched policy rather than a metric threshold because a
# container that dies during startup never gets far enough to report a metric —
# the log line is the only evidence that exists.
resource "google_monitoring_alert_policy" "cloud_run_deploy_failing" {
  project      = var.project_id
  display_name = "Unifeed ${var.environment} — Cloud Run revision failed to start"
  combiner     = "OR"

  documentation {
    content   = <<-EOT
      A Cloud Run revision failed its startup probe and took no traffic.

      The service is almost certainly still up on its previous revision, so
      customers see nothing. What has actually broken is deployment: until this
      is fixed, every deploy appears to succeed and changes nothing.

      Check the failed revision's logs. Historically the cause has been Flyway
      refusing to start on a migration checksum mismatch — an applied migration
      was edited, or a repair rewrote the recorded checksums to match a
      different copy of the file.
    EOT
    mime_type = "text/markdown"
  }

  conditions {
    display_name = "Container failed to start"

    condition_matched_log {
      filter = join("\n", [
        "resource.type = \"cloud_run_revision\"",
        "severity >= ERROR",
        "(textPayload:\"Container called exit(1)\" OR textPayload:\"failed the configured startup probe\" OR textPayload:\"Container failed to start\")",
      ])
    }
  }

  notification_channels = [google_monitoring_notification_channel.dependency_alerts.id]

  # Required for a log-matched condition, and useful in its own right: a
  # crash-looping container produces the same line repeatedly and would
  # otherwise send one email per restart.
  alert_strategy {
    notification_rate_limit {
      period = "3600s"
    }
  }
}
