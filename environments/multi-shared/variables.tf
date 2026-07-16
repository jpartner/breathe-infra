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

# Database
variable "db_tier" {
  description = "Cloud SQL machine tier"
  type        = string
  default     = "db-custom-2-8192"
}
