# Deploy hub (hub.dev.unifeed.io) — Zitadel OIDC app on auth.unifeed.io
#
# Lives in the same Zitadel project as the ingest tool, so one "admin" grant
# on that project is the platform-admins group covering both tools.

resource "zitadel_application_oidc" "hub" {
  provider = zitadel.unifeed

  org_id     = local.unifeed_org_id
  project_id = zitadel_project.ingest.id
  name       = "Deploy Hub"

  redirect_uris = [
    "https://hub.dev.unifeed.io/api/auth/callback/zitadel",
    "http://localhost:3000/api/auth/callback/zitadel",
  ]

  post_logout_redirect_uris = [
    "https://hub.dev.unifeed.io",
    "http://localhost:3000",
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

resource "google_secret_manager_secret" "hub_zitadel_secret" {
  project   = var.project_id
  secret_id = "hub-zitadel-client-secret"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "hub_zitadel_secret" {
  secret      = google_secret_manager_secret.hub_zitadel_secret.id
  secret_data = zitadel_application_oidc.hub.client_secret
}

# NextAuth session encryption secret
resource "random_password" "hub_auth_secret" {
  length  = 32
  special = false
}

resource "google_secret_manager_secret" "hub_auth_secret" {
  project   = var.project_id
  secret_id = "hub-auth-secret"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "hub_auth_secret" {
  secret      = google_secret_manager_secret.hub_auth_secret.id
  secret_data = random_password.hub_auth_secret.result
}

# =============================================================================
# Platform admins
# Human users granted the platform-tools admin role. Email starts unverified
# so Zitadel sends an initialization mail (SMTP via Postmark) for the user to
# set their own password.
# =============================================================================

resource "zitadel_human_user" "tom" {
  provider = zitadel.unifeed

  org_id     = local.unifeed_org_id
  user_name  = "tom@breathebranding.co.uk"
  first_name = "Tom"
  last_name  = "Breathe"
  email      = "tom@breathebranding.co.uk"
}

resource "zitadel_user_grant" "tom_platform_admin" {
  provider = zitadel.unifeed

  org_id     = local.unifeed_org_id
  project_id = zitadel_project.ingest.id
  user_id    = zitadel_human_user.tom.id
  role_keys  = ["admin"]
}
