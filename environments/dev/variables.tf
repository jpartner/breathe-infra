variable "project_id" {
  description = "Project ID for the dev environment"
  type        = string
  default     = "breathe-dev-env"
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

# Shared project references
variable "shared_project_id" {
  description = "Shared project ID"
  type        = string
  default     = "breathe-shared"
}

variable "shared_feeds_bucket" {
  description = "Name of shared feeds bucket"
  type        = string
  default     = "breathe-pf-feeds"
}

variable "shared_generated_data_bucket" {
  description = "Name of shared generated data bucket"
  type        = string
  default     = "breathe-generated-product-data"
}

variable "shared_images_bucket" {
  description = "Name of shared images bucket"
  type        = string
  default     = "breathe-product-images"
}

variable "db_password_secret_id" {
  description = "Secret ID for database password in shared project"
  type        = string
  default     = "db-password"
}
