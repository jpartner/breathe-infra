# Multi-Tenant Dev Environment
# Project: breathe-dev-env (existing, cleaned)

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  backend "gcs" {
    bucket = "breathe-terraform-state"
    prefix = "multi-dev"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# =============================================================================
# APIs
# =============================================================================

resource "google_project_service" "apis" {
  for_each = toset([
    "run.googleapis.com",
    "secretmanager.googleapis.com",
    "storage.googleapis.com",
    "cloudscheduler.googleapis.com",
    "iam.googleapis.com",
    "sqladmin.googleapis.com",
  ])

  project = var.project_id
  service = each.value

  disable_dependent_services = false
  disable_on_destroy         = false
}

# =============================================================================
# Service Accounts
# =============================================================================

resource "google_service_account" "backend" {
  project      = var.project_id
  account_id   = "sa-backend"
  display_name = "Backend Service Account"
  description  = "Service account for ecommerce + catalogue Cloud Run services"
}

resource "google_service_account" "admin" {
  project      = var.project_id
  account_id   = "sa-admin"
  display_name = "Admin UI Service Account"
}

resource "google_service_account" "catalogue_job" {
  project      = var.project_id
  account_id   = "sa-catalogue-job"
  display_name = "Catalogue Feed Processor Job"
}

resource "google_service_account" "scheduler" {
  project      = var.project_id
  account_id   = "sa-scheduler"
  display_name = "Cloud Scheduler"
}

# =============================================================================
# GCS Buckets
# =============================================================================

resource "google_storage_bucket" "product_data" {
  project                     = var.project_id
  name                        = "${var.project_id}-product-data"
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = true

  versioning { enabled = true }

  lifecycle_rule {
    condition { num_newer_versions = 3 }
    action { type = "Delete" }
  }

  labels = {
    environment = var.environment
    managed_by  = "terraform"
  }
}

resource "google_storage_bucket" "raw_feeds" {
  project                     = var.project_id
  name                        = "${var.project_id}-raw-feeds"
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = true

  versioning { enabled = true }

  labels = {
    environment = var.environment
    managed_by  = "terraform"
  }
}

resource "google_storage_bucket" "images" {
  project                     = var.project_id
  name                        = "${var.project_id}-images"
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = true

  labels = {
    environment = var.environment
    managed_by  = "terraform"
  }
}

# =============================================================================
# IAM — Backend service account
# =============================================================================

resource "google_project_iam_member" "backend_sql" {
  project = var.shared_project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.backend.email}"
}

resource "google_storage_bucket_iam_member" "backend_product_data" {
  bucket = google_storage_bucket.product_data.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.backend.email}"
}

resource "google_storage_bucket_iam_member" "backend_images" {
  bucket = google_storage_bucket.images.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.backend.email}"
}

# =============================================================================
# IAM — Catalogue job service account
# =============================================================================

resource "google_project_iam_member" "catalogue_sql" {
  project = var.shared_project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.catalogue_job.email}"
}

resource "google_storage_bucket_iam_member" "catalogue_product_data" {
  bucket = google_storage_bucket.product_data.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.catalogue_job.email}"
}

resource "google_storage_bucket_iam_member" "catalogue_raw_feeds" {
  bucket = google_storage_bucket.raw_feeds.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.catalogue_job.email}"
}

resource "google_storage_bucket_iam_member" "catalogue_images" {
  bucket = google_storage_bucket.images.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.catalogue_job.email}"
}

# =============================================================================
# Secrets — DB password is in breathe-shared, Stripe is per-environment
# =============================================================================

# Grant backend access to shared DB password
resource "google_secret_manager_secret_iam_member" "backend_db" {
  project   = var.shared_project_id
  secret_id = "db-app-password"
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.backend.email}"
}

# Grant catalogue job access to shared DB password
resource "google_secret_manager_secret_iam_member" "catalogue_db" {
  project   = var.shared_project_id
  secret_id = "db-app-password"
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.catalogue_job.email}"
}

# =============================================================================
# Cloud Run — Backend (ecommerce API)
# =============================================================================

