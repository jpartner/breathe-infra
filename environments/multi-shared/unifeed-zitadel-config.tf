# Unifeed Zitadel identity configuration
# Manages organizations, projects, and OIDC applications for all tenants/environments.

provider "zitadel" {
  alias            = "unifeed"
  domain           = var.unifeed_zitadel_domain
  port             = "443"
  insecure         = false
  jwt_profile_file = var.unifeed_zitadel_key_path
}

module "unifeed_zitadel_config" {
  count    = var.unifeed_zitadel_manage_config ? 1 : 0
  source   = "../../modules/zitadel-config"

  providers = {
    zitadel = zitadel.unifeed
  }

  tenants = {
    unifeed = {
      display_name = "Unifeed"
      domains = {
        dev     = ["dev.unifeed.io"]
        staging = ["staging.unifeed.io"]
        prod    = ["unifeed.io", "www.unifeed.io"]
      }
    }
    breathe = {
      display_name = "Breathe Branding"
      domains = {
        dev     = ["dev.breathebranding.co.uk"]
        staging = ["staging.breathebranding.co.uk"]
        prod    = ["breathebranding.co.uk", "www.breathebranding.co.uk", "breathebranding.eu", "breathebranding.com.au"]
      }
    }
    pa = {
      display_name = "PA Promotions"
      domains = {
        dev     = ["dev.pa-promotions.co.uk"]
        staging = ["staging.pa-promotions.co.uk"]
        prod    = ["pa-promotions.co.uk", "www.pa-promotions.co.uk"]
      }
    }
  }

  environments = {
    dev = {
      display_name = "Development"
      api_domain   = "api.dev.unifeed.io"
      admin_domain = "admin.dev.unifeed.io"
      ops_domain   = "ops.dev.unifeed.io"
    }
    staging = {
      display_name = "Staging"
      api_domain   = "api.staging.unifeed.io"
      admin_domain = "admin.staging.unifeed.io"
      ops_domain   = "ops.staging.unifeed.io"
    }
    prod = {
      display_name = "Production"
      api_domain   = "api.unifeed.io"
      admin_domain = "admin.unifeed.io"
      ops_domain   = "ops.unifeed.io"
    }
  }
}

# =============================================================================
# Customer Auth — NextAuth session secrets in Secret Manager
# Note: Customer OIDC apps use AUTH_METHOD_TYPE_NONE (public clients, no secret needed)
# =============================================================================

# NextAuth secret (random) for each storefront
resource "random_password" "storefront_auth_secret" {
  for_each = toset(["breathe", "breathe-eu", "pa", "uniten"])
  length   = 32
  special  = false
}

