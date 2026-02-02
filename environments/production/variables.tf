variable "project_id" {
  description = "Project ID for the production environment"
  type        = string
  default     = "breathe-production-env"
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
}

variable "shared_images_bucket" {
  description = "Name of shared images bucket"
  type        = string
}

variable "db_password_secret_id" {
  description = "Secret ID for database password in shared project"
  type        = string
  default     = "db-password"
}

# Database configuration
variable "db_private_ip" {
  description = "Cloud SQL private IP address"
  type        = string
}

variable "db_connection_name" {
  description = "Cloud SQL connection name"
  type        = string
}

variable "db_user" {
  description = "Database user"
  type        = string
  default     = "postgres"
}

variable "db_name" {
  description = "Database name (defaults to breathe_{environment})"
  type        = string
  default     = ""
}

# VPC configuration
variable "vpc_connector_id" {
  description = "Full VPC connector ID"
  type        = string
}

# Service URLs
variable "customer_frontend_url" {
  description = "Customer frontend URL"
  type        = string
  default     = "https://breathebranding.co.uk"
}

variable "typesense_host" {
  description = "Typesense host URL"
  type        = string
  default     = ""
}

variable "ecommerce_url" {
  description = "Ecommerce service URL (populated after deployment)"
  type        = string
  default     = ""
}

# Feature flags
variable "enable_image_cache" {
  description = "Enable image caching for feed processor"
  type        = bool
  default     = true
}

# Container image tags
variable "ecommerce_image_tag" {
  description = "Tag for the ecommerce Docker image"
  type        = string
  default     = "latest"
}

variable "feed_processor_image_tag" {
  description = "Tag for the feed processor Docker image"
  type        = string
  default     = "latest"
}

variable "admin_image_tag" {
  description = "Tag for the admin UI Docker image"
  type        = string
  default     = "latest"
}

variable "typesense_api_key" {
  description = "Typesense search API key"
  type        = string
  default     = ""
}
