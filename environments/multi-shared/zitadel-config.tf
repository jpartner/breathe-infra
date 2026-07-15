# Zitadel identity configuration
# Manages organizations, projects, and OIDC applications for all tenants/environments.
#
# IMPORTANT: This requires Zitadel to be running. On first apply, run with
# zitadel_manage_config=false, then re-apply with zitadel_manage_config=true
# after Zitadel is up and a service user key has been created.

provider "zitadel" {
  domain           = var.zitadel_domain
  port             = "443"
  insecure         = false
  jwt_profile_file = var.zitadel_service_account_key_path
}

module "zitadel_config" {
  count  = var.zitadel_manage_config ? 1 : 0
  source = "../../modules/zitadel-config"

  tenants = {
    breathe = {
      display_name = "Breathe Branding"
      domains = {
        dev     = ["dev.breathebranding.co.uk"]
        staging = ["staging.breathebranding.co.uk"]
        prod    = ["breathebranding.co.uk", "www.breathebranding.co.uk"]
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
      api_domain   = "api.dev.breathebranding.co.uk"
      admin_domain = "admin.dev.breathebranding.co.uk"
    }
    staging = {
      display_name = "Staging"
      api_domain   = "api.staging.breathebranding.co.uk"
      admin_domain = "admin.staging.breathebranding.co.uk"
    }
    prod = {
      display_name = "Production"
      api_domain   = "api.breathebranding.co.uk"
      admin_domain = "admin.breathebranding.co.uk"
    }
  }
}

# =============================================================================
# SMTP — Postmark for auth emails
# =============================================================================

resource "google_secret_manager_secret" "postmark_auth_token" {
  project   = var.project_id
  secret_id = "postmark-auth-token"
  replication {
    auto {}
  }
}

resource "zitadel_smtp_config" "postmark" {
  count = var.zitadel_manage_config ? 1 : 0

  sender_address = var.zitadel_smtp_sender
  sender_name    = "Breathe"
  tls            = true
  host           = "smtp.postmarkapp.com:587"
  user           = var.zitadel_smtp_password
  password       = var.zitadel_smtp_password
}
