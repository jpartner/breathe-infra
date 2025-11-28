variable "project_id" {
  description = "Project ID for the VPC"
  type        = string
}

variable "region" {
  description = "Region for regional resources"
  type        = string
}

variable "network_name" {
  description = "Name of the VPC network"
  type        = string
  default     = "breathe-vpc"
}

variable "serverless_cidr" {
  description = "CIDR range for serverless VPC connector subnet"
  type        = string
  default     = "10.8.0.0/28"
}

variable "database_cidr" {
  description = "CIDR range for database subnet"
  type        = string
  default     = "10.9.0.0/24"
}
