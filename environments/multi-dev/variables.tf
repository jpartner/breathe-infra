variable "project_id" {
  type    = string
  default = "breathe-dev-env"
}

variable "region" {
  type    = string
  default = "europe-west2"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "shared_project_id" {
  type    = string
  default = "breathe-shared"
}

variable "vpc_connector_id" {
  description = "VPC connector from shared project"
  type        = string
  default     = null
}

# Database
variable "db_name" {
  type    = string
  default = "breathe_multi_dev"
}

variable "db_user" {
  type    = string
  default = "app"
}

# Auth
variable "auth_issuer_url" {
  description = "Zitadel OIDC issuer URL"
  type        = string
  default     = ""
}

variable "unifeed_zitadel_issuer" {
  description = "Unifeed Zitadel OIDC issuer URL"
  type        = string
  default     = "https://auth.unifeed.io"
}

variable "storefront_breathe_client_id" {
  description = "Zitadel customer OIDC client ID for Breathe storefront (dev)"
  type        = string
  default     = null
}

variable "storefront_pa_client_id" {
  description = "Zitadel customer OIDC client ID for PA storefront (dev)"
  type        = string
  default     = null
}

variable "storefront_uniten_client_id" {
  description = "Zitadel customer OIDC client ID for Uniten storefront (dev)"
  type        = string
  default     = null
}

# OIDC client IDs are read from multi-shared's outputs in client-ids.tf. These
# variables exist only to pin one by hand; left null they come from that state,
# so there is nothing to refresh after multi-shared replaces an application.
variable "admin_breathe_client_id" {
  description = "Zitadel admin UI OIDC client ID for Breathe (dev)"
  type        = string
  default     = null
}

variable "admin_pa_client_id" {
  description = "Zitadel admin UI OIDC client ID for PA (dev)"
  type        = string
  default     = null
}

variable "admin_uniten_client_id" {
  description = "Zitadel admin UI OIDC client ID for Uniten (dev)"
  type        = string
  default     = null
}

# Cloudflare
variable "cloudflare_api_token" {
  description = "Cloudflare API token with Zone:DNS:Edit for breathebranding.co.uk"
  type        = string
  sensitive   = true
  default     = null
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID for breathebranding.co.uk"
  type        = string
  default     = "4dc7218313de868751814ec5055e7fd7"
}

variable "unifeed_cloudflare_api_token" {
  description = "Cloudflare API token for unifeed.io DNS"
  type        = string
  sensitive   = true
  default     = null
}

variable "unifeed_cloudflare_zone_id" {
  description = "Cloudflare zone ID for unifeed.io"
  type        = string
  default     = "5f93decf4a452ae42913b147b4f6ed74"
}

variable "breathe_eu_cloudflare_zone_id" {
  description = "Cloudflare zone ID for breathebranding.eu"
  type        = string
  default     = "dfe1f68487b88da8faa3ae5dba7939d2"
}

variable "db_host" {
  description = "Cloud SQL private IP"
  type        = string
  default     = "10.219.0.5"
}

variable "typesense_host" {
  description = "Typesense Cloud host"
  type        = string
  default     = "c7op2qkelxuh81n3p-1.a1.typesense.net"
}

variable "breathe_live_project_id" {
  description = "Project running the live (pre-Unifeed) Breathe system"
  type        = string
  default     = "breathe-dev"
}

variable "breathe_sql_connection_name" {
  description = "Cloud SQL connection name of the live Breathe database"
  type        = string
  default     = "breathe-dev:europe-west2:breathe-branding"
}

variable "zitadel_org_map" {
  description = "Unifeed tenant code -> Zitadel organisation id"
  type        = map(string)
  default = {
    uniten  = "384307974325186060"
    breathe = "384307372207681036"
    pa      = "384307372308344332"
  }
}

variable "zitadel_project_map" {
  description = "Unifeed tenant code -> Zitadel project id (this environment)"
  type        = map(string)
  default = {
    uniten  = "384307979559677452"
    breathe = "384307378247478796"
    pa      = "384307378314587660"
  }
}
