# Multi-Tenant Dev Environment
# Project: breathe-dev-env (existing, cleaned)

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
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

provider "cloudflare" {
  api_token = var.cloudflare_api_token
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

resource "google_storage_bucket" "baskets" {
  project                     = var.project_id
  name                        = "${var.project_id}-baskets"
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = true

  labels = {
    environment = var.environment
    managed_by  = "terraform"
  }
}

resource "google_storage_bucket" "artwork" {
  project                     = var.project_id
  name                        = "${var.project_id}-artwork"
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = true

  labels = {
    environment = var.environment
    managed_by  = "terraform"
  }
}

resource "google_storage_bucket" "uploaded_artwork" {
  project                     = var.project_id
  name                        = "${var.project_id}-uploaded-artwork"
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = true

  labels = {
    environment = var.environment
    managed_by  = "terraform"
  }
}

resource "google_storage_bucket" "cost_pricing" {
  project                     = var.project_id
  name                        = "${var.project_id}-cost-pricing"
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

resource "google_storage_bucket_iam_member" "backend_baskets" {
  bucket = google_storage_bucket.baskets.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.backend.email}"
}

resource "google_storage_bucket_iam_member" "backend_artwork" {
  bucket = google_storage_bucket.artwork.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.backend.email}"
}

resource "google_storage_bucket_iam_member" "backend_uploaded_artwork" {
  bucket = google_storage_bucket.uploaded_artwork.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.backend.email}"
}

resource "google_storage_bucket_iam_member" "backend_cost_pricing" {
  bucket = google_storage_bucket.cost_pricing.name
  role   = "roles/storage.objectAdmin"
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

# Grant backend access to Zitadel service account key (for role lookups)
resource "google_secret_manager_secret_iam_member" "backend_zitadel_sa" {
  project   = var.shared_project_id
  secret_id = "zitadel-service-account-key"
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.backend.email}"
}

# Grant backend access to Typesense API key (catalogue search proxy)
resource "google_secret_manager_secret_iam_member" "backend_typesense" {
  project   = var.shared_project_id
  secret_id = "typesense-api-key"
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.backend.email}"
}

# Grant backend access to Anthropic API key (LLM classification)
resource "google_secret_manager_secret_iam_member" "backend_anthropic" {
  project   = var.shared_project_id
  secret_id = "anthropic-api-key"
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.backend.email}"
}

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

