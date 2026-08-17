# =============================================================================
# The deploy hub's transaction runner
# =============================================================================
#
# Created imperatively before this file existed, so it held the test database
# password and four PATs while nothing declared it: invisible to `plan`, able
# to survive a destroy, and silently divergent from the repo. Adopted here on
# 2026-08-14 by importing the live job — the resource below was written to
# match what was already running, and a targeted plan reported no changes
# before anything was altered.
#
# The image is deploy-managed: unifeed-test's own Cloud Build updates this job
# on every push, so Terraform must not fight it. Same guard the services carry.
resource "google_cloud_run_v2_job" "unifeed_test_runner" {
  name     = "unifeed-test-runner"
  project  = var.project_id
  location = var.region

  lifecycle {
    ignore_changes = [
      template[0].template[0].containers[0].image,
      template[0].labels,
      labels,
      client,
      client_version,
    ]
  }

  template {
    template {
      service_account = "sa-test-runner@${var.project_id}.iam.gserviceaccount.com"

      # A full transaction is a deploy plus four test phases; 50 minutes is the
      # ceiling that keeps a wedged run from occupying the queue indefinitely.
      # max_retries 0: a failed transaction must not silently re-run and deploy
      # a second time — the hub requeues deliberately or not at all.
      timeout     = "3000s"
      max_retries = 0

      vpc_access {
        connector = "projects/${var.project_id}/locations/${var.region}/connectors/breathe-vpc-connector"
        egress    = "PRIVATE_RANGES_ONLY"
      }

      containers {
        image   = "${var.region}-docker.pkg.dev/${var.project_id}/unifeed-test/unifeed-test:latest"
        command = ["pnpm"]
        args    = ["exec", "tsx", "scripts/run-transaction.ts"]

        resources {
          limits = {
            cpu    = "2"
            memory = "4Gi"
          }
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
          value = "10.219.0.5"
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
          name  = "ADMIN_URL"
          value = "https://admin-uniten.dev.unifeed.io"
        }
        env {
          name  = "TEST_LOGIN_EMAIL"
          value = "e2e-test@unifeed.io"
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
        env {
          name = "TEST_ADMIN_PAT"
          value_source {
            secret_key_ref {
              secret  = "unifeed-test-admin-pat"
              version = "latest"
            }
          }
        }
        env {
          name = "TEST_CUSTOMER_PAT"
          value_source {
            secret_key_ref {
              secret  = "unifeed-test-customer-pat"
              version = "latest"
            }
          }
        }
        env {
          name = "TEST_NOROLE_PAT"
          value_source {
            secret_key_ref {
              secret  = "unifeed-test-norole-pat"
              version = "latest"
            }
          }
        }
        env {
          name = "TEST_CSR_PAT"
          value_source {
            secret_key_ref {
              secret  = "unifeed-test-csr-pat"
              version = "latest"
            }
          }
        }
        env {
          name = "TEST_LOGIN_PASSWORD"
          value_source {
            secret_key_ref {
              secret  = "unifeed-test-login-password"
              version = "latest"
            }
          }
        }
        env {
          name  = "TEST_CSR_LOGIN_EMAIL"
          value = "e2e-csr@unifeed.io"
        }
        env {
          name  = "TEST_DESIGNER_LOGIN_EMAIL"
          value = "e2e-designer@unifeed.io"
        }
        env {
          name  = "TEST_ADMIN_LOGIN_EMAIL"
          value = "e2e-admin@unifeed.io"
        }
        env {
          name  = "SMOKE_PHASE_ENABLED"
          value = "1"
        }

        # Phase-by-phase transaction updates in Slack. The runner posts one
        # message per transaction and edits it as each phase lands, rather than
        # a message per phase — the Cloud Build notifier in
        # build-notifications.tf already established that a message per status
        # transition produces "a channel nobody reads".
        #
        # Appended rather than inserted: env is an ordered list to Terraform,
        # and inserting mid-list renames every block after it. On this resource
        # that proposed rewriting DB_PASSWORD's secret_key_ref as a plain value.
        env {
          name  = "SLACK_CHANNEL"
          value = var.slack_build_channel
        }
        env {
          name = "SLACK_BOT_TOKEN"
          value_source {
            secret_key_ref {
              secret  = "slack-bot-token"
              version = "latest"
            }
          }
        }
      }
    }
  }
}

# The Slack bot token is an adopted secret (adopted-secrets.tf), created before
# this repo managed it, so it is referenced by name rather than by resource.
resource "google_secret_manager_secret_iam_member" "test_runner_slack" {
  project   = var.project_id
  secret_id = "slack-bot-token"
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.test_runner.email}"
}
