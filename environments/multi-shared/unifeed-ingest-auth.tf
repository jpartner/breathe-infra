# Ingest tool — Zitadel OIDC app on auth.unifeed.io
# Single shared instance, not per-tenant.

locals {
  unifeed_org_id = "384307974325186060"
}

resource "zitadel_project" "ingest" {
  provider = zitadel.unifeed

  org_id                 = local.unifeed_org_id
  name                   = "Ingest Tools"
  project_role_assertion = true
}

resource "zitadel_application_oidc" "ingest" {
  provider = zitadel.unifeed

  org_id     = local.unifeed_org_id
  project_id = zitadel_project.ingest.id
  name       = "Ingest"

  redirect_uris = [
    "https://ingest.unifeed.io/api/auth/callback/zitadel",
    "http://localhost:3002/api/auth/callback/zitadel",
  ]

  post_logout_redirect_uris = [
    "https://ingest.unifeed.io",
    "http://localhost:3002",
  ]

  response_types              = ["OIDC_RESPONSE_TYPE_CODE"]
  grant_types                 = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE", "OIDC_GRANT_TYPE_REFRESH_TOKEN"]
  app_type                    = "OIDC_APP_TYPE_WEB"
  auth_method_type            = "OIDC_AUTH_METHOD_TYPE_BASIC"
  access_token_type           = "OIDC_TOKEN_TYPE_JWT"
  id_token_role_assertion     = true
  id_token_userinfo_assertion = true
  access_token_role_assertion = true
}

# Store client secret in Secret Manager
resource "google_secret_manager_secret" "ingest_zitadel_secret" {
  project   = var.project_id
  secret_id = "ingest-zitadel-client-secret"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "ingest_zitadel_secret" {
  secret      = google_secret_manager_secret.ingest_zitadel_secret.id
  secret_data = zitadel_application_oidc.ingest.client_secret
}

# NextAuth session encryption secret
resource "random_password" "ingest_auth_secret" {
  length  = 32
  special = false
}

resource "google_secret_manager_secret" "ingest_auth_secret" {
  project   = var.project_id
  secret_id = "ingest-auth-secret"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "ingest_auth_secret" {
  secret      = google_secret_manager_secret.ingest_auth_secret.id
  secret_data = random_password.ingest_auth_secret.result
}
