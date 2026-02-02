# Shared Project Infrastructure
# Contains: Artifact Registry, Cloud SQL, shared GCS buckets, networking,
#           Feed puller job (pulls once, shared across environments)

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
    postgresql = {
      source  = "cyrilgdn/postgresql"
      version = "~> 1.22"
    }
  }

  # Uncomment and configure for remote state
  # backend "gcs" {
  #   bucket = "breathe-terraform-state"
  #   prefix = "shared"
  # }
}

provider "google" {
  region = var.region
}

provider "google-beta" {
  region = var.region
}

# =============================================================================
# Project & Core Infrastructure
# =============================================================================

module "project" {
  source = "../../modules/project"

  project_name    = "Breathe Shared"
  project_id      = var.project_id
  billing_account = var.billing_account
  org_id          = var.org_id
  environment     = "shared"

  apis = [
    "cloudresourcemanager.googleapis.com",
    "serviceusage.googleapis.com",
    "iam.googleapis.com",
    "compute.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
    "run.googleapis.com",
    "sqladmin.googleapis.com",
    "sql-component.googleapis.com",
    "servicenetworking.googleapis.com",
    "secretmanager.googleapis.com",
    "vpcaccess.googleapis.com",
    "storage.googleapis.com",
    "cloudscheduler.googleapis.com",
  ]
}

module "networking" {
  source = "../../modules/networking"

  project_id = module.project.project_id
  region     = var.region

  depends_on = [module.project]
}

module "artifact_registry" {
  source = "../../modules/artifact-registry"

  project_id = module.project.project_id
  region     = var.region

  repositories = [
    "breathe-ecommerce",
    "breathe-pf-feed-processor",
    "breathe-nginx",
    "breathe-admin",
    "breathe-pricing-rust",
    "breathe-feed-puller",
  ]

  reader_projects = var.environment_project_numbers

  depends_on = [module.project]
}

# =============================================================================
# Cloud SQL (DO NOT MODIFY - data exists)
# =============================================================================

module "cloud_sql" {
  source = "../../modules/cloud-sql"

  project_id             = module.project.project_id
  region                 = var.region
  network_id             = module.networking.network_id
  private_vpc_connection = module.networking.private_vpc_connection

  instance_name       = "breathe-db"
  tier                = var.db_tier
  availability_type   = var.db_availability_type
  deletion_protection = var.environment == "production"

  databases = ["breathe_dev", "breathe_staging", "breathe_prod"]

  depends_on = [module.networking]
}

# =============================================================================
# Shared GCS Buckets
# =============================================================================

resource "google_storage_bucket" "feeds" {
  project                     = module.project.project_id
  name                        = "breathe-pf-feeds"
  location                    = var.region
  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      num_newer_versions = 5
    }
    action {
      type = "Delete"
    }
  }

  labels = {
    purpose    = "supplier-feeds"
    managed_by = "terraform"
  }

  depends_on = [module.project]
}

# =============================================================================
# Per-Environment Buckets (created in each environment project)
# =============================================================================

locals {
  environments = {
    dev = {
      project = "breathe-dev-env"
      sa      = "sa-ecommerce@breathe-dev-env.iam.gserviceaccount.com"
    }
    staging = {
      project = "breathe-staging-env"
      sa      = "sa-ecommerce@breathe-staging-env.iam.gserviceaccount.com"
    }
    prod = {
      project = "breathe-production-env"
      sa      = "sa-ecommerce@breathe-production-env.iam.gserviceaccount.com"
    }
  }
}

# Generated product data buckets (one per environment)
resource "google_storage_bucket" "generated_data" {
  for_each = local.environments

  project                     = each.value.project
  name                        = "breathe-${each.key}-generated-product-data"
  location                    = var.region
  uniform_bucket_level_access = true

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
    environment = each.key
    purpose     = "generated-product-data"
    managed_by  = "terraform"
  }
}

