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
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
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

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

provider "cloudflare" {
  alias     = "unifeed"
  api_token = var.unifeed_cloudflare_api_token
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

resource "google_sql_database_instance" "main" {
  project          = var.project_id
  name             = "breathe-multi-db"
  region           = var.region
  database_version = "POSTGRES_16"

  settings {
    tier              = var.db_tier
    availability_type = "ZONAL"
    edition           = "ENTERPRISE"
    disk_type         = "PD_SSD"
    disk_autoresize   = true

    # Initial size only — see the lifecycle block. Once GCP has grown the disk
    # this value stops being the truth, and Terraform must not act on it.
    disk_size = 10

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = local.vpc_network_id
      enable_private_path_for_google_cloud_services = true
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

  lifecycle {
    ignore_changes = [
      # disk_autoresize is on, so GCP grows this disk on its own. Left
      # unignored, the next plan sees live 20GB against a declared 10 and
      # proposes shrinking it — which Cloud SQL rejects outright. The result is
      # a plan that looks fine and an apply that fails on the primary database,
      # at whatever moment the disk happened to grow.
      #
      # The trade: Terraform can no longer *raise* the size either. Growing the
      # disk deliberately means removing this line for that apply, or doing it
      # in the console and letting autoresize keep it. Given the disk only ever
      # grows automatically here, that is the better side of the trade.
      settings[0].disk_size,
    ]
  }
}

# Databases
resource "google_sql_database" "envs" {
  for_each = toset([])

  project  = var.project_id
  instance = google_sql_database_instance.main.name
  name     = each.value
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

# =============================================================================
# External API secrets (values set manually via gcloud/console)
# =============================================================================

resource "google_secret_manager_secret" "postmark_api_key" {
  project   = var.project_id
  secret_id = "postmark-api-key"
  replication {
    auto {}
  }
}

# =============================================================================
# Artifact Registry
# =============================================================================

resource "google_artifact_registry_repository" "images" {
  for_each = toset(["pa-migration", "unifeed-backend", "unifeed-storefront", "unifeed-ingest", "unifeed-test"])

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

# Lets the build mint a Google ID token for itself (IAM Credentials
# generateIdToken), so it can authenticate to the deploy hub without carrying
# the non-expiring platform-admin PAT into every build step. Cloud Build's
# metadata server does not serve ID tokens, so self-impersonation is the route.
resource "google_service_account_iam_member" "cloudbuild_self_token_creator" {
  service_account_id = google_service_account.cloudbuild.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${google_service_account.cloudbuild.email}"
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

resource "google_cloudbuild_trigger" "pa_migration_dev" {
  project     = var.project_id
  name        = "pa-migration-dev"
  description = "Build and deploy PA migration service to dev on push to main"
  location    = var.region

  github {
    owner = var.github_owner
    name  = "pa-migration"

    push {
      branch = "^main$"
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

resource "google_cloudbuild_trigger" "unifeed_backend_dev" {
  project     = var.project_id
  name        = "unifeed-backend-dev"
  description = "Build and deploy Unifeed backend to dev on push to main"
  location    = var.region

  github {
    owner = var.github_owner
    name  = "unifeed-backend"

    push {
      branch = "^main$"
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

resource "google_cloudbuild_trigger" "unifeed_storefronts_dev" {
  project     = var.project_id
  name        = "unifeed-storefronts-dev"
  description = "Build and deploy all storefronts (breathe, pa, uniten) to dev on push to main"
  location    = var.region

  github {
    owner = var.github_owner
    name  = "unifeed-ui"

    push {
      branch = "^main$"
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

resource "google_cloudbuild_trigger" "unifeed_test_dev" {
  project     = var.project_id
  name        = "unifeed-test-dev"
  description = "Build and deploy Unifeed test runner on push to main"
  location    = var.region

  github {
    owner = var.github_owner
    name  = "unifeed-test"

    push {
      branch = "^main$"
    }
  }

  filename = "cloudbuild.yaml"

  substitutions = {
    _DEPLOY_PROJECT = var.project_id
    _ENV_NAME       = "shared"
    _DEPLOY_REGION  = var.region
    _AR_HOSTNAME    = "${var.region}-docker.pkg.dev"
    _SHARED_PROJECT = var.project_id
    _SERVICE_NAME   = "unifeed-test"
  }

  service_account = google_service_account.cloudbuild.id
}

resource "google_cloudbuild_trigger" "unifeed_pdf_dev" {
  project     = var.project_id
  name        = "unifeed-pdf-dev"
  description = "Build and deploy Unifeed PDF service on push to main"
  location    = var.region

  github {
    owner = var.github_owner
    name  = "unifeed-pdf"

    push {
      branch = "^main$"
    }
  }

  filename = "cloudbuild.yaml"

  substitutions = {
    _DEPLOY_PROJECT = "breathe-dev-env"
    _ENV_NAME       = "dev"
    _DEPLOY_REGION  = var.region
    _AR_HOSTNAME    = "${var.region}-docker.pkg.dev"
    _SHARED_PROJECT = var.project_id
    _SERVICE_NAME   = "unifeed-pdf"
  }

  service_account = google_service_account.cloudbuild.id
}

# =============================================================================
# Terraform plan CI — plan-only, never applies
# =============================================================================
#
# Runs cloudbuild/terraform-plan.yaml on every push to this repo's main branch.
# It reads state and reports; the gate fails the build only on proposed
# destroys (see the header of that file for the full policy).
#
# This runs as its own service account rather than sa-cloudbuild. The deploy SA
# has no business reading Terraform state or every secret in the project, and
# this SA has no business deploying — keeping them apart means neither grows the
# other's privileges by accident.

resource "google_service_account" "terraform_plan" {
  project      = var.project_id
  account_id   = "sa-terraform-plan"
  display_name = "Terraform plan CI (read-only)"
  description  = "Runs terraform plan in Cloud Build. Never applies."
}

# Read the state bucket. Read-only is sufficient because the pipeline plans with
# -lock=false, so it never writes a lock object. If a future change makes these
# plans take the lock, this needs objectAdmin.
resource "google_storage_bucket_iam_member" "terraform_plan_state" {
  bucket = "breathe-terraform-state"
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.terraform_plan.email}"
}

# Refreshing the 15 managed google_secret_manager_secret_version resources means
# reading their payloads, so this grant covers every secret in breathe-shared.
# It is the widest privilege this SA holds and the main reason it is separate
# from sa-cloudbuild.
resource "google_project_iam_member" "terraform_plan_secrets" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.terraform_plan.email}"
}

# Refresh reads every managed resource across the shared and environment
# projects. roles/viewer is read-only by definition — this SA cannot mutate
# anything in GCP, which is what makes a plan-only pipeline safe to run
# unattended.
resource "google_project_iam_member" "terraform_plan_viewer_shared" {
  project = var.project_id
  role    = "roles/viewer"
  member  = "serviceAccount:${google_service_account.terraform_plan.email}"
}

resource "google_project_iam_member" "terraform_plan_viewer_envs" {
  for_each = toset(var.environment_project_ids)

  project = each.value
  role    = "roles/viewer"
  member  = "serviceAccount:${google_service_account.terraform_plan.email}"
}

# multi-dev still declares a cloudsql.client binding on the legacy `breathe-dev`
# project (the one the README says never to touch), so a refresh has to read
# that project's IAM policy. Read-only, and it does not make breathe-dev managed
# — it only lets the plan see what is already declared about it.
resource "google_project_iam_member" "terraform_plan_viewer_legacy" {
  project = "breathe-dev"
  role    = "roles/viewer"
  member  = "serviceAccount:${google_service_account.terraform_plan.email}"
}

resource "google_project_iam_member" "terraform_plan_logs" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.terraform_plan.email}"
}

# roles/viewer covers storage.buckets.get and .list but NOT .getIamPolicy, so
# refreshing the google_storage_bucket_iam_member resources 403s. The predefined
# role that grants it — roles/storage.legacyBucketOwner — also grants
# setIamPolicy, which would give this SA a write capability and cost us the
# property that makes an unattended plan safe. Hence a custom role holding
# exactly the one missing read permission.
# Custom roles are per-project, and the managed buckets live in both the shared
# project and the environment projects, so the role is defined in each.
resource "google_project_iam_custom_role" "bucket_iam_reader" {
  for_each = toset(concat([var.project_id], var.environment_project_ids))

  project     = each.value
  role_id     = "terraformPlanBucketIamReader"
  title       = "Terraform Plan — Bucket IAM Reader"
  description = "Reads bucket IAM policies so terraform plan can refresh bucket IAM bindings. Read-only."
  permissions = ["storage.buckets.getIamPolicy"]
}

resource "google_project_iam_member" "terraform_plan_bucket_iam" {
  for_each = google_project_iam_custom_role.bucket_iam_reader

  project = each.value.project
  role    = each.value.id
  member  = "serviceAccount:${google_service_account.terraform_plan.email}"
}

# The single-project versions of the two resources above, applied earlier today.
# Without these, expanding to for_each reads as destroy-then-create.
moved {
  from = google_project_iam_custom_role.bucket_iam_reader
  to   = google_project_iam_custom_role.bucket_iam_reader["breathe-shared"]
}

moved {
  from = google_project_iam_member.terraform_plan_bucket_iam
  to   = google_project_iam_member.terraform_plan_bucket_iam["breathe-shared"]
}

resource "google_cloudbuild_trigger" "terraform_plan" {
  project     = var.project_id
  name        = "breathe-infra-plan"
  description = "Plan-only Terraform run on push to main. Fails on proposed destroys."
  location    = var.region

  github {
    owner = var.github_owner
    name  = "breathe-infra"

    push {
      branch = "^main$"
    }
  }

  filename = "cloudbuild/terraform-plan.yaml"

  service_account = google_service_account.terraform_plan.id
}

# =============================================================================
# Test Runner — Cloud Run service in shared project
# =============================================================================

resource "google_service_account" "test_runner" {
  project      = var.project_id
  account_id   = "sa-test-runner"
  display_name = "Test Runner Service Account"
}

# Test runner needs Cloud SQL access for its own database
resource "google_project_iam_member" "test_runner_sql" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.test_runner.email}"
}

# Test runner needs to read test user PATs and login password
resource "google_secret_manager_secret_iam_member" "test_runner_pats" {
  for_each = var.unifeed_zitadel_manage_config ? toset(["admin", "customer", "norole", "csr"]) : toset([])

  project   = var.project_id
  secret_id = google_secret_manager_secret.test_pats[each.key].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.test_runner.email}"
}

resource "google_secret_manager_secret_iam_member" "test_runner_login_password" {
  count = var.unifeed_zitadel_manage_config ? 1 : 0

  project   = var.project_id
  secret_id = google_secret_manager_secret.test_login_password[0].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.test_runner.email}"
}

# Hub OIDC login secrets (see unifeed-hub-auth.tf)
resource "google_secret_manager_secret_iam_member" "test_runner_hub_auth" {
  for_each = {
    zitadel_client = google_secret_manager_secret.hub_zitadel_secret.secret_id
    nextauth       = google_secret_manager_secret.hub_auth_secret.secret_id
  }

  project   = var.project_id
  secret_id = each.value
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.test_runner.email}"
}

# Test runner needs to read the DB password
resource "google_secret_manager_secret_iam_member" "test_runner_db" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.db_app_password.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.test_runner.email}"
}

# PA Migration API key
resource "google_secret_manager_secret" "pa_migration_api_key" {
  project   = var.project_id
  secret_id = "pa-migration-api-key"
  replication {
    auto {}
  }
}

# PA Migration — GCS bucket for SQLite database files
resource "google_storage_bucket" "pa_legacy" {
  project                     = var.project_id
  name                        = "${var.project_id}-pa-legacy"
  location                    = var.region
  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }
}

resource "google_storage_bucket_iam_member" "pa_legacy_cloudbuild" {
  bucket = google_storage_bucket.pa_legacy.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.cloudbuild.email}"
}

