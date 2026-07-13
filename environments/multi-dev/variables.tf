variable "project_id" {
  type    = string
  default = "breathe-dev-env"
}

variable "region" {
  type    = string
  default = "europe-west2"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "shared_project_id" {
  type    = string
  default = "breathe-shared"
}

variable "vpc_connector_id" {
  description = "VPC connector from shared project"
  type        = string
}

# Database
variable "db_name" {
  type    = string
  default = "breathe_multi_dev"
}

variable "db_user" {
  type    = string
  default = "app"
}

variable "db_connection_name" {
  description = "Cloud SQL instance connection name"
  type        = string
}

# Auth
variable "auth_issuer_url" {
  description = "Zitadel OIDC issuer URL"
  type        = string
  default     = ""
}