# Grant ecommerce SA access to generated data bucket
resource "google_storage_bucket_iam_member" "generated_data_access" {
  for_each = local.environments

  bucket = google_storage_bucket.generated_data[each.key].name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${each.value.sa}"
}

# Product images buckets (one per environment)
resource "google_storage_bucket" "images" {
  for_each = local.environments

  project                     = each.value.project
  name                        = "breathe-${each.key}-product-images"
  location                    = var.region
  uniform_bucket_level_access = true

  labels = {
    environment = each.key
    purpose     = "product-images"
    managed_by  = "terraform"
  }
}

# Grant ecommerce SA access to images bucket
resource "google_storage_bucket_iam_member" "images_access" {
  for_each = local.environments

  bucket = google_storage_bucket.images[each.key].name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${each.value.sa}"
}

resource "google_storage_bucket" "build_cache" {
  project                     = module.project.project_id
  name                        = "breathe-build-cache"
  location                    = var.region
  uniform_bucket_level_access = true

  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }

  labels = {
    purpose    = "build-cache"
    managed_by = "terraform"
  }

  depends_on = [module.project]
}

# =============================================================================
# Cloud Build Service Account & Permissions
# =============================================================================

resource "google_service_account" "cloudbuild" {
  project      = module.project.project_id
  account_id   = "sa-cloudbuild"
  display_name = "Cloud Build Service Account"
  description  = "Service account for Cloud Build to build and deploy services"

  depends_on = [module.project]
}

# Grant Cloud Build SA permission to push to Artifact Registry
resource "google_artifact_registry_repository_iam_member" "cloudbuild_writer" {
  for_each = toset([
    "breathe-ecommerce",
    "breathe-pf-feed-processor",
    "breathe-nginx",
    "breathe-admin",
    "breathe-pricing-rust",
    "breathe-feed-puller",
  ])

  project    = module.project.project_id
  location   = var.region
  repository = each.value
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.cloudbuild.email}"

  depends_on = [module.artifact_registry]
}

# Cloud Build SA permissions in shared project
resource "google_project_iam_member" "cloudbuild_vpc_user" {
  project = module.project.project_id
  role    = "roles/vpcaccess.user"
  member  = "serviceAccount:${google_service_account.cloudbuild.email}"
}

resource "google_project_iam_member" "cloudbuild_logs" {
  project = module.project.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.cloudbuild.email}"
}

# Cloud Build SA can deploy to Cloud Run in shared (for feed puller job)
resource "google_project_iam_member" "cloudbuild_run_admin_shared" {
  project = module.project.project_id
  role    = "roles/run.admin"
  member  = "serviceAccount:${google_service_account.cloudbuild.email}"
}

resource "google_project_iam_member" "cloudbuild_sa_user_shared" {
  project = module.project.project_id
  role    = "roles/iam.serviceAccountUser"
  member  = "serviceAccount:${google_service_account.cloudbuild.email}"
}

# Cloud Build SA permissions for each environment
resource "google_project_iam_member" "cloudbuild_run_admin" {
  for_each = toset(["breathe-dev-env", "breathe-staging-env", "breathe-production-env"])

  project = each.value
  role    = "roles/run.admin"
  member  = "serviceAccount:${google_service_account.cloudbuild.email}"
}

resource "google_project_iam_member" "cloudbuild_sa_user" {
  for_each = toset(["breathe-dev-env", "breathe-staging-env", "breathe-production-env"])

  project = each.value
  role    = "roles/iam.serviceAccountUser"
  member  = "serviceAccount:${google_service_account.cloudbuild.email}"
}

# Grant Cloud Run service agents from environment projects permission to use VPC connector
resource "google_project_iam_member" "cloudrun_vpc_user" {
  for_each = toset(var.environment_project_numbers)

  project = module.project.project_id
  role    = "roles/vpcaccess.user"
  member  = "serviceAccount:service-${each.value}@serverless-robot-prod.iam.gserviceaccount.com"
}