# GCS bucket for test execution logs
resource "google_storage_bucket" "test_logs" {
  project                     = var.project_id
  name                        = "${var.project_id}-test-logs"
  location                    = var.region
  uniform_bucket_level_access = true

  lifecycle_rule {
    condition { age = 90 }
    action { type = "Delete" }
  }

  labels = {
    managed_by = "terraform"
  }
}

resource "google_storage_bucket_iam_member" "test_runner_logs" {
  bucket = google_storage_bucket.test_logs.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.test_runner.email}"
}

# Test runner needs to update Cloud Run services in dev and staging (for promotion)
resource "google_project_iam_member" "test_runner_run_admin" {
  for_each = toset(var.environment_project_ids)

  project = each.value
  role    = "roles/run.admin"
  member  = "serviceAccount:${google_service_account.test_runner.email}"
}

resource "google_project_iam_member" "test_runner_sa_user" {
  for_each = toset(var.environment_project_ids)

  project = each.value
  role    = "roles/iam.serviceAccountUser"
  member  = "serviceAccount:${google_service_account.test_runner.email}"
}

# =============================================================================
# Unifeed Test Runner
# =============================================================================

resource "google_cloud_run_v2_service" "unifeed_test_runner" {
  name     = "unifeed-test"
  project  = var.project_id
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  lifecycle {
    ignore_changes = [
      template[0].containers[0].image,
      template[0].labels,
      labels,
      # Cloud Run records which tool last wrote the service. Every deploy in
      # this org runs `gcloud run services update`, so these become "gcloud"
      # and Terraform then plans to set them back to null — a change that does
      # nothing and that the next deploy undoes. Left unignored it is a
      # permanent one-resource diff on every plan.
      client,
      client_version,
    ]
  }

  template {
    service_account = google_service_account.test_runner.email

    scaling {
      min_instance_count = 0
      max_instance_count = 1
    }

    containers {
      image = "${var.region}-docker.pkg.dev/${var.project_id}/unifeed-test/unifeed-test:latest"

      ports {
        container_port = 3000
      }

      resources {
        limits = {
          cpu    = "2"
          memory = "4Gi"
        }
        cpu_idle          = false
        startup_cpu_boost = true
      }

      env {
        name  = "BASE_URL"
        value = "https://api.dev.unifeed.io"
      }
      env {
        name  = "UNITEN_URL"
        value = "https://uniten.dev.unifeed.io"
      }
      env {
        name  = "TEST_TENANT"
        value = "uniten"
      }
      env {
        name  = "DB_HOST"
        value = google_sql_database_instance.main.private_ip_address
      }
      env {
        name  = "DB_NAME"
        value = "unifeed_test"
      }
      env {
        name  = "DB_USER"
        value = "app"
      }
      env {
        name = "DB_PASSWORD"
        value_source {
          secret_key_ref {
            secret  = "db-app-password"
            version = "latest"
          }
        }
      }

      # Test user PATs (for authenticated API tests)
      dynamic "env" {
        for_each = var.unifeed_zitadel_manage_config ? [1] : []
        content {
          name = "TEST_ADMIN_PAT"
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.test_pats["admin"].secret_id
              version = "latest"
            }
          }
        }
      }
      dynamic "env" {
        for_each = var.unifeed_zitadel_manage_config ? [1] : []
        content {
          name = "TEST_CUSTOMER_PAT"
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.test_pats["customer"].secret_id
              version = "latest"
            }
          }
        }
      }
      dynamic "env" {
        for_each = var.unifeed_zitadel_manage_config ? [1] : []
        content {
          name = "TEST_NOROLE_PAT"
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.test_pats["norole"].secret_id
              version = "latest"
            }
          }
        }
      }
      env {
        name  = "ADMIN_URL"
        value = "https://admin-uniten.dev.unifeed.io"
      }
      # Codifies a flag first set imperatively on the live service (2026-08)
      # so an apply does not strip it.
      env {
        name  = "SMOKE_PHASE_ENABLED"
        value = "1"
      }
      # Zitadel OIDC login for the hub UI (see unifeed-hub-auth.tf)
      env {
        name  = "NEXTAUTH_URL"
        value = "https://hub.dev.unifeed.io"
      }
      env {
        name  = "ZITADEL_ISSUER"
        value = "https://${var.unifeed_zitadel_domain}"
      }
      env {
        name  = "ZITADEL_CLIENT_ID"
        value = zitadel_application_oidc.hub.client_id
      }
      env {
        name = "ZITADEL_CLIENT_SECRET"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.hub_zitadel_secret.id
            version = "latest"
          }
        }
      }
      env {
        name = "NEXTAUTH_SECRET"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.hub_auth_secret.id
            version = "latest"
          }
        }
      }
      env {
        name  = "TEST_ADMIN_LOGIN_EMAIL"
        value = "e2e-admin@unifeed.io"
      }
      env {
        name  = "TEST_CSR_LOGIN_EMAIL"
        value = "e2e-csr@unifeed.io"
      }
      env {
        name  = "TEST_DESIGNER_LOGIN_EMAIL"
        value = "e2e-designer@unifeed.io"
      }
      dynamic "env" {
        for_each = var.unifeed_zitadel_manage_config ? [1] : []
        content {
          name = "TEST_CSR_PAT"
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.test_pats["csr"].secret_id
              version = "latest"
            }
          }
        }
      }
      dynamic "env" {
        for_each = var.unifeed_zitadel_manage_config ? [1] : []
        content {
          name  = "TEST_LOGIN_EMAIL"
          value = "e2e-test@unifeed.io"
        }
      }
      dynamic "env" {
        for_each = var.unifeed_zitadel_manage_config ? [1] : []
        content {
          name = "TEST_LOGIN_PASSWORD"
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.test_login_password[0].secret_id
              version = "latest"
            }
          }
        }
      }
    }

    vpc_access {
      connector = local.vpc_connector_id
      egress    = "PRIVATE_RANGES_ONLY"
    }

    timeout = "300s"
  }

  labels = {
    service    = "unifeed-test"
    managed_by = "terraform"
  }
}

