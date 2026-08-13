# =============================================================================
# PA legacy lookup service
# =============================================================================
#
# Read-only lookups against the live Breathe Postgres, served to the PA admin UI
# so staff can see legacy PA data alongside the new system.
#
# It lives here rather than in an environment root because there is only ever
# one of it: it reads a single live legacy database that is not per-environment,
# so a copy per environment would be several services pointed at the same rows.
# It was originally built in multi-dev and moved 2026-08-13.
#
# The service is stateless — no VPC connector, no local data, and its image
# already lives in this project's Artifact Registry — so the move is a genuine
# relocation rather than a rebuild.

resource "google_service_account" "pa_migration" {
  project      = var.project_id
  account_id   = "sa-pa-migration"
  display_name = "PA Migration Service Account"
  description  = "Service account for PA legacy lookup Cloud Run service"
}

resource "google_secret_manager_secret_iam_member" "pa_migration_api_key" {
  project   = var.project_id
  secret_id = "pa-migration-api-key"
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.pa_migration.email}"
}

resource "google_secret_manager_secret_iam_member" "pa_migration_breathe_db_password" {
  project   = var.project_id
  secret_id = "breathe-legacy-db-password"
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.pa_migration.email}"
}

# The one grant this config makes on the legacy breathe-dev project. It is
# read-only client access to Cloud SQL for a service that issues SELECTs as a
# role restricted to SELECT — it does not manage anything in that project, and
# the README's "never modify breathe-dev" still holds for everything else.
resource "google_project_iam_member" "pa_migration_breathe_sql" {
  project = var.breathe_live_project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.pa_migration.email}"
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
      client,
      client_version,
    ]
  }

  template {
    service_account = google_service_account.pa_migration.email

    scaling {
      min_instance_count = 0
      max_instance_count = 2
    }

    containers {
      image = "${var.region}-docker.pkg.dev/${var.project_id}/pa-migration/pa-migration:latest"

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
            secret  = "projects/${var.project_id}/secrets/pa-migration-api-key"
            version = "latest"
          }
        }
      }

      # Breathe legacy source: read-only lookups against the live Breathe
      # Postgres over the Cloud SQL socket, served under /breathe
      env {
        name  = "BREATHE_SQL_INSTANCE"
        value = var.breathe_sql_connection_name
      }
      env {
        name  = "BREATHE_DB_NAME"
        value = "breathe_prod"
      }
      env {
        name  = "BREATHE_DB_USER"
        value = "legacy_lookup" # read-only role: SELECT only, created 2026-08-11
      }
      env {
        name = "BREATHE_DB_PASSWORD"
        value_source {
          secret_key_ref {
            secret  = "projects/${var.project_id}/secrets/breathe-legacy-db-password"
            version = "latest"
          }
        }
      }

      volume_mounts {
        name       = "cloudsql"
        mount_path = "/cloudsql"
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

    volumes {
      name = "cloudsql"
      cloud_sql_instance {
        instances = [var.breathe_sql_connection_name]
      }
    }

    timeout = "60s"
  }

  labels = {
    managed_by = "terraform"
  }
}

# Public at the load balancer, as before. The service authenticates callers with
# PA_LEGACY_API_KEY rather than IAM, so removing allUsers would lock out the
# admin UI without gaining anything — the key is the control.
resource "google_cloud_run_v2_service_iam_member" "pa_migration_public" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.pa_migration.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# DNS for the new host. pa-migration.unifeed.io rather than the old
# pa.dev.breathebranding.co.uk: the service is not per-environment so it should
# not carry a .dev, and it is not a Breathe service so it should not sit on the
# Breathe brand domain. The old name also collided confusingly with
# pa.dev.unifeed.io, which is the customer-facing PA storefront — two different
# services distinguished only by their domain.
resource "cloudflare_record" "pa_migration" {
  provider = cloudflare.unifeed

  zone_id = var.unifeed_cloudflare_zone_id
  name    = "pa-migration"
  content = module.platform_lb.ip_address
  type    = "A"
  proxied = false
  ttl     = 300
}
