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

variable "db_connection_name" {
  description = "Cloud SQL instance connection name"
  type        = string
}

# Auth
variable "auth_issuer_url" {
  description = "Zitadel OIDC issuer URL"
  type        = string
  default     = ""
}

variable "zitadel_admin_client_id" {
  description = "Zitadel OIDC client ID for admin app"
  type        = string
  default     = "383218689803110726"
}

# Cloudflare
variable "cloudflare_api_token" {
  description = "Cloudflare API token with Zone:DNS:Edit for breathebranding.co.uk"
  type        = string
  sensitive   = true
  default     = ""
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
  default     = ""
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
