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

# Database configuration (non-secret)
variable "db_private_ip" {
  description = "Cloud SQL private IP address"
  type        = string
}

variable "db_connection_name" {
  description = "Cloud SQL connection name"
  type        = string
}

variable "db_user" {
  description = "Database user name"
  type        = string
  default     = "breathe_app"
}

variable "db_name" {
  description = "Database name (defaults to breathe_{environment})"
  type        = string
  default     = ""
}

# VPC configuration
variable "vpc_connector_id" {
  description = "Full VPC connector ID (projects/PROJECT/locations/REGION/connectors/NAME)"
  type        = string
}

# Service URLs
variable "customer_frontend_url" {
  description = "Customer frontend URL"
  type        = string
}

variable "typesense_host" {
  description = "Typesense host URL"
  type        = string
  default     = ""
}

variable "ecommerce_url" {
  description = "Ecommerce service URL"
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

# Slack notification configuration
variable "slack_bot_token_secret_id" {
  description = "Secret Manager secret ID for Slack bot token"
  type        = string
  default     = "slack-bot-token"
}

variable "slack_notification_channel_id" {
  description = "Slack channel ID for deployment notifications"
  type        = string
  default     = "C03HS8FEU4Q"  # deployments channel
}
