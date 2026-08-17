# =============================================================================
# Build caches
# =============================================================================

# Gradle dependency and build cache for unifeed-backend.
#
# The backend build compiles from cold every time: Gradle runs inside `docker
# build`, which in Cloud Build has no layer cache unless --cache-from is passed,
# so every push re-resolves every dependency and recompiles every module. That
# is most of an 8m34s build against ~5-6m for the equivalent Breathe service,
# which restores a Gradle cache from GCS instead.
#
# Breathe's cache lives in gs://breathe-build-caches, in a different project
# that this project's build account cannot read — hence a bucket of our own
# rather than sharing theirs.
#
# Contents are disposable by construction: every consumer treats a restore
# failure as a cache miss and carries on, so losing this bucket costs build
# minutes and nothing else.
resource "google_storage_bucket" "build_caches" {
  project                     = var.project_id
  name                        = "${var.project_id}-build-caches"
  location                    = var.region
  uniform_bucket_level_access = true

  # A cache nobody has read in a fortnight is not a cache, it is storage for a
  # branch that stopped building. Short enough to stay cheap, long enough to
  # survive a quiet period without making the next build pay full price.
  lifecycle_rule {
    condition { age = 14 }
    action { type = "Delete" }
  }

  # The cache is rewritten every build; keeping old generations would multiply
  # a ~200MB object by every push for no recovery value.
  versioning {
    enabled = false
  }

  labels = {
    managed_by = "terraform"
  }
}

resource "google_storage_bucket_iam_member" "cloudbuild_build_caches" {
  bucket = google_storage_bucket.build_caches.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.cloudbuild.email}"
}
