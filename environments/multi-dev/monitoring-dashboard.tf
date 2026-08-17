# =============================================================================
# Operational dashboard — "is anything broken right now"
# =============================================================================
#
# Deliberately one dashboard, and deliberately narrow.
#
# Every panel here is driven by a metric that an alert policy in monitoring.tf
# also fires on. That is the point: what you look at and what pages you are the
# same data, so a panel that looks healthy cannot coexist with an alert that is
# firing. Dashboards and alerts drifting apart is the normal way a monitoring
# setup rots, and it happens precisely because they get built from different
# queries by different people at different times.
#
# What is NOT here, on purpose:
#
#   Business metrics (orders, quotes, payments). Different question, different
#   reader. Someone checking whether trading is healthy should not scroll past
#   connection-pool graphs, and someone debugging an outage should not scroll
#   past order counts. That dashboard is worth building when someone actually
#   wants to read it daily — the metrics are being collected either way.
#
#   The ~120 Spring and JVM built-ins. They are valuable when debugging a
#   specific problem and Metrics Explorer is the right tool for that. On a
#   dashboard they invite staring at graphs that are almost always fine, which
#   trains people to treat "looks normal" as information.

resource "google_monitoring_dashboard" "unifeed_operational" {
  project = var.project_id

  dashboard_json = jsonencode({
    displayName = "Unifeed ${var.environment} — dependencies"
    mosaicLayout = {
      columns = 12
      tiles = [
        # ---------------------------------------------------------------
        # Seconds since each provider last worked.
        # ---------------------------------------------------------------
        # Top-left because it is the panel that answers the question this
        # whole exercise started from. A provider that has quietly ceased
        # trading shows here as a line climbing steadily, long before anyone
        # files a bug — it was the absence of this that let an address lookup
        # provider stay dead until a customer reported it.
        #
        # REDUCE_MIN across instances: if any instance got a good answer
        # recently the provider is alive.
        {
          xPos   = 0
          yPos   = 0
          width  = 12
          height = 4
          widget = {
            title = "Seconds since last success, per provider (alerts at ${var.provider_stale_threshold_seconds}s)"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = join(" AND ", [
                      "metric.type=\"custom.googleapis.com/external/call/last/success/age\"",
                      "resource.type=\"generic_task\"",
                      "metric.label.\"env\"=\"${var.environment}\"",
                    ])
                    aggregation = {
                      alignmentPeriod    = "60s"
                      perSeriesAligner   = "ALIGN_MAX"
                      crossSeriesReducer = "REDUCE_MIN"
                      groupByFields      = ["metric.label.\"provider\""]
                    }
                  }
                }
                plotType       = "LINE"
                legendTemplate = "$${metric.label.provider}"
              }]
              # No colour: the API rejects a colour on an XyChart threshold.
              # The line is drawn where the alert fires, so a series crossing it
              # on screen means an email is already on its way.
              thresholds = [{ value = var.provider_stale_threshold_seconds }]
              yAxis      = { label = "seconds", scale = "LINEAR" }
            }
          }
        },

        # ---------------------------------------------------------------
        # Call volume per provider.
        # ---------------------------------------------------------------
        # Volume is half the signal and the half people forget. A dependency
        # going quiet shows up as a count falling to zero well before it shows
        # up as errors — a vendor that switches off does not return 500s, it
        # returns nothing because nothing calls it successfully any more.
        {
          xPos   = 0
          yPos   = 4
          width  = 6
          height = 4
          widget = {
            title = "External calls per provider"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = join(" AND ", [
                      "metric.type=\"custom.googleapis.com/external/call/total\"",
                      "resource.type=\"generic_task\"",
                      "metric.label.\"env\"=\"${var.environment}\"",
                    ])
                    aggregation = {
                      alignmentPeriod    = "300s"
                      perSeriesAligner   = "ALIGN_DELTA"
                      crossSeriesReducer = "REDUCE_SUM"
                      groupByFields      = ["metric.label.\"provider\""]
                    }
                  }
                }
                plotType       = "STACKED_BAR"
                legendTemplate = "$${metric.label.provider}"
              }]
              yAxis = { label = "calls / 5 min", scale = "LINEAR" }
            }
          }
        },

        # ---------------------------------------------------------------
        # Everything that was not a success, broken out by outcome.
        # ---------------------------------------------------------------
        # Split by outcome rather than merged into an error rate, because the
        # outcomes mean genuinely different things and want different
        # reactions. `empty` in particular is the one to watch: a 200 carrying
        # nothing usable is how a failing supplier most often presents, and it
        # is invisible in any chart that only counts non-2xx.
        #
        # `cached` appearing here is not a failure but is not health either —
        # it means we have not actually reached that provider.
        {
          xPos   = 6
          yPos   = 4
          width  = 6
          height = 4
          widget = {
            title = "Non-success outcomes by provider"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = join(" AND ", [
                      "metric.type=\"custom.googleapis.com/external/call/total\"",
                      "resource.type=\"generic_task\"",
                      "metric.label.\"env\"=\"${var.environment}\"",
                      "metric.label.\"outcome\"!=\"success\"",
                    ])
                    aggregation = {
                      alignmentPeriod    = "300s"
                      perSeriesAligner   = "ALIGN_DELTA"
                      crossSeriesReducer = "REDUCE_SUM"
                      groupByFields      = ["metric.label.\"provider\"", "metric.label.\"outcome\""]
                    }
                  }
                }
                plotType       = "STACKED_BAR"
                legendTemplate = "$${metric.label.provider} / $${metric.label.outcome}"
              }]
              yAxis = { label = "calls / 5 min", scale = "LINEAR" }
            }
          }
        },

        # ---------------------------------------------------------------
        # Is anything reporting at all.
        # ---------------------------------------------------------------
        # The panel that tells you whether to believe the other three. If this
        # is flat at zero then every graph above is showing the absence of
        # data rather than the absence of problems, and they are not the same
        # thing. This has been the actual state of dev for days at a time
        # while Terraform reported metrics as enabled.
        {
          xPos   = 0
          yPos   = 8
          width  = 12
          height = 3
          widget = {
            title = "Instances reporting (if this is zero, nothing above means anything)"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = join(" AND ", [
                      "metric.type=\"custom.googleapis.com/process/uptime\"",
                      "resource.type=\"generic_task\"",
                      "metric.label.\"env\"=\"${var.environment}\"",
                    ])
                    aggregation = {
                      alignmentPeriod    = "300s"
                      perSeriesAligner   = "ALIGN_MEAN"
                      crossSeriesReducer = "REDUCE_COUNT"
                    }
                  }
                }
                plotType = "LINE"
              }]
              yAxis = { label = "instances", scale = "LINEAR" }
            }
          }
        },
      ]
    }
  })
}
