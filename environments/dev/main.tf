# Development Environment Infrastructure
# Creates: Project, service accounts, environment-specific buckets

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
  }

  # Uncomment and configure for remote state
  # backend "gcs" {
  #   bucket = "breathe-terraform-state"
  #   prefix = "dev"
  # }
}

provider "google" {
  region = var.region
}

provider "google-beta" {
  region = var.region
}

# Create the dev project
module "project" {
  source = "../../modules/project"

  project_name    = "Breathe Dev Environment"
  project_id      = var.project_id
  billing_account = var.billing_account
  org_id          = var.org_id
  environment     = "dev"

  apis = [
    "cloudresourcemanager.googleapis.com",
    "serviceusage.googleapis.com",
    "iam.googleapis.com",
    "compute.googleapis.com",
    "run.googleapis.com",
    "cloudscheduler.googleapis.com",
    "secretmanager.googleapis.com",
    "storage.googleapis.com",
  ]
}

# Environment resources (service accounts, buckets, IAM)
module "environment" {
  source = "../../modules/environment"

  project_id  = module.project.project_id
  environment = "dev"
  region      = var.region

  shared_project_id            = var.shared_project_id
  shared_feeds_bucket          = var.shared_feeds_bucket
  shared_generated_data_bucket = var.shared_generated_data_bucket
  shared_images_bucket         = var.shared_images_bucket
  db_password_secret_id        = var.db_password_secret_id

  # Database configuration
  db_private_ip      = var.db_private_ip
  db_connection_name = var.db_connection_name
  db_user            = var.db_user

  # VPC configuration
  vpc_connector_id = var.vpc_connector_id

  # Service URLs
  customer_frontend_url = var.customer_frontend_url
  typesense_host        = var.typesense_host
  ecommerce_url         = var.ecommerce_url

  # Feature flags
  enable_image_cache = var.enable_image_cache

  # Container image tags
  ecommerce_image_tag      = var.ecommerce_image_tag
  feed_processor_image_tag = var.feed_processor_image_tag
  admin_image_tag          = var.admin_image_tag

  # Admin UI config
  typesense_api_key = var.typesense_api_key

  depends_on = [module.project]
}

# Grant this project's Cloud Run service agent access to shared Artifact Registry
resource "google_artifact_registry_repository_iam_member" "ecommerce_reader" {
  project    = var.shared_project_id
  location   = var.region
  repository = "breathe-ecommerce"
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:service-${module.project.project_number}@serverless-robot-prod.iam.gserviceaccount.com"

  depends_on = [module.project]
}

resource "google_artifact_registry_repository_iam_member" "nginx_reader" {
  project    = var.shared_project_id
  location   = var.region
  repository = "breathe-nginx"
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:service-${module.project.project_number}@serverless-robot-prod.iam.gserviceaccount.com"

  depends_on = [module.project]
}

resource "google_artifact_registry_repository_iam_member" "admin_reader" {
  project    = var.shared_project_id
  location   = var.region
  repository = "breathe-admin"
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:service-${module.project.project_number}@serverless-robot-prod.iam.gserviceaccount.com"

  depends_on = [module.project]
}

resource "google_artifact_registry_repository_iam_member" "feed_processor_reader" {
  project    = var.shared_project_id
  location   = var.region
  repository = "breathe-pf-feed-processor"
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:service-${module.project.project_number}@serverless-robot-prod.iam.gserviceaccount.com"

  depends_on = [module.project]
}

# Environment-specific secrets
resource "google_secret_manager_secret" "anthropic_api_key" {
  project   = module.project.project_id
  secret_id = "anthropic-api-key"

  replication {
    auto {}
  }

  labels = {
    environment = "dev"
    managed_by  = "terraform"
  }

  depends_on = [module.project]
}

resource "google_secret_manager_secret" "stripe_api_key" {
  project   = module.project.project_id
  secret_id = "stripe-api-key"

  replication {
    auto {}
  }

  labels = {
    environment = "dev"
    managed_by  = "terraform"
  }

  depends_on = [module.project]
}

# Grant ecommerce service account access to secrets
resource "google_secret_manager_secret_iam_member" "ecommerce_anthropic" {
  project   = module.project.project_id
  secret_id = google_secret_manager_secret.anthropic_api_key.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${module.environment.service_accounts.ecommerce}"
}

resource "google_secret_manager_secret_iam_member" "ecommerce_stripe" {
  project   = module.project.project_id
  secret_id = google_secret_manager_secret.stripe_api_key.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${module.environment.service_accounts.ecommerce}"
}