resource "google_cloud_run_v2_service" "backend" {
  name     = "breathe-backend"
  project  = var.project_id
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  lifecycle {
    ignore_changes = [
      template[0].containers[0].image,
      template[0].labels,
      labels,
    ]
  }

  template {
    service_account = google_service_account.backend.email

    vpc_access {
      connector = var.vpc_connector_id
      egress    = "PRIVATE_RANGES_ONLY"
    }

    scaling {
      min_instance_count = 0
      max_instance_count = 3
    }

    containers {
      image = "${var.region}-docker.pkg.dev/${var.shared_project_id}/breathe-backend/breathe-backend:latest"

      ports { container_port = 8080 }

      resources {
        limits = {
          cpu    = "2"
          memory = "1Gi"
        }
        cpu_idle          = true
        startup_cpu_boost = true
      }

      env {
        name  = "BREATHE_ENV"
        value = var.environment
      }
      env {
        name  = "DB_NAME"
        value = var.db_name
      }
      env {
        name  = "DB_USER"
        value = var.db_user
      }
      env {
        name  = "CLOUD_SQL_INSTANCE"
        value = var.db_connection_name
      }
      env {
        name  = "GCS_PRODUCT_DATA_BUCKET"
        value = google_storage_bucket.product_data.name
      }
      env {
        name  = "GCS_RAW_FEEDS_BUCKET"
        value = google_storage_bucket.raw_feeds.name
      }
      env {
        name  = "GCS_IMAGES_BUCKET"
        value = google_storage_bucket.images.name
      }
      env {
        name  = "AUTH_ISSUER"
        value = var.auth_issuer_url
      }

      env {
        name = "DB_PASSWORD"
        value_source {
          secret_key_ref {
            secret  = "projects/${var.shared_project_id}/secrets/db-app-password"
            version = "latest"
          }
        }
      }

      startup_probe {
        tcp_socket { port = 8080 }
        initial_delay_seconds = 5
        timeout_seconds       = 5
        period_seconds        = 10
        failure_threshold     = 30
      }
    }

    timeout = "300s"
  }

  labels = {
    environment = var.environment
    managed_by  = "terraform"
  }

  depends_on = [google_project_service.apis]
}

resource "google_cloud_run_v2_service_iam_member" "backend_public" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.backend.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# =============================================================================
# Cloud Run Job — Catalogue Feed Processor
# =============================================================================

resource "google_cloud_run_v2_job" "catalogue" {
  name     = "catalogue-feed-processor"
  project  = var.project_id
  location = var.region

  lifecycle {
    ignore_changes = [
      template[0].template[0].containers[0].image,
      template[0].labels,
      labels,
    ]
  }

  template {
    task_count  = 1
    parallelism = 1

    template {
      service_account = google_service_account.catalogue_job.email
      timeout         = "3600s"
      max_retries     = 1

      vpc_access {
        connector = var.vpc_connector_id
        egress    = "PRIVATE_RANGES_ONLY"
      }

      containers {
        image = "${var.region}-docker.pkg.dev/${var.shared_project_id}/breathe-backend/breathe-backend:latest"
        command = ["java", "-cp", "/app/classpath/*:/app/libs/*", "com.breathe.catalogue.job.CatalogueJobRunnerKt"]

        resources {
          limits = {
            cpu    = "2"
            memory = "2Gi"
          }
        }

        env {
          name  = "JOB_TYPE"
          value = "FEED_SYNC"
        }
        env {
          name  = "DB_NAME"
          value = var.db_name
        }
        env {
          name  = "DB_USER"
          value = var.db_user
        }
        env {
          name  = "CLOUD_SQL_INSTANCE"
          value = var.db_connection_name
        }
        env {
          name  = "GCS_GENERATED_BUCKET"
          value = google_storage_bucket.product_data.name
        }
        env {
          name  = "GCS_RAW_FEEDS_BUCKET"
          value = google_storage_bucket.raw_feeds.name
        }
        env {
          name  = "GCS_IMAGES_BUCKET"
          value = google_storage_bucket.images.name
        }

        env {
          name = "DB_PASSWORD"
          value_source {
            secret_key_ref {
              secret  = "projects/${var.shared_project_id}/secrets/db-app-password"
              version = "latest"
            }
          }
        }
      }
    }
  }

  labels = {
    environment = var.environment
    managed_by  = "terraform"
  }

  depends_on = [google_project_service.apis]
}

# Scheduler can invoke the catalogue job
resource "google_project_iam_member" "scheduler_invoker" {
  project = var.project_id
  role    = "roles/run.invoker"
  member  = "serviceAccount:${google_service_account.scheduler.email}"
}

resource "google_cloud_scheduler_job" "catalogue" {
  name        = "catalogue-feed-sync"
  project     = var.project_id
  region      = var.region
  description = "Runs catalogue feed processor"
  schedule    = "0 */4 * * *" # Every 4 hours
  time_zone   = "Europe/London"

  http_target {
    uri         = "https://${var.region}-run.googleapis.com/v2/projects/${var.project_id}/locations/${var.region}/jobs/catalogue-feed-processor:run"
    http_method = "POST"

    oauth_token {
      service_account_email = google_service_account.scheduler.email
      scope                 = "https://www.googleapis.com/auth/cloud-platform"
    }
  }

  depends_on = [google_cloud_run_v2_job.catalogue]
}
