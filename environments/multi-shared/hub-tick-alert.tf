# =============================================================================
# Deploy hub tick — liveness
# =============================================================================

# Alerts when the hub's clock stops.
#
# `unifeed-hub-tick` fires every minute at /api/tick, and that endpoint is the
# only thing that drains a settled candidate queue or reaps a transaction whose
# runner died. If it stops, nothing deploys and nothing says so: the hub simply
# accumulates queued candidates and looks idle.
#
# That is not hypothetical. The job spent 2026-08-12 to 2026-08-17 pointing at
# a hostname that had been removed, firing successfully into nothing. Five days
# of "deploys are mysteriously stuck", diagnosed repeatedly as a queue bug,
# because a scheduler that runs on time and reaches nobody looks exactly like a
# scheduler that is fine.
#
# What this watches is the hub's own request log rather than Cloud Scheduler's
# job metrics — deliberately, and not for want of trying the obvious thing.
# There are no cloudscheduler.googleapis.com metric descriptors in this project
# at all, so a policy built on job/attempt_count would have been a policy that
# never evaluates: green in Terraform, silent forever, which is the same class
# of undetected failure this is meant to catch.
#
# Watching the receiving end is also strictly better here. It is evidence the
# request ARRIVED and was answered, so it covers every way the tick can die:
# the job deleted or paused, the job aimed at the wrong host (the actual
# outage), the hub failing to start, or the endpoint returning 5xx. A metric on
# the sender would have reported four of those five as healthy.
resource "google_logging_metric" "hub_tick_success" {
  project = var.project_id
  name    = "hub_tick_success"

  description = "Successful scheduler ticks reaching the deploy hub's /api/tick"

  # Pinned to the scheduler's user agent so a human curling the endpoint while
  # debugging cannot hold the alert open — the thing being verified is that the
  # automatic clock runs unattended, which is exactly what nobody noticed.
  filter = join(" AND ", [
    "resource.type = \"cloud_run_revision\"",
    "resource.labels.service_name = \"${google_cloud_run_v2_service.unifeed_test_runner.name}\"",
    "httpRequest.requestUrl : \"/api/tick\"",
    "httpRequest.status = 200",
    "httpRequest.userAgent = \"Google-Cloud-Scheduler\"",
  ])

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
  }
}

resource "google_monitoring_notification_channel" "hub_alerts" {
  project      = var.project_id
  display_name = "Unifeed deploy hub alerts"
  type         = "email"

  labels = {
    email_address = var.alert_email
  }
}

resource "google_monitoring_alert_policy" "hub_tick_stopped" {
  project      = var.project_id
  display_name = "Deploy hub tick has stopped"
  combiner     = "OR"

  documentation {
    content   = <<-EOT
      Nothing has ticked the deploy hub for fifteen minutes.

      The tick runs every minute. While it is stopped the hub deploys nothing —
      candidates queue up and transactions whose runner died are never reaped —
      and the hub's UI gives no sign of it, because an idle hub and a stopped
      hub look identical.

      This does not mean a deploy has failed. It means deploys are not being
      attempted, and that no rollback would happen if one were needed.

      Check, roughly in order of likelihood:

      1. Is the `unifeed-hub-tick` Cloud Scheduler job still there, enabled, and
         pointed at the CURRENT hub URL? It broke once by outliving the
         hostname it named. It is declared in hub-tick.tf and references the
         service resource for that reason — a literal hostname there is a bug.
      2. Is `unifeed-test` serving? A failed deploy of the hub itself takes the
         tick down with it, and the hub cannot transactionally replace itself.
      3. Is /api/tick returning non-200? This metric counts successes only, so
         a hub that is up but erroring reads as silence here.

      Confirm by hand:
        curl -s -o /dev/null -w '%%{http_code}\n' https://hub.dev.unifeed.io/api/tick

      A 200 means the endpoint is fine and the scheduler is the problem.
    EOT
    mime_type = "text/markdown"
  }

  conditions {
    display_name = "No successful tick has reached the hub"

    condition_absent {
      filter = join(" AND ", [
        "metric.type = \"logging.googleapis.com/user/${google_logging_metric.hub_tick_success.name}\"",
        "resource.type = \"cloud_run_revision\"",
      ])

      # Fifteen missed ticks, not one or two. Cloud Run cold starts, a hub
      # redeploy and Cloud Scheduler's own retry jitter all drop the occasional
      # minute, and an alert that cries wolf nightly gets muted — which is how
      # the last one stopped being read.
      duration = "900s"

      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_DELTA"
        cross_series_reducer = "REDUCE_SUM"
      }

      trigger { count = 1 }
    }
  }

  notification_channels = [google_monitoring_notification_channel.hub_alerts.id]

  alert_strategy {
    auto_close = "86400s"
  }
}

variable "alert_email" {
  description = <<-EOT
    Where deploy hub alerts go. A shared address rather than an individual's
    inbox, for the same reason as the dependency alerts in multi-dev: an alert
    one person receives, from Google's alerting sender, is one spam rule away
    from nobody receiving it.
  EOT
  type        = string
  default     = "dev@breathebranding.co.uk"
}
