# Environment-specific resources
# Creates service accounts, GCS buckets, and prepares for Cloud Run deployments

locals {
  env_prefix = "breathe-${var.environment}"
  db_name    = var.db_name != "" ? var.db_name : "breathe_${var.environment}"
}

# Read Slack bot token from Secret Manager
data "google_secret_manager_secret_version" "slack_bot_token" {
  project = var.shared_project_id
  secret  = var.slack_bot_token_secret_id
}

# Service Accounts with minimal permissions
resource "google_service_account" "ecommerce" {
  project      = var.project_id
  account_id   = "sa-ecommerce"
  display_name = "Breathe Ecommerce Service Account"
  description  = "Service account for breathe-ecommerce Cloud Run service"
}

resource "google_service_account" "nginx" {
  project      = var.project_id
  account_id   = "sa-nginx"
  display_name = "Breathe Nginx Service Account"
  description  = "Service account for breathe-nginx Cloud Run service"
}

resource "google_service_account" "admin" {
  project      = var.project_id
  account_id   = "sa-admin"
  display_name = "Breathe Admin Service Account"
  description  = "Service account for breathe-admin Cloud Run service"
}

resource "google_service_account" "feed_processor" {
  project      = var.project_id
  account_id   = "sa-feed-processor"
  display_name = "Breathe Feed Processor Service Account"
  description  = "Service account for pf-feed-processor Cloud Run job"
}

resource "google_service_account" "scheduler" {
  project      = var.project_id
  account_id   = "sa-scheduler"
  display_name = "Breathe Scheduler Service Account"
  description  = "Service account for Cloud Scheduler to invoke jobs"
}

# Environment-specific GCS buckets
resource "google_storage_bucket" "artwork_uploaded" {
  project                     = var.project_id
  name                        = "${local.env_prefix}-artwork-uploaded"
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = var.environment != "production"

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      num_newer_versions = 3
    }
    action {
      type = "Delete"
    }
  }

  labels = {
    environment = var.environment
    managed_by  = "terraform"
  }
}

resource "google_storage_bucket" "artwork_processed" {
  project                     = var.project_id
  name                        = "${local.env_prefix}-artwork-processed"
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = var.environment != "production"

  labels = {
    environment = var.environment
    managed_by  = "terraform"
  }
}

resource "google_storage_bucket" "basket_storage" {
  project                     = var.project_id
  name                        = "${local.env_prefix}-basket-storage"
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = var.environment != "production"

  lifecycle_rule {
    condition {
      age = 30 # Delete baskets older than 30 days
    }
    action {
      type = "Delete"
    }
  }

  labels = {
    environment = var.environment
    managed_by  = "terraform"
  }
}

resource "google_storage_bucket" "cost_pricing" {
  project                     = var.project_id
  name                        = "${local.env_prefix}-cost-pricing"
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = var.environment != "production"

  versioning {
    enabled = true
  }

  labels = {
    environment = var.environment
    managed_by  = "terraform"
  }
}

resource "google_storage_bucket" "pf_feeds" {
  project                     = var.project_id
  name                        = "${local.env_prefix}-pf-feeds"
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = var.environment != "production"

  versioning {
    enabled = true
  }

  labels = {
    environment = var.environment
    managed_by  = "terraform"
  }
}

# IAM bindings for ecommerce service account
resource "google_project_iam_member" "ecommerce_sql" {
  project = var.shared_project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.ecommerce.email}"
}

resource "google_storage_bucket_iam_member" "ecommerce_cost_pricing" {
  bucket = google_storage_bucket.cost_pricing.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.ecommerce.email}"
}

resource "google_storage_bucket_iam_member" "ecommerce_basket" {
  bucket = google_storage_bucket.basket_storage.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.ecommerce.email}"
}

resource "google_storage_bucket_iam_member" "ecommerce_artwork_uploaded" {
  bucket = google_storage_bucket.artwork_uploaded.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.ecommerce.email}"
}

resource "google_storage_bucket_iam_member" "ecommerce_artwork_processed" {
  bucket = google_storage_bucket.artwork_processed.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.ecommerce.email}"
}

# IAM bindings for nginx service account (shared buckets)
resource "google_storage_bucket_iam_member" "nginx_generated_data" {
  bucket = var.shared_generated_data_bucket
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.nginx.email}"
}

