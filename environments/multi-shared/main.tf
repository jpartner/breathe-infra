# Multi-Tenant Shared Infrastructure
# Everything in breathe-shared is managed by this config.
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
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    zitadel = {
      source  = "zitadel/zitadel"
      version = "~> 3.2"
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
# Networking (pre-existing, read-only)
# VPC, subnets, connector were created previously and are stable.
# Using data sources to reference them without managing their lifecycle.
# =============================================================================

data "google_compute_network" "vpc" {
  project = var.project_id
  name    = "breathe-vpc"
}

data "google_vpc_access_connector" "connector" {
  project = var.project_id
  region  = var.region
  name    = "breathe-vpc-connector"
}

locals {
  vpc_network_id   = data.google_compute_network.vpc.id
  vpc_connector_id = data.google_vpc_access_connector.connector.id
}

# =============================================================================
# Cloud SQL
# =============================================================================

resource "random_password" "db_admin" {
  length  = 32
  special = false
}

resource "random_password" "db_app" {
  length  = 32
  special = false
}

resource "random_password" "db_zitadel" {
  length  = 32
  special = false
}

resource "random_password" "zitadel_masterkey" {
  length  = 32
  special = false
}

resource "google_sql_database_instance" "main" {
  project          = var.project_id
  name             = "breathe-multi-db"
  region           = var.region
  database_version = "POSTGRES_16"

  settings {
    tier              = var.db_tier
    availability_type = "ZONAL"
    edition           = "ENTERPRISE"
    disk_size         = 10
    disk_type         = "PD_SSD"
    disk_autoresize   = true

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = local.vpc_network_id
      enable_private_path_for_google_cloud_services  = true
    }

    backup_configuration {
      enabled                        = true
      start_time                     = "02:00"
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = 7

      backup_retention_settings {
        retained_backups = 7
      }
    }
  }

  deletion_protection = false # Set true for production

}

# Databases
resource "google_sql_database" "envs" {
  for_each = toset(["breathe_multi_dev", "breathe_multi_staging", "breathe_multi_prod"])

  project  = var.project_id
  instance = google_sql_database_instance.main.name
  name     = each.value
}

resource "google_sql_database" "zitadel" {
  project  = var.project_id
  instance = google_sql_database_instance.main.name
  name     = "zitadel"
}

# Users
resource "google_sql_user" "admin" {
  project  = var.project_id
  instance = google_sql_database_instance.main.name
  name     = "postgres"
  password = random_password.db_admin.result
}

resource "google_sql_user" "app" {
  project  = var.project_id
  instance = google_sql_database_instance.main.name
  name     = "app"
  password = random_password.db_app.result
}

resource "google_sql_user" "zitadel" {
  project  = var.project_id
  instance = google_sql_database_instance.main.name
  name     = "zitadel"
  password = random_password.db_zitadel.result
}

# =============================================================================
# Secrets
# =============================================================================

