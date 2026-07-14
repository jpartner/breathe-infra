# Zitadel Configuration
# Manages organizations, projects, OIDC applications, and roles.
# Authenticates via a service account key created during bootstrap.
#
# Structure:
#   Organization (1 per tenant)
#     └── Project (1 per environment)
#           ├── OIDC App: Backend API
#           ├── OIDC App: Admin UI
#           └── OIDC App: Customer Frontend

# =============================================================================
# Organizations (one per tenant)
# =============================================================================

resource "zitadel_org" "tenants" {
  for_each = var.tenants
  name     = each.value.display_name
}

# =============================================================================
# Projects (one per tenant × environment)
# =============================================================================

locals {
  # Flatten tenant × environment into a map
  tenant_envs = merge([
    for tenant_key, tenant in var.tenants : {
      for env_key, env in var.environments :
      "${tenant_key}-${env_key}" => {
        tenant_key   = tenant_key
        env_key      = env_key
        org_id       = zitadel_org.tenants[tenant_key].id
        display_name = "${tenant.display_name} (${env.display_name})"
        api_domain   = env.api_domain
        admin_domain = env.admin_domain
        app_domains  = lookup(tenant.domains, env_key, [])
      }
    }
  ]...)
}

resource "zitadel_project" "envs" {
  for_each = local.tenant_envs

  org_id                 = each.value.org_id
  name                   = each.value.display_name
  project_role_assertion = true
}

# =============================================================================
# OIDC Applications — Backend API (per tenant × environment)
# =============================================================================

resource "zitadel_application_api" "backend" {
  for_each = local.tenant_envs

  org_id     = each.value.org_id
  project_id = zitadel_project.envs[each.key].id
  name       = "Backend API"

  auth_method_type = "API_AUTH_METHOD_TYPE_BASIC"
}

# =============================================================================
# OIDC Applications — Admin UI (per tenant × environment)
# =============================================================================

resource "zitadel_application_oidc" "admin" {
  for_each = local.tenant_envs

  org_id     = each.value.org_id
  project_id = zitadel_project.envs[each.key].id
  name       = "Admin UI"

  redirect_uris = [
    "https://${each.value.admin_domain}/api/auth/callback/zitadel",
    "http://localhost:3000/api/auth/callback/zitadel",
  ]

  post_logout_redirect_uris = [
    "https://${each.value.admin_domain}",
    "http://localhost:3000",
  ]

  response_types             = ["OIDC_RESPONSE_TYPE_CODE"]
  grant_types                = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE", "OIDC_GRANT_TYPE_REFRESH_TOKEN"]
  app_type                   = "OIDC_APP_TYPE_WEB"
  auth_method_type           = "OIDC_AUTH_METHOD_TYPE_NONE"
  access_token_type          = "OIDC_TOKEN_TYPE_JWT"
  id_token_role_assertion    = true
  id_token_userinfo_assertion = true
}

# =============================================================================
# OIDC Applications — Customer Frontend (per tenant × environment)
# =============================================================================

resource "zitadel_application_oidc" "customer" {
  for_each = { for k, v in local.tenant_envs : k => v if length(v.app_domains) > 0 }

  org_id     = each.value.org_id
  project_id = zitadel_project.envs[each.key].id
  name       = "Customer App"

  redirect_uris = concat(
    [for d in each.value.app_domains : "https://${d}/api/auth/callback/zitadel"],
    ["http://localhost:3001/api/auth/callback/zitadel"],
  )

  post_logout_redirect_uris = concat(
    [for d in each.value.app_domains : "https://${d}"],
    ["http://localhost:3001"],
  )

  response_types             = ["OIDC_RESPONSE_TYPE_CODE"]
  grant_types                = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE", "OIDC_GRANT_TYPE_REFRESH_TOKEN"]
  app_type                   = "OIDC_APP_TYPE_WEB"
  auth_method_type           = "OIDC_AUTH_METHOD_TYPE_NONE"
  access_token_type          = "OIDC_TOKEN_TYPE_JWT"
  id_token_role_assertion    = true
  id_token_userinfo_assertion = true
}

# =============================================================================
# Project Roles
# =============================================================================

resource "zitadel_project_role" "roles" {
  for_each = {
    for pair in setproduct(keys(local.tenant_envs), var.roles) :
    "${pair[0]}-${pair[1].key}" => {
      tenant_env_key = pair[0]
      role_key       = pair[1].key
      display_name   = pair[1].display_name
      group          = pair[1].group
    }
  }

  org_id       = local.tenant_envs[each.value.tenant_env_key].org_id
  project_id   = zitadel_project.envs[each.value.tenant_env_key].id
  role_key     = each.value.role_key
  display_name = each.value.display_name
  group        = each.value.group
}
