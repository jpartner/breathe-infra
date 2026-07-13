# Multi-Tenant Shared Infrastructure
# Contains: Artifact Registry, Cloud Build, VPC/networking, Zitadel auth server
#
# Project: breathe-shared (existing, cleaned)
# Remote state: gs://breathe-terraform-state/multi-shared

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

  backend "gcs" {
    bucket = "breathe-terraform-state"
    prefix = "multi-shared"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

# =============================================================================
# APIs
# =============================================================================

resource "google_project_service" "apis" {
  for_each = toset([
    "cloudresourcemanager.googleapis.com",
    "serviceusage.googleapis.com",
    "iam.googleapis.com",
    "compute.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
    "run.googleapis.com",
    "sqladmin.googleapis.com",
    "servicenetworking.googleapis.com",
    "secretmanager.googleapis.com",
    "vpcaccess.googleapis.com",
    "storage.googleapis.com",
    "cloudscheduler.googleapis.com",
  ])

  project = var.project_id
  service = each.value

  disable_dependent_services = false
  disable_on_destroy         = false
}

# =============================================================================
# Networking
# =============================================================================

module "networking" {
  source = "../../modules/networking"

  project_id = var.project_id
  region     = var.region

  depends_on = [google_project_service.apis]
}

# =============================================================================
# Artifact Registry
# =============================================================================

resource "google_artifact_registry_repository" "images" {
  for_each = toset([
    "breathe-backend",
    "breathe-admin",
    "breathe-zitadel",
  ])

  project       = var.project_id
  location      = var.region
  repository_id = each.value
  format        = "DOCKER"

  cleanup_policies {
    id     = "keep-recent"
    action = "KEEP"

    most_recent_versions {
      keep_count = 10
    }
  }

  depends_on = [google_project_service.apis]
}

# =============================================================================
# Cloud Build Service Account
# =============================================================================

resource "google_service_account" "cloudbuild" {
  project      = var.project_id
  account_id   = "sa-cloudbuild"
  display_name = "Cloud Build Service Account"

  depends_on = [google_project_service.apis]
}

# Cloud Build can push to all Artifact Registry repos
resource "google_artifact_registry_repository_iam_member" "cloudbuild_writer" {
  for_each = google_artifact_registry_repository.images

  project    = var.project_id
  location   = var.region
  repository = each.value.repository_id
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.cloudbuild.email}"
}

# Cloud Build can deploy to Cloud Run in all environment projects
resource "google_project_iam_member" "cloudbuild_run_admin" {
  for_each = toset(var.environment_project_ids)

  project = each.value
  role    = "roles/run.admin"
  member  = "serviceAccount:${google_service_account.cloudbuild.email}"
}

resource "google_project_iam_member" "cloudbuild_sa_user" {
  for_each = toset(var.environment_project_ids)

  project = each.value
  role    = "roles/iam.serviceAccountUser"
  member  = "serviceAccount:${google_service_account.cloudbuild.email}"
}

resource "google_project_iam_member" "cloudbuild_logs" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.cloudbuild.email}"
}

# Grant environment Cloud Run service agents access to shared Artifact Registry
resource "google_project_iam_member" "env_ar_reader" {
  for_each = toset(var.environment_project_numbers)

  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:service-${each.value}@serverless-robot-prod.iam.gserviceaccount.com"
}

# Grant environment Cloud Run service agents VPC connector access
resource "google_project_iam_member" "env_vpc_user" {
  for_each = toset(var.environment_project_numbers)

  project = var.project_id
  role    = "roles/vpcaccess.user"
  member  = "serviceAccount:service-${each.value}@serverless-robot-prod.iam.gserviceaccount.com"
}

# =============================================================================
# Cloud Build Triggers
# =============================================================================

resource "google_cloudbuild_trigger" "backend" {
  for_each = tomap({
    dev     = { branch = "^main$", project = "breathe-dev-env" }
    staging = { branch = "^staging$", project = "breathe-staging-env" }
  })

  project     = var.project_id
  name        = "breathe-backend-${each.key}"
  description = "Build and deploy backend to ${each.key}"
  location    = var.region

  github {
    owner = var.github_owner
    name  = "breathe-java"

    push {
      branch = each.value.branch
    }
  }

  filename = "cloudbuild.yaml"

  substitutions = {
    _DEPLOY_PROJECT = each.value.project
    _ENV_NAME       = each.key
    _DEPLOY_REGION  = var.region
    _AR_HOSTNAME    = "${var.region}-docker.pkg.dev"
    _SHARED_PROJECT = var.project_id
  }

  service_account = google_service_account.cloudbuild.id

  depends_on = [google_project_service.apis]
}

# =============================================================================
# Zitadel Auth Server
# =============================================================================

module "zitadel" {
  source = "../../modules/zitadel"

  project_id       = var.project_id
  region           = var.region
  vpc_connector_id = module.networking.vpc_connector_id

  db_instance_connection = var.zitadel_db_connection
  db_name                = "zitadel"
  db_user                = "zitadel"
  db_password_secret_id  = var.zitadel_db_password_secret_id

  domain        = var.zitadel_domain
  image         = "${var.region}-docker.pkg.dev/${var.project_id}/breathe-zitadel/zitadel:latest"
  masterkey_secret_id = var.zitadel_masterkey_secret_id

  depends_on = [google_project_service.apis, module.networking]
}
