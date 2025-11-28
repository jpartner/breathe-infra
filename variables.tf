# Organisation and billing
variable "org_id" {
  description = "GCP Organisation ID (optional, for folder structure)"
  type        = string
  default     = ""
}

variable "billing_account" {
  description = "Billing account ID for new projects"
  type        = string
}

# Naming
variable "project_prefix" {
  description = "Prefix for all project names"
  type        = string
  default     = "breathe"
}

# Region configuration
variable "region" {
  description = "Primary GCP region"
  type        = string
  default     = "europe-west2"
}

variable "zone" {
  description = "Primary GCP zone"
  type        = string
  default     = "europe-west2-c"
}

# Environment list
variable "environments" {
  description = "List of environments to create"
  type        = list(string)
  default     = ["dev", "staging", "production"]
}
