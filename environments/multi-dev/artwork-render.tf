# =============================================================================
# Artwork library — thumbnail rendering
# =============================================================================
#
# Supports the artwork library in unifeed-backend (see
# UnifeedSystem/unifeed-backend/plans/artwork-library.md). Three pieces:
#
#   unifeed-render      rasterises artwork to thumbnails
#   uploads/ lifecycle  hard-deletes abandoned customer uploads
#   thumbnails queue    defers rendering off the request path
#
# Thumbnails degrade gracefully by design — files carry a thumbnail_status of
# PENDING/FAILED/UNSUPPORTED and the UI never blocks on one — so none of this is
# on a critical path.

# -----------------------------------------------------------------------------
# Renderer identity
# -----------------------------------------------------------------------------

# Deliberately holds NO permissions. The renderer takes bytes and returns bytes:
# it reads no GCS, no database and no secrets, because the backend fetches the
# object, streams it here, and writes the result itself.
#
# That is the whole point of a separate identity. This service runs Ghostscript,
# libvips and resvg over files uploaded by anonymous users through a public
# endpoint — the single most likely place in the platform to be handed a
# malicious file. If that ends in RCE, the attacker lands on an identity that
# can do nothing at all.
#
# unifeed-pdf runs as sa-storefront, which holds secret access. Do not copy that
# here, and do not grant this account anything "just to make something work" —
# if the renderer appears to need a permission, the design has drifted.
resource "google_service_account" "render" {
  project      = var.project_id
  account_id   = "sa-render"
  display_name = "Artwork Renderer"
  description  = "Runs unifeed-render. Intentionally holds no IAM roles."
}

# -----------------------------------------------------------------------------
# The service
# -----------------------------------------------------------------------------

resource "google_cloud_run_v2_service" "unifeed_render" {
  name     = "unifeed-render"
  project  = var.project_id
  location = var.region

  # INGRESS_TRAFFIC_ALL is correct here even though the service must never be
  # public, and this is the one setting most likely to be "tightened" by mistake.
  # The backend's VPC egress is private-ranges-only, so an internal-only service
  # is simply unreachable from it and every render fails. Access is enforced by
  # IAM instead: only sa-backend holds run.invoker (below) and it presents a
  # Cloud Run ID token. Never add allUsers — that would publish a rasteriser
  # that accepts arbitrary uploads.
  ingress = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = google_service_account.render.email

    scaling {
      min_instance_count = 0

      # Rasterising PDF/PSD is memory-hungry and this is a low-volume path. The
      # cap is a cost and blast-radius bound, not a throughput target: a burst of
      # malicious or pathological files cannot fan out into an unbounded number
      # of containers. Work queues behind it rather than scaling out.
      max_instance_count = 3
    }

    containers {
      # Placeholder until the first real build. Cloud Run cannot create a service
      # pointing at an image that does not exist, and the repository is empty
      # until CI pushes to it — so the service is created against Google's hello
      # image and the tag is ignored below, exactly as every other service here
      # ignores the tag CI moves.
      image = "us-docker.pkg.dev/cloudrun/container/hello"

      ports { container_port = 8080 }

      resources {
        limits = {
          cpu    = "1"
          memory = "1Gi"
        }
        cpu_idle          = true
        startup_cpu_boost = true
      }
    }

    # Rasterisation is slower than an API call and faster than a batch job. If
    # renders legitimately exceed this, queue them rather than raising it — a
    # long timeout on a memory-hungry path is how one bad file holds an instance.
    timeout = "120s"
  }

  labels = {
    environment = var.environment
    managed_by  = "terraform"
  }

  lifecycle {
    ignore_changes = [
      template[0].containers[0].image,
      template[0].labels,
      labels,
      client,
      client_version,
    ]
  }

  depends_on = [google_project_service.apis]
}

# The only grant that exists on this service.
resource "google_cloud_run_v2_service_iam_member" "render_invoker" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.unifeed_render.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.backend.email}"
}

# -----------------------------------------------------------------------------
# Thumbnail queue
# -----------------------------------------------------------------------------

# Separate from email-retry on purpose: a backlog of thumbnails must not delay
# customer email. Same shape as the notifications retry queue, but a thumbnail
# is worth less than an email, so it gives up sooner.
resource "google_cloud_tasks_queue" "thumbnails" {
  name     = "thumbnails"
  location = var.region
  project  = var.project_id

  retry_config {
    max_attempts  = 3
    min_backoff   = "10s"
    max_backoff   = "600s"
    max_doublings = 3
  }

  depends_on = [google_project_service.apis]
}

# sa-backend already holds roles/cloudtasks.enqueuer project-wide
# (google_project_iam_member.backend_cloud_tasks_enqueuer), which covers this
# queue, and Cloud Tasks already invokes the backend's /internal endpoints via
# google_cloud_run_v2_service_iam_member.cloud_tasks_invoker. No new IAM needed
# for the queue — noted here so nobody adds a redundant grant looking for it.
