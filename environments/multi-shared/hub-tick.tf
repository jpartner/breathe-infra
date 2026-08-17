# =============================================================================
# Deploy hub tick
# =============================================================================

# The hub's clock.
#
# `/api/tick` does two things the hub cannot do for itself: reap transactions
# whose runner died mid-run, and drain the candidate queue once it has settled.
# Both were previously reached only as a side effect of a candidate being
# registered, and the docs described the endpoint as something an operator
# curls by hand.
#
# That stopped working when the queue gained a settle window. Registration
# deliberately declines to drain while candidates are still arriving — that is
# the entire point, and it is what stops a backend change being tested without
# the UI change it needs. But it left nothing to come back afterwards: on
# 2026-08-17 a correctly batched set of eight candidates sat queued for
# nineteen minutes, long past its five-minute window, because the last event
# that could have drained it was the registration that declined to.
#
# So the tick is not a safety net any more, it is the only drain path, and the
# hub does not deploy anything without it.
#
# Every minute: the window is five, so the cost is up to a minute of extra
# latency on a pipeline that takes twenty, and the watchdog's reaping is
# similarly insensitive to a minute either way. Unauthenticated by design —
# the plain tick only starts a transaction that was already due to start.
# `?force=1` skips the window and requires the bearer PAT; nothing scheduled
# should ever use it.
resource "google_cloud_scheduler_job" "hub_tick" {
  name        = "unifeed-hub-tick"
  project     = var.project_id
  region      = var.region
  description = "Drains the settled candidate queue and reaps stale deploy transactions"

  schedule  = "* * * * *"
  time_zone = "Etc/UTC" # what the API normalises to; "UTC" here is a permadiff

  http_target {
    # The service's own URL, not a vanity hostname. This job already existed,
    # pointing at https://test.dev.unifeed.io/api/tick, and that host was
    # removed on 2026-08-12 — so the hub's clock had been firing into nothing
    # for five days, which is why crashed transactions kept needing to be
    # cleared by hand. A reference the deploy cannot outlive is the fix; a
    # hostname in a string is what broke.
    uri         = "${google_cloud_run_v2_service.unifeed_test_runner.uri}/api/tick"
    http_method = "GET"
  }

  # A missed tick is picked up by the next one sixty seconds later, and every
  # action behind this endpoint is idempotent. Retrying would only stack ticks
  # on a hub that is already slow to answer.
  retry_config {
    retry_count = 0
  }
}
