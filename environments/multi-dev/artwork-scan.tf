# =============================================================================
# Artwork library — virus scanning
# =============================================================================
#
# We accept arbitrary binaries at a public unauthenticated upload endpoint,
# store them, serve them to staff over signed URLs, and email some of them to
# suppliers. That last one is why this exists: a malicious file reaching a
# supplier is a reputational incident, not just an internal one.
#
# The intent predates this — Breathe stamps `scannedStatus: "notScanned"` on
# every uploaded object and nothing has ever read it.
#
# SCANNING RUNS BEFORE RENDERING. Ghostscript, libvips and resvg are themselves
# attack surface; handing them unscanned input would defeat the isolation
# unifeed-render is built around. Order matters more than either service does.

# -----------------------------------------------------------------------------
# Scanner identity
# -----------------------------------------------------------------------------

# Holds no permissions, for the same reason sa-render does not: the backend
# fetches the object, streams the bytes, and acts on the verdict itself. The
# scanner reads no GCS, no database and no secrets.
#
# The argument is even stronger here than for the renderer. ClamAV parses
# hostile input by design — it is the component most likely to be attacked, and
# historically has had its own CVEs. If it is compromised, it should be
# compromised into an identity that can do nothing.
resource "google_service_account" "scan" {
  project      = var.project_id
  account_id   = "sa-scan"
  display_name = "Upload Scanner"
  description  = "Runs unifeed-scan. Intentionally holds no IAM roles."
}

# -----------------------------------------------------------------------------
# The service
# -----------------------------------------------------------------------------

resource "google_cloud_run_v2_service" "unifeed_scan" {
  name     = "unifeed-scan"
  project  = var.project_id
  location = var.region

  # As with unifeed-render: internal-only is unreachable from the backend, whose
  # VPC egress is private-ranges-only. Access is IAM — sa-backend alone holds
  # run.invoker and presents an ID token. Never add allUsers.
  ingress = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = google_service_account.scan.email

    scaling {
      # Scales to zero deliberately. ClamAV holds a ~1GB signature database in
      # memory, so a cold start is tens of seconds — which would be unacceptable
      # on a synchronous upload path and is irrelevant on an asynchronous one.
      # Scanning is queued (below), the file stays unusable until a verdict
      # arrives, and nobody waits on it.
      #
      # If scanning ever moves onto the request path, this needs
      # min_instance_count = 1 and the standing cost of a warm 2Gi instance.
      # Change it deliberately, not because a scan felt slow once.
      min_instance_count = 0
      max_instance_count = 3
    }

    containers {
      # Placeholder until the first real build — Cloud Run cannot create a
      # service against an image that does not exist. The tag is ignored below,
      # as everywhere else here.
      #
      # NOTE for whoever wires the caller: until a real image is pushed this
      # returns HTML with a 200. A scanner that treats any 200 as "clean" would
      # mark every file safe. Verdicts must be parsed explicitly, and anything
      # unrecognised treated as NOT clean.
      image = "us-docker.pkg.dev/cloudrun/container/hello"

      ports { container_port = 8080 }

      resources {
        limits = {
          cpu = "1"
          # The signature database is the reason for 2Gi, not the files. Scanning
          # a small artwork file in a container that cannot load its signatures
          # fails in a way that looks like a corrupt upload.
          memory = "2Gi"
        }
        # Not cpu_idle: freshclam and the signature load want CPU between
        # requests, and throttling an idle instance makes the first scan after a
        # refresh far slower than it needs to be.
        cpu_idle          = false
        startup_cpu_boost = true
      }
    }

    # Generous because a cold start includes loading the signature database.
    # A scan that genuinely takes minutes means something is wrong with the
    # input, and the queue's retry limit bounds it.
    timeout = "300s"
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

resource "google_cloud_run_v2_service_iam_member" "scan_invoker" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.unifeed_scan.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.backend.email}"
}

# -----------------------------------------------------------------------------
# Scan queue
# -----------------------------------------------------------------------------

# Separate from thumbnails because the ordering is a dependency, not a
# preference: a file is scanned, and only a clean verdict makes it eligible for
# rendering. Sharing one queue would let a thumbnail backlog delay the scan that
# gates it.
#
# More patient than thumbnails. A failed thumbnail costs a preview; an
# unscanned file cannot be released to staff or suppliers at all, so it is worth
# retrying harder before giving up.
resource "google_cloud_tasks_queue" "scans" {
  name     = "scans"
  location = var.region
  project  = var.project_id

  retry_config {
    max_attempts  = 5
    min_backoff   = "30s"
    max_backoff   = "1800s"
    max_doublings = 4
  }

  depends_on = [google_project_service.apis]
}

# No new IAM: sa-backend already holds roles/cloudtasks.enqueuer project-wide,
# and Cloud Tasks can already invoke the backend's /internal endpoints.
