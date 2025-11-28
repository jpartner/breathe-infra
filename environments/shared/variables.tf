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
