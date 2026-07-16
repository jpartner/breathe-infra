# Platform-level Zitadel resources
# These are NOT tenant-specific — they're for internal platform tools.
# Lives in the default ZITADEL org.

# =============================================================================
# Platform Tools Project
# =============================================================================

resource "zitadel_project" "platform" {
  org_id                 = var.zitadel_default_org_id
  name                   = "Platform Tools"
  project_role_assertion = true
}

resource "zitadel_project_role" "platform_admin" {
  org_id       = var.zitadel_default_org_id
  project_id   = zitadel_project.platform.id
  role_key     = "admin"
  display_name = "Platform Administrator"
  group        = "platform"
}

# =============================================================================
# Test Runner — OIDC Application
# =============================================================================

resource "zitadel_application_oidc" "test_runner" {
  org_id     = var.zitadel_default_org_id
  project_id = zitadel_project.platform.id
  name       = "Test Runner"

  redirect_uris = [
    "https://test.breathebranding.co.uk/api/auth/callback/zitadel",
    "http://localhost:3000/api/auth/callback/zitadel",
  ]

  post_logout_redirect_uris = [
    "https://test.breathebranding.co.uk",
    "http://localhost:3000",
  ]

  response_types             = ["OIDC_RESPONSE_TYPE_CODE"]
  grant_types                = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE", "OIDC_GRANT_TYPE_REFRESH_TOKEN"]
  app_type                   = "OIDC_APP_TYPE_WEB"
  auth_method_type           = "OIDC_AUTH_METHOD_TYPE_BASIC"
  access_token_type          = "OIDC_TOKEN_TYPE_JWT"
  id_token_role_assertion    = true
  id_token_userinfo_assertion = true
}

# Store the client secret in Secret Manager
resource "google_secret_manager_secret_version" "test_runner_zitadel_secret" {
  secret      = google_secret_manager_secret.test_runner_zitadel_secret.id
  secret_data = zitadel_application_oidc.test_runner.client_secret
}

# Store the auth secret (NextAuth session encryption)
resource "random_password" "test_runner_auth_secret" {
  length  = 32
  special = false
}

resource "google_secret_manager_secret_version" "test_runner_auth_secret" {
  secret      = google_secret_manager_secret.test_runner_auth_secret.id
  secret_data = random_password.test_runner_auth_secret.result
}
