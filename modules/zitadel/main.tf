# Zitadel Auth Server
# Self-hosted OIDC/OAuth2 identity provider on Cloud Run
# Supports multi-tenancy via Organizations

resource "google_service_account" "zitadel" {
  project      = var.project_id
  account_id   = "sa-zitadel"
  display_name = "Zitadel Auth Server"
  description  = "Service account for Zitadel identity provider"
}

# Zitadel needs Cloud SQL access
resource "google_project_iam_member" "zitadel_sql" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.zitadel.email}"
}

# Zitadel needs to read its secrets
resource "google_secret_manager_secret_iam_member" "zitadel_db_password" {
  project   = var.project_id
  secret_id = var.db_password_secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.zitadel.email}"
}

resource "google_secret_manager_secret_iam_member" "zitadel_masterkey" {
  project   = var.project_id
  secret_id = var.masterkey_secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.zitadel.email}"
}

resource "google_secret_manager_secret_iam_member" "zitadel_admin_password" {
  project   = var.project_id
  secret_id = var.db_admin_password_secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.zitadel.email}"
}

# Cloud Run service for Zitadel
resource "google_cloud_run_v2_service" "zitadel" {
  name     = "zitadel"
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
    service_account = google_service_account.zitadel.email

    vpc_access {
      connector = var.vpc_connector_id
      egress    = "PRIVATE_RANGES_ONLY"
    }

    scaling {
      min_instance_count = 1 # Auth server should always be warm
      max_instance_count = 3
    }

    containers {
      image   = var.image
      command = ["/app/zitadel"]
      args    = ["start-from-init", "--tlsMode", "external", "--masterkeyFromEnv"]

      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
        cpu_idle          = false # Keep warm
        startup_cpu_boost = true
      }

      env {
        name  = "ZITADEL_EXTERNALDOMAIN"
        value = var.domain
      }

      env {
        name  = "ZITADEL_EXTERNALPORT"
        value = "443"
      }

      env {
        name  = "ZITADEL_EXTERNALSECURE"
        value = "true"
      }

      env {
        name  = "ZITADEL_DATABASE_POSTGRES_HOST"
        value = var.db_host
      }

      env {
        name  = "ZITADEL_DATABASE_POSTGRES_PORT"
        value = "5432"
      }

      env {
        name  = "ZITADEL_DATABASE_POSTGRES_DATABASE"
        value = var.db_name
      }

      env {
        name  = "ZITADEL_DATABASE_POSTGRES_USER_USERNAME"
        value = var.db_user
      }

      env {
        name  = "ZITADEL_DATABASE_POSTGRES_ADMIN_USERNAME"
        value = "postgres"
      }

      env {
        name  = "ZITADEL_DATABASE_POSTGRES_USER_SSL_MODE"
        value = "disable"
      }

      env {
        name  = "ZITADEL_DATABASE_POSTGRES_ADMIN_SSL_MODE"
        value = "disable"
      }

      env {
        name = "ZITADEL_DATABASE_POSTGRES_USER_PASSWORD"
        value_source {
          secret_key_ref {
            secret  = "projects/${var.project_id}/secrets/${var.db_password_secret_id}"
            version = "latest"
          }
        }
      }

      env {
        name = "ZITADEL_DATABASE_POSTGRES_ADMIN_PASSWORD"
        value_source {
          secret_key_ref {
            secret  = "projects/${var.project_id}/secrets/${var.db_admin_password_secret_id}"
            version = "latest"
          }
        }
      }

      env {
        name = "ZITADEL_MASTERKEY"
        value_source {
          secret_key_ref {
            secret  = "projects/${var.project_id}/secrets/${var.masterkey_secret_id}"
            version = "latest"
          }
        }
      }

      startup_probe {
        http_get {
          path = "/debug/healthz"
          port = 8080
        }
        initial_delay_seconds = 15
        timeout_seconds       = 5
        period_seconds        = 10
        failure_threshold     = 30
      }

      liveness_probe {
        http_get {
          path = "/debug/healthz"
          port = 8080
        }
        period_seconds    = 30
        failure_threshold = 3
      }
    }

    timeout = "300s"
  }

  labels = {
    service    = "zitadel"
    managed_by = "terraform"
  }
}

# Zitadel must be publicly accessible (login pages)
resource "google_cloud_run_v2_service_iam_member" "zitadel_public" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.zitadel.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