# Grant catalogue job access to supplier secrets
resource "google_secret_manager_secret_iam_member" "catalogue_supplier_secrets" {
  for_each = toset([
    "typesense-api-key",
    "preseli-secret-key",
    "impression-europe-password",
    "xoopar-password",
    "outdoors-company-user-token",
    "keramikos-password",
    "umbrella-api-key",
    "laltex-api-key",
    "bic-graphic-client-secret",
    "bic-graphic-password",
    "crystal-galleries-api-key",
  ])

  project   = var.shared_project_id
  secret_id = each.value
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
        value = "BREATHE_WEST2_TEST"
      }

      # Database
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
        name = "DB_PASSWORD"
        value_source {
          secret_key_ref {
            secret  = "projects/${var.shared_project_id}/secrets/db-app-password"
            version = "latest"
          }
        }
      }

      # GCP project
      env {
        name  = "GCP_PROJECT"
        value = var.project_id
      }

      # GCS Buckets
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
        name  = "GCS_BASKET_BUCKET"
        value = google_storage_bucket.baskets.name
      }
      env {
        name  = "GCS_ARTWORK_BUCKET"
        value = google_storage_bucket.artwork.name
      }
      env {
        name  = "GCS_UPLOADED_ARTWORK_BUCKET"
        value = google_storage_bucket.uploaded_artwork.name
      }
      env {
        name  = "GCS_COST_PRICING_BUCKET"
        value = google_storage_bucket.cost_pricing.name
      }

      # Service URLs (self-reference uses the known Cloud Run URL pattern)
      env {
        name  = "SERVICE_URL_ECOMMERCE"
        value = "http://localhost:8080"
      }
      env {
        name  = "SERVICE_URL_CUSTOMER"
        value = "https://dev.breathebranding.co.uk"
      }
      env {
        name  = "PDF_SERVICE_URL"
        value = google_cloud_run_v2_service.pdf.uri
      }

      # Typesense (catalogue search proxy)
      env {
        name  = "TYPESENSE_COLLECTION"
        value = "catalogue_dev"
      }
      env {
        name = "TYPESENSE_API_KEY"
        value_source {
          secret_key_ref {
            secret  = "projects/${var.shared_project_id}/secrets/typesense-api-key"
            version = "latest"
          }
        }
      }

      # Anthropic API (LLM classification)
      env {
        name = "ANTHROPIC_API_KEY"
        value_source {
          secret_key_ref {
            secret  = "projects/${var.shared_project_id}/secrets/anthropic-api-key"
            version = "latest"
          }
        }
      }

      # Auth
      env {
        name  = "AUTH_ISSUER"
        value = var.auth_issuer_url
      }
      env {
        name = "ZITADEL_SERVICE_ACCOUNT_KEY"
        value_source {
          secret_key_ref {
            secret  = "projects/${var.shared_project_id}/secrets/zitadel-service-account-key"
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
        command = ["/product-catalogue-0.0.1/bin/product-catalogue"]

        resources {
          limits = {
            cpu    = "2"
            memory = "4Gi"
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

        # CDN for cached images
        env {
          name  = "CDN_BASE_URL"
          value = "https://cdn.dev.breathebranding.co.uk"
        }

        # Typesense
        env {
          name  = "TYPESENSE_COLLECTION"
          value = "catalogue_dev"
        }
        env {
          name = "TYPESENSE_API_KEY"
          value_source {
            secret_key_ref {
              secret  = "projects/${var.shared_project_id}/secrets/typesense-api-key"
              version = "latest"
            }
          }
        }

        # SP001 PF Concept
        env {
          name  = "PF_ENABLED"
          value = "true"
        }
        env {
          name  = "PF_FEEDS_BUCKET"
          value = google_storage_bucket.raw_feeds.name
        }

        # SP002 Preseli
        env {
          name  = "PRESELI_ENABLED"
          value = "true"
        }
        env {
          name  = "PRESELI_CLIENT_ID"
          value = "MzM4Nw==7WIM3Vw5vrjJd64_CzmOb0BS8DtixNauRQXFeHnKyq"
        }
        env {
          name = "PRESELI_SECRET_KEY"
          value_source {
            secret_key_ref {
              secret  = "projects/${var.shared_project_id}/secrets/preseli-secret-key"
              version = "latest"
            }
          }
        }

        # SP003 Impression Europe
        env {
          name  = "IMPRESSION_EUROPE_ENABLED"
          value = "true"
        }
        env {
          name  = "IMPRESSION_EUROPE_USERNAME"
          value = "pa-promotions"
        }
        env {
          name = "IMPRESSION_EUROPE_PASSWORD"
          value_source {
            secret_key_ref {
              secret  = "projects/${var.shared_project_id}/secrets/impression-europe-password"
              version = "latest"
            }
          }
        }

        # SP005 Outdoors Company
        env {
          name  = "OUTDOORS_COMPANY_ENABLED"
          value = "true"
        }
        env {
          name = "OUTDOORS_COMPANY_USER_TOKEN"
          value_source {
            secret_key_ref {
              secret  = "projects/${var.shared_project_id}/secrets/outdoors-company-user-token"
              version = "latest"
            }
          }
        }

        # SP006 Xoopar
        env {
          name  = "XOOPAR_ENABLED"
          value = "true"
        }
        env {
          name  = "XOOPAR_USERNAME"
          value = "PA_PROMOTIONS"
        }
        env {
          name = "XOOPAR_PASSWORD"
          value_source {
            secret_key_ref {
              secret  = "projects/${var.shared_project_id}/secrets/xoopar-password"
              version = "latest"
            }
          }
        }

        # SP007 Keramikos
        env {
          name  = "KERAMIKOS_ENABLED"
          value = "true"
        }
        env {
          name  = "KERAMIKOS_USERNAME"
          value = "tom@pa-promotions.co.uk"
        }
        env {
          name = "KERAMIKOS_PASSWORD"
          value_source {
            secret_key_ref {
              secret  = "projects/${var.shared_project_id}/secrets/keramikos-password"
              version = "latest"
            }
          }
        }

        # SP008 The Umbrella Company
        env {
          name  = "UMBRELLA_ENABLED"
          value = "true"
        }
        env {
          name = "UMBRELLA_API_KEY"
          value_source {
            secret_key_ref {
              secret  = "projects/${var.shared_project_id}/secrets/umbrella-api-key"
              version = "latest"
            }
          }
        }

        # SP004 BIC Graphic
        env {
          name  = "BIC_GRAPHIC_ENABLED"
          value = "true"
        }
        env {
          name  = "BIC_GRAPHIC_CLIENT_ID"
          value = "5de810b5-f818-4496-888a-ed129a260bc0"
        }
        env {
          name  = "BIC_GRAPHIC_USERNAME"
          value = "tom@pa-promotions.co.uk"
        }
        env {
          name = "BIC_GRAPHIC_CLIENT_SECRET"
          value_source {
            secret_key_ref {
              secret  = "projects/${var.shared_project_id}/secrets/bic-graphic-client-secret"
              version = "latest"
            }
          }
        }
        env {
          name = "BIC_GRAPHIC_PASSWORD"
          value_source {
            secret_key_ref {
              secret  = "projects/${var.shared_project_id}/secrets/bic-graphic-password"
              version = "latest"
            }
          }
        }

        # Laltex Group (SP009-SP013)
        env {
          name = "LALTEX_API_KEY"
          value_source {
            secret_key_ref {
              secret  = "projects/${var.shared_project_id}/secrets/laltex-api-key"
              version = "latest"
            }
          }
        }
        env {
          name  = "LALTEX_PRE_ENABLED"
          value = "true"
        }
        env {
          name  = "LALTEX_TPC_ENABLED"
          value = "true"
        }
        env {
          name  = "LALTEX_SRC_ENABLED"
          value = "true"
        }
        env {
          name  = "LALTEX_BHQ_ENABLED"
          value = "true"
        }
        env {
          name  = "LALTEX_FFP_ENABLED"
          value = "true"
        }

        # SP014 Crystal Galleries
        env {
          name  = "CRYSTAL_GALLERIES_ENABLED"
          value = "true"
        }
        env {
          name = "CRYSTAL_GALLERIES_API_KEY"
          value_source {
            secret_key_ref {
              secret  = "projects/${var.shared_project_id}/secrets/crystal-galleries-api-key"
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
  name             = "catalogue-feed-sync"
  project          = var.project_id
  region           = var.region
  description      = "Runs catalogue feed processor every 4 hours"
  schedule         = "0 */4 * * *"
  time_zone        = "Europe/London"
  attempt_deadline = "1800s"

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

resource "google_cloud_run_v2_job" "search_trim" {
  name     = "catalogue-search-trim"
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
      timeout         = "600s"
      max_retries     = 0

      vpc_access {
        connector = var.vpc_connector_id
        egress    = "PRIVATE_RANGES_ONLY"
      }

      containers {
        image   = "${var.region}-docker.pkg.dev/${var.shared_project_id}/breathe-backend/breathe-backend:latest"
        command = ["/product-catalogue-0.0.1/bin/product-catalogue"]

        resources {
          limits = {
            cpu    = "1"
            memory = "512Mi"
          }
        }

        env {
          name  = "JOB_TYPE"
          value = "SEARCH_TRIM"
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
          name  = "TYPESENSE_COLLECTION"
          value = "catalogue_dev"
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
        env {
          name = "TYPESENSE_API_KEY"
          value_source {
            secret_key_ref {
              secret  = "projects/${var.shared_project_id}/secrets/typesense-api-key"
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

resource "google_cloud_scheduler_job" "search_trim" {
  name             = "catalogue-search-trim"
  project          = var.project_id
  region           = var.region
  description      = "Daily trim of stale products from search index"
  schedule         = "30 2 * * *"
  time_zone        = "Europe/London"
  attempt_deadline = "600s"

  http_target {
    uri         = "https://${var.region}-run.googleapis.com/v2/projects/${var.project_id}/locations/${var.region}/jobs/catalogue-search-trim:run"
    http_method = "POST"

    oauth_token {
      service_account_email = google_service_account.scheduler.email
      scope                 = "https://www.googleapis.com/auth/cloud-platform"
    }
  }

  depends_on = [google_cloud_run_v2_job.search_trim]
}

# =============================================================================
# Cloud Run — Admin UI
# =============================================================================

resource "google_cloud_run_v2_service" "admin" {
  name     = "breathe-admin"
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
    service_account = google_service_account.admin.email

    scaling {
      min_instance_count = 0
      max_instance_count = 2
    }

    containers {
      image = "${var.region}-docker.pkg.dev/${var.shared_project_id}/breathe-admin/breathe-admin:latest"

      ports {
        container_port = 3000
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
        cpu_idle          = true
        startup_cpu_boost = true
      }

      env {
        name  = "NUXT_PUBLIC_ADMIN_API_URL"
        value = google_cloud_run_v2_service.backend.uri
      }
      env {
        name  = "NUXT_PUBLIC_BREATHE_ENV"
        value = var.environment
      }
      env {
        name  = "NUXT_PUBLIC_AUTH_ISSUER"
        value = var.auth_issuer_url
      }
      env {
        name  = "NUXT_PUBLIC_AUTH_CLIENT_ID"
        value = var.zitadel_admin_client_id
      }

      startup_probe {
        tcp_socket {
          port = 3000
        }
        initial_delay_seconds = 5
        timeout_seconds       = 5
        period_seconds        = 10
        failure_threshold     = 12
      }
    }

    timeout = "60s"
  }

  labels = {
    environment = var.environment
    managed_by  = "terraform"
  }

  depends_on = [google_project_service.apis]
}

resource "google_cloud_run_v2_service_iam_member" "admin_public" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.admin.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# =============================================================================
# Cloud Run — PDF Service
# =============================================================================

resource "google_cloud_run_v2_service" "pdf" {
  name     = "breathe-pdf"
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
    scaling {
      min_instance_count = 0
      max_instance_count = 3
    }

    containers {
      image = "${var.region}-docker.pkg.dev/${var.shared_project_id}/breathe-pdf/breathe-pdf:latest"

      ports {
        container_port = 3000
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "1Gi"
        }
        cpu_idle          = true
        startup_cpu_boost = true
      }

      env {
        name  = "NODE_ENV"
        value = "production"
      }
      env {
        name  = "PUPPETEER_EXECUTABLE_PATH"
        value = "/usr/bin/google-chrome-stable"
      }

      startup_probe {
        tcp_socket {
          port = 3000
        }
        initial_delay_seconds = 5
        timeout_seconds       = 5
        period_seconds        = 10
        failure_threshold     = 12
      }
    }

    timeout = "60s"
  }

  labels = {
    environment = var.environment
    managed_by  = "terraform"
  }

  depends_on = [google_project_service.apis]
}

resource "google_cloud_run_v2_service_iam_member" "pdf_public" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.pdf.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# =============================================================================
# Cloud Run — Nginx Reverse Proxy (serves product data + images from GCS)
# =============================================================================

resource "google_cloud_run_v2_service" "nginx" {
  name     = "breathe-nginx"
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
    execution_environment = "EXECUTION_ENVIRONMENT_GEN2"

    scaling {
      min_instance_count = 0
      max_instance_count = 5
    }

    containers {
      image = "${var.region}-docker.pkg.dev/${var.shared_project_id}/breathe-nginx/breathe-nginx:latest"

      ports { container_port = 80 }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
        cpu_idle          = true
        startup_cpu_boost = true
      }

      volume_mounts {
        name       = "generated"
        mount_path = "/generated"
      }
      volume_mounts {
        name       = "images"
        mount_path = "/images"
      }
    }

    volumes {
      name = "generated"
      gcs {
        bucket    = google_storage_bucket.product_data.name
        read_only = true
      }
    }
    volumes {
      name = "images"
      gcs {
        bucket    = google_storage_bucket.images.name
        read_only = true
      }
    }

    timeout = "60s"
  }

  labels = {
    environment = var.environment
    managed_by  = "terraform"
  }

  depends_on = [google_project_service.apis]
}

resource "google_cloud_run_v2_service_iam_member" "nginx_public" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.nginx.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# =============================================================================
# Load Balancer — routes custom domains to Cloud Run services
# =============================================================================

module "dev_lb" {
  source = "../../modules/platform-lb"

  project_id = var.project_id

  backends = {
    admin = {
      cloud_run_service = google_cloud_run_v2_service.admin.name
      region            = var.region
    }
    backend = {
      cloud_run_service = google_cloud_run_v2_service.backend.name
      region            = var.region
    }
    pdf = {
      cloud_run_service = google_cloud_run_v2_service.pdf.name
      region            = var.region
    }
    cdn = {
      cloud_run_service = google_cloud_run_v2_service.nginx.name
      region            = var.region
    }
  }

  host_rules = {
    admin = {
      hosts   = ["admin.dev.breathebranding.co.uk"]
      backend = "admin"
    }
    backend = {
      hosts   = ["api.dev.breathebranding.co.uk"]
      backend = "backend"
    }
    pdf = {
      hosts   = ["pdf.dev.breathebranding.co.uk"]
      backend = "pdf"
    }
    cdn = {
      hosts   = ["cdn.dev.breathebranding.co.uk"]
      backend = "cdn"
    }
  }

  default_backend = "backend"

  domains = [
    "admin.dev.breathebranding.co.uk",
    "api.dev.breathebranding.co.uk",
    "pdf.dev.breathebranding.co.uk",
    "cdn.dev.breathebranding.co.uk",
  ]
}

# =============================================================================
# Cloudflare DNS — dev environment domains
# =============================================================================

resource "cloudflare_record" "dev_services" {
  for_each = {
    "admin.dev" = "admin.dev"
    "api.dev"   = "api.dev"
    "pdf.dev"   = "pdf.dev"
    "cdn.dev"   = "cdn.dev"
  }

  zone_id = var.cloudflare_zone_id
  name    = each.value
  content = module.dev_lb.ip_address
  type    = "A"
  proxied = false  # DNS only — GCP managed SSL certs need direct resolution
  ttl     = 300
}
