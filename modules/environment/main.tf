# Environment-specific resources
# Creates service accounts, GCS buckets, and prepares for Cloud Run deployments

locals {
  env_prefix = "breathe-${var.environment}"
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
  bucket = var.shared_feeds_bucket
  role   = "roles/storage.objectViewer"
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