resource "google_storage_bucket_iam_member" "nginx_images" {
  bucket = var.shared_images_bucket
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.nginx.email}"
}

# IAM bindings for feed processor service account
resource "google_project_iam_member" "feed_processor_sql" {
  project = var.shared_project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.feed_processor.email}"
}

resource "google_storage_bucket_iam_member" "feed_processor_feeds" {
  bucket = google_storage_bucket.pf_feeds.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.feed_processor.email}"
}

resource "google_storage_bucket_iam_member" "feed_processor_generated" {
  bucket = var.shared_generated_data_bucket
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.feed_processor.email}"
}

resource "google_storage_bucket_iam_member" "feed_processor_images" {
  bucket = var.shared_images_bucket
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.feed_processor.email}"
}

resource "google_storage_bucket_iam_member" "feed_processor_cost_pricing" {
  bucket = google_storage_bucket.cost_pricing.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.feed_processor.email}"
}

# Scheduler service account can invoke Cloud Run
resource "google_project_iam_member" "scheduler_run_invoker" {
  project = var.project_id
  role    = "roles/run.invoker"
  member  = "serviceAccount:${google_service_account.scheduler.email}"
}

# Secret Manager access for service accounts that need it
resource "google_secret_manager_secret_iam_member" "ecommerce_db_password" {
  project   = var.shared_project_id
  secret_id = var.db_password_secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.ecommerce.email}"
}

resource "google_secret_manager_secret_iam_member" "feed_processor_db_password" {
  project   = var.shared_project_id
  secret_id = var.db_password_secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.feed_processor.email}"
}

# =============================================================================
# Configuration Bucket and File
# =============================================================================

# Config bucket for storing environment configuration
resource "google_storage_bucket" "config" {
  project                     = var.project_id
  name                        = "${local.env_prefix}-config"
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = var.environment != "production"

  versioning {
    enabled = true
  }

  labels = {
    environment = var.environment
    managed_by  = "terraform"
    purpose     = "service-configuration"
  }
}

# Environment configuration file (non-secret values only)
resource "google_storage_bucket_object" "config" {
  name         = "config.json"
  bucket       = google_storage_bucket.config.name
  content_type = "application/json"

  content = jsonencode({
    environment = var.environment
    projectId   = var.project_id

    database = {
      host           = var.db_private_ip
      name           = local.db_name
      user           = var.db_user
      connectionName = var.db_connection_name
    }

    buckets = {
      # Shared buckets (cross-environment)
      generatedData = var.shared_generated_data_bucket
      images        = var.shared_images_bucket

      # Environment-specific buckets
      feeds            = google_storage_bucket.pf_feeds.name
      artworkUploaded  = google_storage_bucket.artwork_uploaded.name
      artworkProcessed = google_storage_bucket.artwork_processed.name
      basketStorage    = google_storage_bucket.basket_storage.name
      costPricing      = google_storage_bucket.cost_pricing.name
      config           = google_storage_bucket.config.name
    }

    services = {
      customerFrontendUrl = var.customer_frontend_url
      typesenseHost       = var.typesense_host
      ecommerceUrl        = var.ecommerce_url
    }

    vpcConnector = var.vpc_connector_id

    features = {
      enableImageCache = var.enable_image_cache
    }

    slack = {
      botToken              = data.google_secret_manager_secret_version.slack_bot_token.secret_data
      notificationChannelId = var.slack_notification_channel_id
    }

    secrets = {
      # Reference paths - services should mount these from Secret Manager
      dbPassword = "projects/${var.shared_project_id}/secrets/${var.db_password_secret_id}/versions/latest"
    }
  })
}

# Grant config bucket read access to all service accounts
resource "google_storage_bucket_iam_member" "config_ecommerce" {
  bucket = google_storage_bucket.config.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.ecommerce.email}"
}

resource "google_storage_bucket_iam_member" "config_feed_processor" {
  bucket = google_storage_bucket.config.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.feed_processor.email}"
}

resource "google_storage_bucket_iam_member" "config_nginx" {
  bucket = google_storage_bucket.config.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.nginx.email}"
}

resource "google_storage_bucket_iam_member" "config_admin" {
  bucket = google_storage_bucket.config.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.admin.email}"
}

