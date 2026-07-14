# Zitadel identity configuration
# Manages organizations, projects, and OIDC applications for all tenants/environments.
#
# Bootstrap: create a service account in the Zitadel UI, download the JSON key,
# then set the path via ZITADEL_SERVICE_ACCOUNT_KEY_PATH environment variable
# before running terraform.

terraform {
  required_providers {
    zitadel = {
      source  = "zitadel/zitadel"
      version = "~> 3.2"
    }
  }
}

provider "zitadel" {
  domain           = var.zitadel_domain
  port             = "443"
  insecure         = false
  jwt_profile_file = var.zitadel_service_account_key_path
}

module "zitadel_config" {
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
