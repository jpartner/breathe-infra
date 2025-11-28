variable "project_id" {
  description = "Project ID for Cloud SQL"
  type        = string
}

variable "region" {
  description = "Region for the instance"
  type        = string
}

variable "instance_name" {
  description = "Name of the Cloud SQL instance"
  type        = string
  default     = "breathe-db"
}

variable "database_version" {
  description = "PostgreSQL version"
  type        = string
  default     = "POSTGRES_16"
}

variable "tier" {
  description = "Machine tier"
  type        = string
  default     = "db-custom-2-8192" # 2 vCPU, 8GB RAM
}

variable "availability_type" {
  description = "Availability type (REGIONAL for HA, ZONAL for single zone)"
  type        = string
  default     = "ZONAL"
}

variable "disk_size" {
  description = "Initial disk size in GB"
  type        = number
  default     = 20
}

variable "deletion_protection" {
  description = "Prevent accidental deletion"
  type        = bool
  default     = true
}

variable "backup_retention_days" {
  description = "Number of backups to retain"
  type        = number
  default     = 30
}

variable "network_id" {
  description = "VPC network ID for private IP"
  type        = string
}

variable "private_vpc_connection" {
  description = "Private VPC connection dependency"
  type        = string
}

variable "databases" {
  description = "List of databases to create"
  type        = list(string)
  default     = ["breathe_dev", "breathe_staging", "breathe_prod"]
}

variable "app_user_name" {
  description = "Application database user name"
  type        = string
  default     = "breathe_app"
}