# Grant environment ecommerce service accounts access to DB password secret
resource "google_secret_manager_secret_iam_member" "db_password_accessor" {
  for_each = toset([
    "sa-ecommerce@breathe-dev-env.iam.gserviceaccount.com",
    "sa-ecommerce@breathe-staging-env.iam.gserviceaccount.com",
    "sa-ecommerce@breathe-production-env.iam.gserviceaccount.com",
  ])

  project   = module.project.project_id
  secret_id = module.cloud_sql.password_secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${each.value}"
}

# =============================================================================
# Cloud Build Triggers (All in europe-west2)
# GitHub connections configured manually in Cloud Console
# =============================================================================

# Backend (breathe-java) -> dev
resource "google_cloudbuild_trigger" "backend_dev" {
  project     = module.project.project_id
  name        = "breathe-backend-dev"
  description = "Build and deploy breathe-ecommerce backend to dev on push to v2"
  location    = var.region

  github {
    owner = var.github_owner
    name  = "breathe-java"

    push {
      branch = "^feed-processor-refactor$"
    }
  }

  filename = "cloudbuild.yaml"

  substitutions = {
    _DEPLOY_PROJECT        = "breathe-dev-env"
    _ENV_NAME              = "dev"
    _DB_NAME               = "breathe_dev"
    _DEPLOY_REGION         = var.region
    _AR_HOSTNAME           = "${var.region}-docker.pkg.dev"
    _SHARED_PROJECT        = module.project.project_id
    _CUSTOMER_FRONTEND_URL = "https://dev.breathebranding.co.uk"
  }

  service_account = google_service_account.cloudbuild.id

  depends_on = [module.project, google_service_account.cloudbuild]
}

# Pricing Rust service -> dev
resource "google_cloudbuild_trigger" "pricing_rust_dev" {
  project     = module.project.project_id
  name        = "breathe-pricing-rust-dev"
  description = "Build and deploy breathe-pricing-rust to dev on push to main"
  location    = var.region

  github {
    owner = var.github_owner
    name  = "breathe-pricing-rust"

    push {
      branch = "^main$"
    }
  }

  filename = "cloudbuild.yaml"

  substitutions = {
    _IMAGE          = "${var.region}-docker.pkg.dev/${module.project.project_id}/breathe-pricing-rust/breathe-pricing-rust"
    _DEPLOY_PROJECT = "breathe-dev-env"
    _SERVICE_NAME   = "breathe-pricing-rust"
    _VPC_CONNECTOR  = "projects/${module.project.project_id}/locations/${var.region}/connectors/breathe-vpc-connector"
    _ENV_NAME       = "dev"
  }

  service_account = google_service_account.cloudbuild.id

  depends_on = [module.project, google_service_account.cloudbuild]
}

# Feed puller job -> shared (runs once for all environments)
resource "google_cloudbuild_trigger" "feed_puller" {
  project     = module.project.project_id
  name        = "breathe-feed-puller"
  description = "Build and deploy feed puller job to shared on push to v2"
  location    = var.region

  github {
    owner = var.github_owner
    name  = "breathe-gcp"

    push {
      branch = "^v2$"
    }
  }

  filename = "cloudbuild.yaml"

  substitutions = {
    _DEPLOY_PROJECT = module.project.project_id
    _ENV_NAME       = "shared"
    _DEPLOY_REGION  = var.region
    _AR_HOSTNAME    = "${var.region}-docker.pkg.dev"
    _SHARED_PROJECT = module.project.project_id
    _JOB_NAME       = "breathe-feed-puller"
  }

  service_account = google_service_account.cloudbuild.id

  depends_on = [module.project, google_service_account.cloudbuild]
}

