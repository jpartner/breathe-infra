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

provider "cloudflare" {
  alias     = "unifeed"
  api_token = var.unifeed_cloudflare_api_token
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
    "cloudtasks.googleapis.com",
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

resource "google_service_account" "storefront" {
  project      = var.project_id
  account_id   = "sa-storefront"
  display_name = "Storefront Service Account"
  description  = "Service account for customer-facing storefront Cloud Run services"
}

# Storefront needs Secret Manager access for NextAuth session secrets
resource "google_secret_manager_secret_iam_member" "storefront_secrets" {
  for_each = toset([
    "storefront-breathe-auth-secret",
    "storefront-breathe-eu-auth-secret",
    "storefront-pa-auth-secret",
  ])

  project   = var.shared_project_id
  secret_id = each.value
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.storefront.email}"
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

# Grant backend access to Postmark API key (email notifications)
resource "google_secret_manager_secret_iam_member" "backend_postmark" {
  project   = var.shared_project_id
  secret_id = "postmark-api-key"
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
        image   = "${var.region}-docker.pkg.dev/${var.shared_project_id}/breathe-backend/breathe-backend:latest"
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
          value = "https://cdn.dev.unifeed.io/uk"
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
# PA Migration — read-only legacy data lookup service
# =============================================================================

resource "google_service_account" "pa_migration" {
  project      = var.project_id
  account_id   = "sa-pa-migration"
  display_name = "PA Migration Service Account"
  description  = "Service account for PA legacy lookup Cloud Run service"
}

resource "google_secret_manager_secret_iam_member" "pa_migration_api_key" {
  project   = var.shared_project_id
  secret_id = "pa-migration-api-key"
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.pa_migration.email}"
}

resource "google_cloud_run_v2_service" "pa_migration" {
  name     = "pa-migration"
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
    service_account = google_service_account.pa_migration.email

    scaling {
      min_instance_count = 0
      max_instance_count = 2
    }

    containers {
      image = "${var.region}-docker.pkg.dev/${var.shared_project_id}/pa-migration/pa-migration:latest"

      ports { container_port = 8080 }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
        cpu_idle          = true
        startup_cpu_boost = true
      }

      env {
        name = "PA_LEGACY_API_KEY"
        value_source {
          secret_key_ref {
            secret  = "projects/${var.shared_project_id}/secrets/pa-migration-api-key"
            version = "latest"
          }
        }
      }

      startup_probe {
        http_get {
          path = "/health"
          port = 8080
        }
        initial_delay_seconds = 2
        timeout_seconds       = 3
        period_seconds        = 5
        failure_threshold     = 5
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

resource "google_cloud_run_v2_service_iam_member" "pa_migration_public" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.pa_migration.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# =============================================================================
# Unifeed Backend
# =============================================================================

resource "google_cloud_run_v2_service" "unifeed_backend" {
  name     = "unifeed-backend"
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
      image = "${var.region}-docker.pkg.dev/${var.shared_project_id}/unifeed-backend/unifeed-backend:latest"

      ports { container_port = 8080 }

      resources {
        limits = {
          cpu    = "1"
          memory = "1Gi"
        }
        cpu_idle          = true
        startup_cpu_boost = true
      }

      env {
        name  = "DB_URL"
        value = "jdbc:postgresql://${var.db_host}:5432/unifeed_dev"
      }
      env {
        name  = "DB_USER"
        value = var.db_user
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
        name  = "TYPESENSE_HOST"
        value = var.typesense_host
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
      env {
        name  = "TYPESENSE_COLLECTION"
        value = "catalogue_uk"
      }
      env {
        name  = "ZITADEL_ISSUER"
        value = var.unifeed_zitadel_issuer
      }
      env {
        name = "UNIFEED_NOTIFICATIONS_POSTMARK_DEFAULT_API_KEY"
        value_source {
          secret_key_ref {
            secret  = "projects/${var.shared_project_id}/secrets/postmark-api-key"
            version = "latest"
          }
        }
      }
      env {
        name  = "UNIFEED_NOTIFICATIONS_POSTMARK_DEFAULT_FROM_EMAIL"
        value = "hello@breathebranding.co.uk"
      }
      env {
        name  = "UNIFEED_NOTIFICATIONS_POSTMARK_DEFAULT_ADMIN_EMAIL"
        value = "dev@breathebranding.co.uk"
      }

      startup_probe {
        http_get {
          path = "/health"
          port = 8080
        }
        initial_delay_seconds = 10
        timeout_seconds       = 5
        period_seconds        = 10
        failure_threshold     = 20
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

resource "google_cloud_run_v2_service_iam_member" "unifeed_backend_public" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.unifeed_backend.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# =============================================================================
# Unifeed Catalogue Feed Sync Job
# =============================================================================

resource "google_cloud_run_v2_job" "unifeed_catalogue_sync" {
  name     = "unifeed-catalogue-sync"
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
      service_account = google_service_account.backend.email
      timeout         = "3600s"
      max_retries     = 1

      vpc_access {
        connector = var.vpc_connector_id
        egress    = "PRIVATE_RANGES_ONLY"
      }

      containers {
        image   = "${var.region}-docker.pkg.dev/${var.shared_project_id}/unifeed-backend/unifeed-backend:latest"
        command = ["java", "-jar", "app.jar", "--spring.profiles.active=job"]

        resources {
          limits = {
            cpu    = "2"
            memory = "2Gi"
          }
        }

        # Job config
        env {
          name  = "JOB_TYPE"
          value = "FEED_SYNC"
        }
        env {
          name  = "CATALOGUE_CODE"
          value = "uk"
        }
        env {
          name  = "TRIGGERED_BY"
          value = "schedule"
        }

        # Database
        env {
          name  = "DB_URL"
          value = "jdbc:postgresql://${var.db_host}:5432/unifeed_dev"
        }
        env {
          name  = "DB_USER"
          value = var.db_user
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

        # Typesense
        env {
          name  = "TYPESENSE_HOST"
          value = var.typesense_host
        }
        env {
          name  = "TYPESENSE_COLLECTION"
          value = "catalogue_uk"
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

        # GCS buckets
        env {
          name  = "GCS_PRODUCT_DATA_BUCKET"
          value = "unifeed-catalogue-uk-dev"
        }
        env {
          name  = "GCS_RAW_FEED_BUCKET"
          value = "unifeed-catalogue-uk-dev"
        }
        env {
          name  = "GCS_IMAGES_BUCKET"
          value = "unifeed-catalogue-uk-dev"
        }
        env {
          name  = "CDN_BASE_URL"
          value = "https://cdn.dev.unifeed.io/uk"
        }

        # PF Concept (SP001)
        env {
          name  = "PF_ENABLED"
          value = "true"
        }
        env {
          name  = "PF_FEEDS_BUCKET"
          value = "unifeed-catalogue-uk-dev"
        }

        # Preseli (SP002)
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

        # Impression Europe (SP003)
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

        # Outdoors (SP005)
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

        # Xoopar (SP006)
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

        # Keramikos (SP007)
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

        # Umbrella (SP008)
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

        # BIC Graphic (SP004)
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

        # Laltex (SP009-SP013)
        env {
          name = "LALTEX_API_KEY"
          value_source {
            secret_key_ref {
              secret  = "projects/${var.shared_project_id}/secrets/laltex-api-key"
              version = "latest"
            }
          }
        }

        # Crystal Galleries (SP014)
        env {
          name = "CRYSTAL_GALLERIES_API_KEY"
          value_source {
            secret_key_ref {
              secret  = "projects/${var.shared_project_id}/secrets/crystal-galleries-api-key"
              version = "latest"
            }
          }
        }

        # Midocean (SP015)
        env {
          name = "MIDOCEAN_API_KEY"
          value_source {
            secret_key_ref {
              secret  = "projects/${var.shared_project_id}/secrets/midocean-api-key"
              version = "latest"
            }
          }
        }

        # USB Group (SP017)
        env {
          name = "USB_GROUP_API_KEY"
          value_source {
            secret_key_ref {
              secret  = "projects/${var.shared_project_id}/secrets/usbgroup-api-key"
              version = "latest"
            }
          }
        }

        # Pinpoint (SP018)
        env {
          name = "PINPOINT_PASSWORD"
          value_source {
            secret_key_ref {
              secret  = "projects/${var.shared_project_id}/secrets/pinpoint-api-key"
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

# =============================================================================
# Unifeed Storefronts — one image, three services
# =============================================================================

resource "google_cloud_run_v2_service" "storefront_breathe" {
  name     = "storefront-breathe"
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
    service_account = google_service_account.storefront.email

    scaling {
      min_instance_count = 0
      max_instance_count = 2
    }

    containers {
      image = "${var.region}-docker.pkg.dev/${var.shared_project_id}/unifeed-storefront/unifeed-storefront:latest"
      ports { container_port = 3000 }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
        cpu_idle          = true
        startup_cpu_boost = true
      }

      env {
        name  = "API_URL"
        value = "https://api.dev.unifeed.io"
      }
      env {
        name  = "TENANT_CODE"
        value = "breathe"
      }
      env {
        name  = "AUTH_ZITADEL_ISSUER"
        value = var.unifeed_zitadel_issuer
      }
      env {
        name  = "AUTH_ZITADEL_ID"
        value = var.storefront_breathe_client_id
      }
      env {
        name = "AUTH_SECRET"
        value_source {
          secret_key_ref {
            secret  = "projects/${var.shared_project_id}/secrets/storefront-breathe-auth-secret"
            version = "latest"
          }
        }
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

resource "google_cloud_run_v2_service_iam_member" "storefront_breathe_public" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.storefront_breathe.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_cloud_run_v2_service" "storefront_breathe_eu" {
  name     = "storefront-breathe-eu"
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
    service_account = google_service_account.storefront.email

    scaling {
      min_instance_count = 0
      max_instance_count = 2
    }

    containers {
      image = "${var.region}-docker.pkg.dev/${var.shared_project_id}/unifeed-storefront/unifeed-storefront:latest"
      ports { container_port = 3000 }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
        cpu_idle          = true
        startup_cpu_boost = true
      }

      env {
        name  = "API_URL"
        value = "https://api.dev.unifeed.io"
      }
      env {
        name  = "TENANT_CODE"
        value = "breathe-eu"
      }
      env {
        name  = "AUTH_ZITADEL_ISSUER"
        value = var.unifeed_zitadel_issuer
      }
      env {
        name  = "AUTH_ZITADEL_ID"
        value = var.storefront_breathe_client_id
      }
      env {
        name = "AUTH_SECRET"
        value_source {
          secret_key_ref {
            secret  = "projects/${var.shared_project_id}/secrets/storefront-breathe-eu-auth-secret"
            version = "latest"
          }
        }
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

resource "google_cloud_run_v2_service_iam_member" "storefront_breathe_eu_public" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.storefront_breathe_eu.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_cloud_run_v2_service" "storefront_pa" {
  name     = "storefront-pa"
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
    service_account = google_service_account.storefront.email

    scaling {
      min_instance_count = 0
      max_instance_count = 2
    }

    containers {
      image = "${var.region}-docker.pkg.dev/${var.shared_project_id}/unifeed-storefront/unifeed-storefront:latest"
      ports { container_port = 3000 }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
        cpu_idle          = true
        startup_cpu_boost = true
      }

      env {
        name  = "API_URL"
        value = "https://api.dev.unifeed.io"
      }
      env {
        name  = "TENANT_CODE"
        value = "pa"
      }
      env {
        name  = "AUTH_ZITADEL_ISSUER"
        value = var.unifeed_zitadel_issuer
      }
      env {
        name  = "AUTH_ZITADEL_ID"
        value = var.storefront_pa_client_id
      }
      env {
        name = "AUTH_SECRET"
        value_source {
          secret_key_ref {
            secret  = "projects/${var.shared_project_id}/secrets/storefront-pa-auth-secret"
            version = "latest"
          }
        }
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

resource "google_cloud_run_v2_service_iam_member" "storefront_pa_public" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.storefront_pa.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# =============================================================================
# Uniten — test tenant storefront for automated testing
# =============================================================================

resource "google_cloud_run_v2_service" "storefront_uniten" {
  name     = "storefront-uniten"
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
      max_instance_count = 1
    }

    containers {
      image = "${var.region}-docker.pkg.dev/${var.shared_project_id}/unifeed-storefront/uniten:latest"
      ports { container_port = 3000 }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
        cpu_idle          = true
        startup_cpu_boost = true
      }

      env {
        name  = "API_URL"
        value = "https://api.dev.unifeed.io"
      }
      env {
        name  = "TENANT_CODE"
        value = "uniten"
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

resource "google_cloud_run_v2_service_iam_member" "storefront_uniten_public" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.storefront_uniten.name
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
    pa = {
      cloud_run_service = google_cloud_run_v2_service.pa_migration.name
      region            = var.region
    }
    unifeed-api = {
      cloud_run_service = google_cloud_run_v2_service.unifeed_backend.name
      region            = var.region
    }
    storefront-breathe = {
      cloud_run_service = google_cloud_run_v2_service.storefront_breathe.name
      region            = var.region
    }
    storefront-breathe-eu = {
      cloud_run_service = google_cloud_run_v2_service.storefront_breathe_eu.name
      region            = var.region
    }
    storefront-pa = {
      cloud_run_service = google_cloud_run_v2_service.storefront_pa.name
      region            = var.region
    }
    storefront-uniten = {
      cloud_run_service = google_cloud_run_v2_service.storefront_uniten.name
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
    pa = {
      hosts   = ["pa.dev.breathebranding.co.uk"]
      backend = "pa"
    }
    unifeed-api = {
      hosts   = ["api.dev.unifeed.io"]
      backend = "unifeed-api"
    }
    storefront-breathe = {
      hosts   = ["shop.dev.breathebranding.co.uk"]
      backend = "storefront-breathe"
    }
    storefront-breathe-eu = {
      hosts   = ["dev.breathebranding.eu"]
      backend = "storefront-breathe-eu"
    }
    storefront-pa = {
      hosts   = ["pa.dev.unifeed.io"]
      backend = "storefront-pa"
    }
    storefront-uniten = {
      hosts   = ["uniten.dev.unifeed.io"]
      backend = "storefront-uniten"
    }
  }

  default_backend = "backend"

  domains = [
    "admin.dev.breathebranding.co.uk",
    "api.dev.breathebranding.co.uk",
    "pdf.dev.breathebranding.co.uk",
    "cdn.dev.breathebranding.co.uk",
    "pa.dev.breathebranding.co.uk",
    "api.dev.unifeed.io",
    "shop.dev.breathebranding.co.uk",
    "dev.breathebranding.eu",
    "pa.dev.unifeed.io",
    "uniten.dev.unifeed.io",
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
    "pa.dev"    = "pa.dev"
    "shop.dev"  = "shop.dev"
  }

  zone_id = var.cloudflare_zone_id
  name    = each.value
  content = module.dev_lb.ip_address
  type    = "A"
  proxied = false
  ttl     = 300
}

# Unifeed DNS — api.dev.unifeed.io, pa.dev.unifeed.io
resource "cloudflare_record" "dev_unifeed" {
  provider = cloudflare.unifeed

  for_each = {
    "api.dev"    = "api.dev"
    "pa.dev"     = "pa.dev"
    "uniten.dev" = "uniten.dev"
  }

  zone_id = var.unifeed_cloudflare_zone_id
  name    = each.value
  content = module.dev_lb.ip_address
  type    = "A"
  proxied = false
  ttl     = 300
}

# breathebranding.eu DNS — dev.breathebranding.eu
resource "cloudflare_record" "dev_breathe_eu" {
  provider = cloudflare.unifeed

  zone_id = var.breathe_eu_cloudflare_zone_id
  name    = "dev"
  content = module.dev_lb.ip_address
  type    = "A"
  proxied = false
  ttl     = 300
}

# =============================================================================
# Cloud Tasks — email retry queue
# =============================================================================

resource "google_cloud_tasks_queue" "email_retry" {
  name     = "email-retry"
  location = var.region
  project  = var.project_id

  retry_config {
    max_attempts  = 5
    min_backoff   = "300s"   # 5 minutes
    max_backoff   = "14400s" # 4 hours
    max_doublings = 3        # 5m → 10m → 20m → 40m → then linear to 4h
  }

  depends_on = [google_project_service.apis]
}

# Allow the backend SA to enqueue tasks
resource "google_project_iam_member" "backend_cloud_tasks_enqueuer" {
  project = var.project_id
  role    = "roles/cloudtasks.enqueuer"
  member  = "serviceAccount:${google_service_account.backend.email}"
}

# Allow Cloud Tasks to invoke the unifeed backend (OIDC auth for retry endpoint)
resource "google_cloud_run_v2_service_iam_member" "cloud_tasks_invoker" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.unifeed_backend.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.backend.email}"
}
