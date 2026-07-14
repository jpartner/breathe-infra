variable "project_id" {
  description = "GCP project ID for shared resources"
  type        = string
  default     = "breathe-shared"
}

variable "region" {
  description = "Primary GCP region"
  type        = string
  default     = "europe-west2"
}

variable "github_owner" {
  description = "GitHub repository owner"
  type        = string
  default     = "jpartner"
}

variable "environment_project_ids" {
  description = "List of environment project IDs that need access to shared resources"
  type        = list(string)
  default     = ["breathe-dev-env", "breathe-staging-env", "breathe-production-env"]
}

variable "environment_project_numbers" {
  description = "List of environment project numbers (for service agent IAM)"
  type        = list(string)
}

# Zitadel
variable "zitadel_domain" {
  description = "Domain for Zitadel auth server"
  type        = string
  default     = "auth.breathebranding.co.uk"
}

variable "zitadel_db_connection" {
  description = "Cloud SQL connection name for Zitadel database"
  type        = string
  default     = ""
}

variable "zitadel_db_password_secret_id" {
  description = "Secret Manager secret ID for Zitadel DB password"
  type        = string
  default     = "zitadel-db-password"
}

variable "zitadel_masterkey_secret_id" {
  description = "Secret Manager secret ID for Zitadel master key"
  type        = string
  default     = "zitadel-masterkey"
}

variable "zitadel_service_account_key_path" {
  description = "Path to Zitadel service account JSON key (for Terraform provider auth)"
  type        = string
  default     = ""
}