# =============================================================================
# Cloud Scheduler for Feed Processor
# =============================================================================

resource "google_cloud_scheduler_job" "feed_processor" {
  name        = "pffeedprocessor-scheduler"
  project     = var.project_id
  region      = var.region
  description = "Runs feed processor hourly to check for feed updates and process product data"
  schedule    = "0 * * * *"
  time_zone   = "Etc/UTC"

  http_target {
    uri         = "https://${var.region}-run.googleapis.com/v2/projects/${var.project_id}/locations/${var.region}/jobs/pffeedprocessor:run"
    http_method = "POST"

    oauth_token {
      service_account_email = google_service_account.scheduler.email
      scope                 = "https://www.googleapis.com/auth/cloud-platform"
    }
  }

  retry_config {
    min_backoff_duration = "5s"
    max_backoff_duration = "3600s"
    max_doublings        = 5
  }

  depends_on = [google_cloud_run_v2_job.feed_processor]
}

# =============================================================================
# Cloud Run Service - Ecommerce
# =============================================================================

resource "google_cloud_run_v2_service" "ecommerce" {
  name     = "breathe-ecommerce"
  project  = var.project_id
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  # Ignore image changes - deployments are managed via admin tool/CI, not Terraform
  lifecycle {
    ignore_changes = [
      template[0].containers[0].image,
      template[0].labels,
      labels,
    ]
  }

  template {
    service_account = google_service_account.ecommerce.email

    vpc_access {
      connector = var.vpc_connector_id
      egress    = "PRIVATE_RANGES_ONLY"
    }

    scaling {
      min_instance_count = 0
      max_instance_count = 2
    }

    containers {
      image = "${var.region}-docker.pkg.dev/${var.shared_project_id}/breathe-ecommerce/breathe-ecommerce:${var.ecommerce_image_tag}"

      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = "2"
          memory = "1Gi"
        }
        cpu_idle          = true
        startup_cpu_boost = true
      }

      env {
        name  = "CONFIG_BUCKET"
        value = google_storage_bucket.config.name
      }

      env {
        name = "DB_PASSWORD"
        value_source {
          secret_key_ref {
            secret  = "projects/${var.shared_project_id}/secrets/${var.db_password_secret_id}"
            version = "latest"
          }
        }
      }

      startup_probe {
        tcp_socket {
          port = 8080
        }
        initial_delay_seconds = 5
        timeout_seconds       = 5
        period_seconds        = 10
        failure_threshold     = 30  # 30 * 10s = 5 minutes max startup time
      }
    }

    timeout = "300s"
  }

  labels = {
    environment = var.environment
    managed_by  = "terraform"
  }
}

# Grant scheduler ability to invoke the ecommerce service
resource "google_cloud_run_v2_service_iam_member" "ecommerce_invoker" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.ecommerce.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# =============================================================================
# Cloud Run Job - Feed Processor
# =============================================================================

resource "google_cloud_run_v2_job" "feed_processor" {
  name     = "pffeedprocessor"
  project  = var.project_id
  location = var.region

  # Ignore image changes - deployments are managed via admin tool/CI, not Terraform
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
      service_account = google_service_account.feed_processor.email
      timeout         = "3600s"
      max_retries     = 3

      vpc_access {
        connector = var.vpc_connector_id
        egress    = "PRIVATE_RANGES_ONLY"
      }

      containers {
        image = "${var.region}-docker.pkg.dev/${var.shared_project_id}/breathe-pf-feed-processor/breathe-pf-feed-processor:${var.feed_processor_image_tag}"

        resources {
          limits = {
            cpu    = "8"
            memory = "4Gi"
          }
        }

        env {
          name  = "CONFIG_BUCKET"
          value = google_storage_bucket.config.name
        }

        env {
          name  = "ENABLE_IMAGE_CACHE"
          value = tostring(var.enable_image_cache)
        }

        env {
          name = "DB_PASSWORD"
          value_source {
            secret_key_ref {
              secret  = "projects/${var.shared_project_id}/secrets/${var.db_password_secret_id}"
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
}

# Grant scheduler ability to invoke the feed processor job
resource "google_cloud_run_v2_job_iam_member" "feed_processor_invoker" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_job.feed_processor.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.scheduler.email}"
}