resource "google_secret_manager_secret" "db_admin_password" {
  project   = var.project_id
  secret_id = "db-admin-password"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "db_admin_password" {
  secret      = google_secret_manager_secret.db_admin_password.id
  secret_data = random_password.db_admin.result
}

resource "google_secret_manager_secret" "db_app_password" {
  project   = var.project_id
  secret_id = "db-app-password"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "db_app_password" {
  secret      = google_secret_manager_secret.db_app_password.id
  secret_data = random_password.db_app.result
}

resource "google_secret_manager_secret" "zitadel_db_password" {
  project   = var.project_id
  secret_id = "zitadel-db-password"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "zitadel_db_password" {
  secret      = google_secret_manager_secret.zitadel_db_password.id
  secret_data = random_password.db_zitadel.result
}

resource "google_secret_manager_secret" "zitadel_masterkey" {
  project   = var.project_id
  secret_id = "zitadel-masterkey"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "zitadel_masterkey" {
  secret      = google_secret_manager_secret.zitadel_masterkey.id
  secret_data = random_password.zitadel_masterkey.result
}

# =============================================================================
# Artifact Registry
# =============================================================================

resource "google_artifact_registry_repository" "images" {
  for_each = toset(["breathe-backend", "breathe-admin", "breathe-pdf"])

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

}

# =============================================================================
# Cloud Build Service Account
# =============================================================================

resource "google_service_account" "cloudbuild" {
  project      = var.project_id
  account_id   = "sa-cloudbuild"
  display_name = "Cloud Build Service Account"

}

resource "google_artifact_registry_repository_iam_member" "cloudbuild_writer" {
  for_each = google_artifact_registry_repository.images

  project    = var.project_id
  location   = var.region
  repository = each.value.repository_id
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.cloudbuild.email}"
}

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

# Grant environment Cloud Run service agents access to shared resources
resource "google_project_iam_member" "env_ar_reader" {
  for_each = toset(var.environment_project_numbers)

  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:service-${each.value}@serverless-robot-prod.iam.gserviceaccount.com"
}

resource "google_project_iam_member" "env_vpc_user" {
  for_each = toset(var.environment_project_numbers)

  project = var.project_id
  role    = "roles/vpcaccess.user"
  member  = "serviceAccount:service-${each.value}@serverless-robot-prod.iam.gserviceaccount.com"
}

# =============================================================================
# Cloud Build Triggers — all on multi-tenant branch, deploy to dev
# =============================================================================

resource "google_cloudbuild_trigger" "backend_dev" {
  project     = var.project_id
  name        = "breathe-backend-dev"
  description = "Build and deploy backend to dev on push to multi-tenant"
  location    = var.region

  github {
    owner = var.github_owner
    name  = "breathe-java"

    push {
      branch = "^multi-tenant$"
    }
  }

  filename = "cloudbuild.yaml"

  substitutions = {
    _DEPLOY_PROJECT = "breathe-dev-env"
    _ENV_NAME       = "dev"
    _DEPLOY_REGION  = var.region
    _AR_HOSTNAME    = "${var.region}-docker.pkg.dev"
    _SHARED_PROJECT = var.project_id
  }

  service_account = google_service_account.cloudbuild.id
}

resource "google_cloudbuild_trigger" "admin_dev" {
  project     = var.project_id
  name        = "breathe-admin-dev"
  description = "Build and deploy admin to dev on push to multi-tenant"
  location    = var.region

  github {
    owner = var.github_owner
    name  = "breathe-admin-nuxt-claude"

    push {
      branch = "^multi-tenant$"
    }
  }

  filename = "cloudbuild.yaml"

  substitutions = {
    _DEPLOY_PROJECT = "breathe-dev-env"
    _ENV_NAME       = "dev"
    _DEPLOY_REGION  = var.region
    _AR_HOSTNAME    = "${var.region}-docker.pkg.dev"
    _SHARED_PROJECT = var.project_id
    _SERVICE_NAME   = "breathe-admin"
  }

  service_account = google_service_account.cloudbuild.id
}

resource "google_cloudbuild_trigger" "pdf_dev" {
  project     = var.project_id
  name        = "breathe-pdf-dev"
  description = "Build and deploy PDF service to dev on push to multi-tenant"
  location    = var.region

  github {
    owner = var.github_owner
    name  = "breathe-pdf-creation"

    push {
      branch = "^multi-tenant$"
    }
  }

  filename = "cloudbuild.yaml"

  substitutions = {
    _DEPLOY_PROJECT = "breathe-dev-env"
    _ENV_NAME       = "dev"
    _DEPLOY_REGION  = var.region
    _AR_HOSTNAME    = "${var.region}-docker.pkg.dev"
    _SHARED_PROJECT = var.project_id
    _SERVICE_NAME   = "breathe-pdf"
  }

  service_account = google_service_account.cloudbuild.id
}


# =============================================================================
# Zitadel Auth Server
# =============================================================================

module "zitadel" {
  source = "../../modules/zitadel"

  project_id       = var.project_id
  region           = var.region
  vpc_connector_id = local.vpc_connector_id

  db_host                    = google_sql_database_instance.main.private_ip_address
  db_name                    = "zitadel"
  db_user                    = "zitadel"
  db_password_secret_id      = google_secret_manager_secret.zitadel_db_password.secret_id
  db_admin_password_secret_id = google_secret_manager_secret.db_admin_password.secret_id

  domain              = var.zitadel_domain
  image               = "ghcr.io/zitadel/zitadel:v2.71.5"
  masterkey_secret_id = google_secret_manager_secret.zitadel_masterkey.secret_id

  depends_on = [
    google_sql_database.zitadel,
    google_sql_user.zitadel,
    google_secret_manager_secret_version.zitadel_db_password,
    google_secret_manager_secret_version.zitadel_masterkey,
  ]
}

# =============================================================================
# Platform Load Balancer
# =============================================================================

module "platform_lb" {
  source = "../../modules/platform-lb"

  project_id = var.project_id

  backends = {
    zitadel = {
      cloud_run_service = "zitadel"
      region            = var.region
    }
  }

  host_rules = {
    auth = {
      hosts   = [var.zitadel_domain]
      backend = "zitadel"
    }
  }

  default_backend = "zitadel"

  domains = [var.zitadel_domain]

  depends_on = [module.zitadel]
}