resource "google_cloud_run_v2_service_iam_member" "unifeed_test_runner_public" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.unifeed_test_runner.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# =============================================================================
# Unifeed Ingest — supplier data ingestion and enrichment UI
# =============================================================================

resource "google_cloud_run_v2_service" "unifeed_ingest" {
  name     = "unifeed-ingest"
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
      image = "${var.region}-docker.pkg.dev/${var.project_id}/unifeed-ingest/unifeed-ingest:latest"
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
        name  = "NEXTAUTH_URL"
        value = "https://ingest.unifeed.io"
      }
      env {
        name  = "ZITADEL_ISSUER"
        value = "https://${var.unifeed_zitadel_domain}"
      }
      env {
        name  = "ZITADEL_CLIENT_ID"
        value = zitadel_application_oidc.ingest.client_id
      }
      env {
        name = "ZITADEL_CLIENT_SECRET"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.ingest_zitadel_secret.id
            version = "latest"
          }
        }
      }
      env {
        name = "NEXTAUTH_SECRET"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.ingest_auth_secret.id
            version = "latest"
          }
        }
      }
    }

    timeout = "60s"
  }

  labels = {
    managed_by = "terraform"
  }

}

resource "google_cloud_run_v2_service_iam_member" "unifeed_ingest_public" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.unifeed_ingest.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}


