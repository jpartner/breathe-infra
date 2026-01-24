variable "project_id" {
  description = "Project ID for the shared project"
  type        = string
  default     = "breathe-shared"
}

variable "billing_account" {
  description = "Billing account ID"
  type        = string
}

variable "org_id" {
  description = "Organisation ID (optional)"
  type        = string
  default     = ""
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "europe-west2"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "shared"
}

variable "environment_project_numbers" {
  description = "List of environment project numbers for Artifact Registry access"
  type        = list(string)
  default     = []
}

variable "db_tier" {
  description = "Cloud SQL machine tier"
  type        = string
  default     = "db-custom-2-8192"
}

variable "db_availability_type" {
  description = "Cloud SQL availability type"
  type        = string
  default     = "ZONAL"
}

variable "github_owner" {
  description = "GitHub repository owner for Cloud Build triggers"
  type        = string
  default     = "jpartner"
}

# =============================================================================
# Database Schema Variables
# =============================================================================

variable "manage_db_schemas" {
  description = "Whether to manage database schemas (requires Cloud SQL Proxy running)"
  type        = bool
  default     = false
}

variable "db_host" {
  description = "Database host (localhost when using Cloud SQL Proxy)"
  type        = string
  default     = "localhost"
}

variable "db_port" {
  description = "Database port"
  type        = number
  default     = 5432
}

variable "db_admin_user" {
  description = "Database admin user for schema management"
  type        = string
  default     = "postgres"
}

variable "db_admin_password" {
  description = "Database admin password (provide via TF_VAR_db_admin_password or -var)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "db_schemas" {
  description = "List of schema names to create in each database"
  type        = list(string)
  default     = ["app"]
}
