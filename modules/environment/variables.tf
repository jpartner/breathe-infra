variable "project_id" {
  description = "Environment project ID"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, production)"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
}

variable "shared_project_id" {
  description = "Shared project ID for cross-project access"
  type        = string
}

variable "shared_feeds_bucket" {
  description = "Name of shared feeds bucket"
  type        = string
}

variable "shared_generated_data_bucket" {
  description = "Name of shared generated data bucket"
  type        = string
}

variable "shared_images_bucket" {
  description = "Name of shared images bucket"
  type        = string
}

variable "db_password_secret_id" {
  description = "Secret ID for database password in shared project"
  type        = string
}
