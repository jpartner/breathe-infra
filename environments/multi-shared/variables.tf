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

variable "zitadel_service_account_key_path" {
  description = "Path to Zitadel service account JSON key (for Terraform provider auth)"
  type        = string
  default     = ""
}

variable "zitadel_manage_config" {
  description = "Whether to manage Zitadel orgs/projects/apps (requires Zitadel running + service user key)"
  type        = bool
  default     = false
}

variable "zitadel_smtp_sender" {
  description = "Sender email address for Zitadel auth emails"
  type        = string
  default     = "hello@breathebranding.co.uk"
}

variable "zitadel_smtp_password" {
  description = "Postmark Server API token for SMTP auth"
  type        = string
  sensitive   = true
  default     = ""
}

# Zitadel default org (ZITADEL org, used for platform-level resources)
variable "zitadel_default_org_id" {
  description = "Default Zitadel organization ID for platform resources"
  type        = string
  default     = "381719479391980205"
}

# Google OAuth (for Zitadel Google IdP)
variable "google_oauth_client_id" {
  description = "Google OAuth client ID for Zitadel Google login"
  type        = string
  default     = "869820587346-cud6q2doompdsdif7ckvm40rkreu512a.apps.googleusercontent.com"
}

variable "google_oauth_client_secret" {
  description = "Google OAuth client secret"
  type        = string
  sensitive   = true
  default     = ""
}

# Database
variable "db_tier" {
  description = "Cloud SQL machine tier"
  type        = string
  default     = "db-custom-2-8192"
}
