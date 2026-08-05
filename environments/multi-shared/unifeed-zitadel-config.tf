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
