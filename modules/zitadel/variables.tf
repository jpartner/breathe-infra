variable "project_id" {
  type = string
}

variable "region" {
  type    = string
  default = "europe-west2"
}

variable "vpc_connector_id" {
  description = "VPC connector for Cloud SQL access"
  type        = string
}

variable "db_instance_connection" {
  description = "Cloud SQL instance connection name"
  type        = string
}

variable "db_name" {
  type    = string
  default = "zitadel"
}

variable "db_user" {
  type    = string
  default = "zitadel"
}

variable "db_password_secret_id" {
  description = "Secret Manager ID for the Zitadel DB password"
  type        = string
}

variable "masterkey_secret_id" {
  description = "Secret Manager ID for the Zitadel master encryption key"
  type        = string
}

variable "domain" {
  description = "External domain for Zitadel (e.g. auth.breathebranding.co.uk)"
  type        = string
}

variable "image" {
  description = "Container image for Zitadel"
  type        = string
  default     = "ghcr.io/zitadel/zitadel:latest"
}