# Admin UI -> dev
resource "google_cloudbuild_trigger" "admin_dev" {
  project     = module.project.project_id
  name        = "breathe-admin-dev"
  description = "Build and deploy admin UI to dev on push to v2"
  location    = var.region

  github {
    owner = var.github_owner
    name  = "breathe-admin-nuxt-claude"

    push {
      branch = "^v2$"
    }
  }

  filename = "cloudbuild.yaml"

  substitutions = {
    _DEPLOY_PROJECT   = "breathe-dev-env"
    _ENV_NAME         = "dev"
    _DEPLOY_REGION    = var.region
    _AR_HOSTNAME      = "${var.region}-docker.pkg.dev"
    _SHARED_PROJECT   = module.project.project_id
    _SERVICE_NAME     = "breathe-admin"
    _BACKEND_URL      = "https://breathe-ecommerce-815682864674.europe-west2.run.app"
    _TYPESENSE_API_KEY = ""
  }

  service_account = google_service_account.cloudbuild.id

  depends_on = [module.project, google_service_account.cloudbuild]
}

# =============================================================================
# Feed Puller Cloud Run Job (in breathe-shared)
# Pulls supplier feeds once, stores in shared bucket for all environments
# =============================================================================

# Service account for the feed puller job
resource "google_service_account" "feed_puller" {
  project      = module.project.project_id
  account_id   = "sa-feed-puller"
  display_name = "Feed Puller Job"
  description  = "Service account for the feed puller Cloud Run Job"

  depends_on = [module.project]
}

# Grant feed puller access to the feeds bucket
resource "google_storage_bucket_iam_member" "feed_puller_feeds_bucket" {
  bucket = google_storage_bucket.feeds.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.feed_puller.email}"
}

# Service account for Cloud Scheduler to invoke the job
resource "google_service_account" "scheduler_feed_puller" {
  project      = module.project.project_id
  account_id   = "sa-scheduler-feed-puller"
  display_name = "Cloud Scheduler - Feed Puller"
  description  = "Service account for Cloud Scheduler to invoke feed puller job"

  depends_on = [module.project]
}

# Grant scheduler SA permission to invoke Cloud Run Jobs
resource "google_project_iam_member" "scheduler_run_invoker" {
  project = module.project.project_id
  role    = "roles/run.invoker"
  member  = "serviceAccount:${google_service_account.scheduler_feed_puller.email}"
}

# Cloud Scheduler job - runs every hour
resource "google_cloud_scheduler_job" "feed_puller" {
  project     = module.project.project_id
  region      = var.region
  name        = "breathe-feed-puller-scheduler"
  description = "Triggers the feed puller Cloud Run Job every hour"
  schedule    = "0 * * * *"
  time_zone   = "Etc/UTC"

  http_target {
    http_method = "POST"
    uri         = "https://${var.region}-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/${module.project.project_id}/jobs/breathe-feed-puller:run"

    oauth_token {
      service_account_email = google_service_account.scheduler_feed_puller.email
      scope                 = "https://www.googleapis.com/auth/cloud-platform"
    }
  }

  retry_config {
    retry_count = 1
  }

  depends_on = [module.project]
}

# =============================================================================
# Database Schemas (Optional - requires Cloud SQL Proxy)
# To enable: terraform apply -var="manage_db_schemas=true" -var="db_admin_password=..."
#
# First start Cloud SQL Proxy:
#   cloud-sql-proxy --port 5432 breathe-shared:europe-west2:breathe-db
# =============================================================================

provider "postgresql" {
  host     = var.manage_db_schemas ? var.db_host : "localhost"
  port     = var.manage_db_schemas ? var.db_port : 5432
  username = var.manage_db_schemas ? var.db_admin_user : "disabled"
  password = var.manage_db_schemas ? var.db_admin_password : "disabled"
  sslmode  = "disable"

  connect_timeout = var.manage_db_schemas ? 15 : 1
  database        = "postgres"
}

module "database_schemas" {
  source = "../../modules/database-schemas"
  count  = var.manage_db_schemas ? 1 : 0

  databases    = module.cloud_sql.database_names
  schemas      = var.db_schemas
  schema_owner = var.db_admin_user
  app_user     = module.cloud_sql.app_user_name

  depends_on = [module.cloud_sql]
}