resource "google_secret_manager_secret" "storefront_auth_secret" {
  for_each  = random_password.storefront_auth_secret

  project   = var.project_id
  secret_id = "storefront-${each.key}-auth-secret"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "storefront_auth_secret" {
  for_each    = google_secret_manager_secret.storefront_auth_secret

  secret      = each.value.id
  secret_data = random_password.storefront_auth_secret[each.key].result
}

# =============================================================================
# Test Users — machine users (PATs for API tests) + human users (UI login tests)
# All created in the "unifeed" org on the "unifeed-dev" project (uniten tenant)
# =============================================================================

# -- Machine users (for API tests with PATs) --

resource "zitadel_machine_user" "test_admin" {
  count    = var.unifeed_zitadel_manage_config ? 1 : 0
  provider = zitadel.unifeed

  org_id            = module.unifeed_zitadel_config[0].org_ids["unifeed"]
  user_name         = "e2e-test-admin"
  name              = "E2E Test Admin"
  description       = "Machine user for API tests — admin role"
  access_token_type = "ACCESS_TOKEN_TYPE_BEARER"
}

resource "zitadel_personal_access_token" "test_admin" {
  count    = var.unifeed_zitadel_manage_config ? 1 : 0
  provider = zitadel.unifeed

  org_id  = module.unifeed_zitadel_config[0].org_ids["unifeed"]
  user_id = zitadel_machine_user.test_admin[0].id
}

resource "zitadel_user_grant" "test_admin" {
  count    = var.unifeed_zitadel_manage_config ? 1 : 0
  provider = zitadel.unifeed

  org_id     = module.unifeed_zitadel_config[0].org_ids["unifeed"]
  project_id = module.unifeed_zitadel_config[0].project_ids["unifeed-dev"]
  user_id    = zitadel_machine_user.test_admin[0].id
  role_keys  = ["admin"]
}

resource "zitadel_machine_user" "test_customer" {
  count    = var.unifeed_zitadel_manage_config ? 1 : 0
  provider = zitadel.unifeed

  org_id            = module.unifeed_zitadel_config[0].org_ids["unifeed"]
  user_name         = "e2e-test-customer"
  name              = "E2E Test Customer"
  description       = "Machine user for API tests — customer role"
  access_token_type = "ACCESS_TOKEN_TYPE_BEARER"
}

resource "zitadel_personal_access_token" "test_customer" {
  count    = var.unifeed_zitadel_manage_config ? 1 : 0
  provider = zitadel.unifeed

  org_id  = module.unifeed_zitadel_config[0].org_ids["unifeed"]
  user_id = zitadel_machine_user.test_customer[0].id
}

resource "zitadel_user_grant" "test_customer" {
  count    = var.unifeed_zitadel_manage_config ? 1 : 0
  provider = zitadel.unifeed

  org_id     = module.unifeed_zitadel_config[0].org_ids["unifeed"]
  project_id = module.unifeed_zitadel_config[0].project_ids["unifeed-dev"]
  user_id    = zitadel_machine_user.test_customer[0].id
  role_keys  = ["customer"]
}

resource "zitadel_machine_user" "test_norole" {
  count    = var.unifeed_zitadel_manage_config ? 1 : 0
  provider = zitadel.unifeed

  org_id            = module.unifeed_zitadel_config[0].org_ids["unifeed"]
  user_name         = "e2e-test-norole"
  name              = "E2E Test No Role"
  description       = "Machine user for API tests — no role granted"
  access_token_type = "ACCESS_TOKEN_TYPE_BEARER"
}

resource "zitadel_personal_access_token" "test_norole" {
  count    = var.unifeed_zitadel_manage_config ? 1 : 0
  provider = zitadel.unifeed

  org_id  = module.unifeed_zitadel_config[0].org_ids["unifeed"]
  user_id = zitadel_machine_user.test_norole[0].id
}

# -- Human user (for UI login tests via Playwright) --

resource "zitadel_human_user" "test_login" {
  count    = var.unifeed_zitadel_manage_config ? 1 : 0
  provider = zitadel.unifeed

  org_id     = module.unifeed_zitadel_config[0].org_ids["unifeed"]
  user_name  = "e2e-test-login"
  first_name = "Test"
  last_name  = "User"
  email      = "e2e-test@unifeed.io"
  is_email_verified = true

  initial_password             = var.unifeed_test_user_password
  initial_skip_password_change = true
}

resource "zitadel_user_grant" "test_login" {
  count    = var.unifeed_zitadel_manage_config ? 1 : 0
  provider = zitadel.unifeed

  org_id     = module.unifeed_zitadel_config[0].org_ids["unifeed"]
  project_id = module.unifeed_zitadel_config[0].project_ids["unifeed-dev"]
  user_id    = zitadel_human_user.test_login[0].id
  role_keys  = ["customer"]
}

# -- Store PATs and test credentials in Secret Manager --

resource "google_secret_manager_secret" "test_pats" {
  for_each  = var.unifeed_zitadel_manage_config ? toset(["admin", "customer", "norole"]) : toset([])

  project   = var.project_id
  secret_id = "unifeed-test-${each.key}-pat"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "test_admin_pat" {
  count       = var.unifeed_zitadel_manage_config ? 1 : 0
  secret      = google_secret_manager_secret.test_pats["admin"].id
  secret_data = zitadel_personal_access_token.test_admin[0].token
}

resource "google_secret_manager_secret_version" "test_customer_pat" {
  count       = var.unifeed_zitadel_manage_config ? 1 : 0
  secret      = google_secret_manager_secret.test_pats["customer"].id
  secret_data = zitadel_personal_access_token.test_customer[0].token
}

resource "google_secret_manager_secret_version" "test_norole_pat" {
  count       = var.unifeed_zitadel_manage_config ? 1 : 0
  secret      = google_secret_manager_secret.test_pats["norole"].id
  secret_data = zitadel_personal_access_token.test_norole[0].token
}

resource "google_secret_manager_secret" "test_login_password" {
  count     = var.unifeed_zitadel_manage_config ? 1 : 0

  project   = var.project_id
  secret_id = "unifeed-test-login-password"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "test_login_password" {
  count       = var.unifeed_zitadel_manage_config ? 1 : 0
  secret      = google_secret_manager_secret.test_login_password[0].id
  secret_data = var.unifeed_test_user_password
}