# =============================================================================
# Unifeed Zitadel Auth Server (auth.unifeed.io)
# =============================================================================

resource "random_password" "unifeed_zitadel_db" {
  length  = 32
  special = false
}

resource "random_password" "unifeed_zitadel_masterkey" {
  length  = 32
  special = false
}

resource "google_sql_database" "unifeed_zitadel" {
  project  = var.project_id
  instance = google_sql_database_instance.main.name
  name     = "unifeed_zitadel"
}

resource "google_sql_user" "unifeed_zitadel" {
  project  = var.project_id
  instance = google_sql_database_instance.main.name
  name     = "unifeed_zitadel"
  password = random_password.unifeed_zitadel_db.result
}

resource "google_secret_manager_secret" "unifeed_zitadel_db_password" {
  project   = var.project_id
  secret_id = "unifeed-zitadel-db-password"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "unifeed_zitadel_db_password" {
  secret      = google_secret_manager_secret.unifeed_zitadel_db_password.id
  secret_data = random_password.unifeed_zitadel_db.result
}

resource "google_secret_manager_secret" "unifeed_zitadel_masterkey" {
  project   = var.project_id
  secret_id = "unifeed-zitadel-masterkey"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "unifeed_zitadel_masterkey" {
  secret      = google_secret_manager_secret.unifeed_zitadel_masterkey.id
  secret_data = random_password.unifeed_zitadel_masterkey.result
}

module "unifeed_zitadel" {
  source = "../../modules/zitadel"

  project_id       = var.project_id
  region           = var.region
  vpc_connector_id = local.vpc_connector_id

  service_name                = "unifeed-zitadel"
  db_host                     = google_sql_database_instance.main.private_ip_address
  db_name                     = "unifeed_zitadel"
  db_user                     = "unifeed_zitadel"
  db_password_secret_id       = google_secret_manager_secret.unifeed_zitadel_db_password.secret_id
  db_admin_password_secret_id = google_secret_manager_secret.db_admin_password.secret_id

  domain              = var.unifeed_zitadel_domain
  image               = "ghcr.io/zitadel/zitadel:v2.71.5"
  masterkey_secret_id = google_secret_manager_secret.unifeed_zitadel_masterkey.secret_id

  depends_on = [
    google_sql_database.unifeed_zitadel,
    google_sql_user.unifeed_zitadel,
    google_secret_manager_secret_version.unifeed_zitadel_db_password,
    google_secret_manager_secret_version.unifeed_zitadel_masterkey,
  ]
}

# =============================================================================
# Platform Load Balancer
# =============================================================================

module "platform_lb" {
  source = "../../modules/platform-lb"

  project_id = var.project_id

  backends = {
    unifeed-zitadel = {
      cloud_run_service = "unifeed-zitadel"
      region            = var.region
    }
    unifeed-test = {
      cloud_run_service = "unifeed-test"
      region            = var.region
    }
    unifeed-ingest = {
      cloud_run_service = google_cloud_run_v2_service.unifeed_ingest.name
      region            = var.region
    }
  }

  host_rules = {
    unifeed-auth = {
      hosts   = [var.unifeed_zitadel_domain]
      backend = "unifeed-zitadel"
    }
    unifeed-test = {
      hosts   = ["hub.dev.unifeed.io"]
      backend = "unifeed-test"
    }
    unifeed-ingest = {
      hosts   = ["ingest.unifeed.io"]
      backend = "unifeed-ingest"
    }
  }

  default_backend = "unifeed-zitadel"

  domains = [var.unifeed_zitadel_domain, "hub.dev.unifeed.io", "ingest.unifeed.io"]

  depends_on = [module.unifeed_zitadel]
}

# =============================================================================
# Cloudflare DNS — unifeed.io
# =============================================================================

resource "cloudflare_record" "unifeed_hub" {
  provider = cloudflare.unifeed

  zone_id = var.unifeed_cloudflare_zone_id
  name    = "hub.dev"
  content = module.platform_lb.ip_address
  type    = "A"
  proxied = false
  ttl     = 300
}

resource "cloudflare_record" "unifeed_ingest" {
  provider = cloudflare.unifeed

  zone_id = var.unifeed_cloudflare_zone_id
  name    = "ingest"
  content = module.platform_lb.ip_address
  type    = "A"
  proxied = false
  ttl     = 300
}

resource "cloudflare_record" "unifeed_auth" {
  provider = cloudflare.unifeed

  zone_id = var.unifeed_cloudflare_zone_id
  name    = "auth"
  content = module.platform_lb.ip_address
  type    = "A"
  proxied = false
  ttl     = 300
}

# =============================================================================
# Cloud KMS — Tenant Secret Encryption
# One keyring in shared, one key per environment.
# Each env's backend SA gets decrypt only on its own key.
# =============================================================================

resource "google_project_service" "kms" {
  project = var.project_id
  service = "cloudkms.googleapis.com"

  disable_dependent_services = false
  disable_on_destroy         = false
}

resource "google_kms_key_ring" "tenant_secrets" {
  project  = var.project_id
  name     = "unifeed-secrets"
  location = var.region

  depends_on = [google_project_service.kms]
}

resource "google_kms_crypto_key" "tenant_secrets" {
  for_each = toset(["dev", "staging", "production"])

  name     = "tenant-secrets-${each.key}"
  key_ring = google_kms_key_ring.tenant_secrets.id
  purpose  = "ENCRYPT_DECRYPT"

  rotation_period = "7776000s" # 90 days

  lifecycle {
    prevent_destroy = true
  }
}

# =============================================================================
# Cloudflare DNS — breathebranding.co.uk
# =============================================================================

