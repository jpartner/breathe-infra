# Shared Project Infrastructure
# Contains: Artifact Registry, Cloud SQL, shared GCS buckets, networking

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

# Create the shared project
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
  ]
}

# Networking
module "networking" {
  source = "../../modules/networking"

  project_id = module.project.project_id
  region     = var.region

  depends_on = [module.project]
}

# Artifact Registry
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

  # Will be populated with environment project numbers after they're created
  reader_projects = var.environment_project_numbers

  depends_on = [module.project]
}

# Cloud SQL
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

# Shared GCS buckets
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

resource "google_storage_bucket" "generated_data" {
  project                     = module.project.project_id
  name                        = "breathe-generated-product-data"
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
    purpose    = "generated-product-data"
    managed_by = "terraform"
  }

  depends_on = [module.project]
}

resource "google_storage_bucket" "images" {
  project                     = module.project.project_id
  name                        = "breathe-product-images"
  location                    = var.region
  uniform_bucket_level_access = true

  labels = {
    purpose    = "product-images"
    managed_by = "terraform"
  }

  depends_on = [module.project]
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
# Cloud Build Triggers
# Note: GitHub connections must be set up manually in the Cloud Console first:
# https://console.cloud.google.com/cloud-build/repositories/2nd-gen
# =============================================================================

# Cloud Build trigger for breathe-pricing-rust -> dev
resource "google_cloudbuild_trigger" "pricing_rust_dev" {
  project     = module.project.project_id
  name        = "breathe-pricing-rust-dev"
  description = "Build and deploy breathe-pricing-rust to dev environment on push to main"
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
    _IMAGE         = "europe-west2-docker.pkg.dev/${module.project.project_id}/breathe-pricing-rust/breathe-pricing-rust"
    _DEPLOY_PROJECT = "breathe-dev-env"
    _SERVICE_NAME   = "breathe-pricing-rust"
    _VPC_CONNECTOR  = "projects/${module.project.project_id}/locations/${var.region}/connectors/breathe-vpc-connector"
    _ENV_NAME       = "dev"
  }

  service_account = google_service_account.cloudbuild.id

  depends_on = [module.project, google_service_account.cloudbuild]
}

# Service account for Cloud Build with necessary permissions
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

# Grant Cloud Build SA permission to deploy to Cloud Run in dev
resource "google_project_iam_member" "cloudbuild_run_admin_dev" {
  project = "breathe-dev-env"
  role    = "roles/run.admin"
  member  = "serviceAccount:${google_service_account.cloudbuild.email}"
}

# Grant Cloud Build SA permission to act as service accounts in dev
resource "google_project_iam_member" "cloudbuild_sa_user_dev" {
  project = "breathe-dev-env"
  role    = "roles/iam.serviceAccountUser"
  member  = "serviceAccount:${google_service_account.cloudbuild.email}"
}

# Grant Cloud Build SA permission to use VPC connector
resource "google_project_iam_member" "cloudbuild_vpc_user" {
  project = module.project.project_id
  role    = "roles/vpcaccess.user"
  member  = "serviceAccount:${google_service_account.cloudbuild.email}"
}

# Grant Cloud Build SA logging permissions
resource "google_project_iam_member" "cloudbuild_logs" {
  project = module.project.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.cloudbuild.email}"
}

# Grant Cloud Run service agents from environment projects permission to use VPC connector
resource "google_project_iam_member" "cloudrun_vpc_user" {
  for_each = toset(var.environment_project_numbers)

  project = module.project.project_id
  role    = "roles/vpcaccess.user"
  member  = "serviceAccount:service-${each.value}@serverless-robot-prod.iam.gserviceaccount.com"
}

# Cloud Build trigger for breathe-java backend -> dev
resource "google_cloudbuild_trigger" "backend_dev" {
  project     = module.project.project_id
  name        = "breathe-java-dev"
  description = "Build and deploy breathe-java backend to dev environment on push to main"
  location    = var.region

  github {
    owner = var.github_owner
    name  = "breathe-java"

    push {
      branch = "^main$"
    }
  }

  filename = "cloudbuild.yaml"

  substitutions = {
    _DEPLOY_PROJECT       = "breathe-dev-env"
    _ENV_NAME             = "dev"
    _DB_NAME              = "breathe_dev"
    _DEPLOY_REGION        = var.region
    _AR_HOSTNAME          = "${var.region}-docker.pkg.dev"
    _SHARED_PROJECT       = module.project.project_id
    _CUSTOMER_FRONTEND_URL = "https://dev.breathebranding.co.uk"
  }

  service_account = google_service_account.cloudbuild.id

  depends_on = [module.project, google_service_account.cloudbuild]
}

# Cloud Build trigger for breathe-gcp feed puller -> dev
resource "google_cloudbuild_trigger" "feed_puller_dev" {
  project     = module.project.project_id
  name        = "breathe-feed-puller-dev"
  description = "Build and deploy breathe-feed-puller job to dev environment on push to v2"
  location    = "global"  # Use global since GitHub connection exists there

  github {
    owner = var.github_owner
    name  = "breathe-gcp"

    push {
      branch = "^v2$"
    }
  }

  filename = "cloudbuild.yaml"

  substitutions = {
    _DEPLOY_PROJECT = "breathe-dev-env"
    _ENV_NAME       = "dev"
    _DEPLOY_REGION  = var.region
    _AR_HOSTNAME    = "${var.region}-docker.pkg.dev"
    _SHARED_PROJECT = module.project.project_id
    _JOB_NAME       = "breathe-feed-puller"
  }

  service_account = google_service_account.cloudbuild.id

  depends_on = [module.project, google_service_account.cloudbuild]
}

# Grant Cloud Run Job service account access to GCS buckets in breathe-shared
# The job needs to read from and write to breathe-pf-feeds bucket
resource "google_storage_bucket_iam_member" "feed_puller_feeds_bucket" {
  bucket = google_storage_bucket.feeds.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${var.dev_compute_service_account}"
}

# =============================================================================
# Database Schemas (Optional - requires Cloud SQL Proxy)
# To enable: terraform apply -var="manage_db_schemas=true" -var="db_admin_password=..."
#
# First start Cloud SQL Proxy:
#   cloud-sql-proxy --port 5432 breathe-shared:europe-west2:breathe-db
# =============================================================================

# PostgreSQL provider - only configured when manage_db_schemas is true
# When false, provider uses dummy config that won't attempt connection
provider "postgresql" {
  host     = var.manage_db_schemas ? var.db_host : "localhost"
  port     = var.manage_db_schemas ? var.db_port : 5432
  username = var.manage_db_schemas ? var.db_admin_user : "disabled"
  password = var.manage_db_schemas ? var.db_admin_password : "disabled"
  sslmode  = "disable"

  # Only connect when enabled
  connect_timeout = var.manage_db_schemas ? 15 : 1
  database        = "postgres"
}

# Create schemas in each environment database (only when enabled)
module "database_schemas" {
  source = "../../modules/database-schemas"
  count  = var.manage_db_schemas ? 1 : 0

  databases    = module.cloud_sql.database_names
  schemas      = var.db_schemas
  schema_owner = var.db_admin_user
  app_user     = module.cloud_sql.app_user_name

  depends_on = [module.cloud_sql]
}
