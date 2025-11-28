variable "project_name" {
  description = "Display name for the project"
  type        = string
}

variable "project_id" {
  description = "Unique project ID"
  type        = string
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

variable "folder_id" {
  description = "Folder ID (optional)"
  type        = string
  default     = ""
}

variable "environment" {
  description = "Environment label (shared, dev, staging, production)"
  type        = string
}

variable "labels" {
  description = "Additional labels to apply"
  type        = map(string)
  default     = {}
}

variable "apis" {
  description = "List of APIs to enable"
  type        = list(string)
  default = [
    "cloudresourcemanager.googleapis.com",
    "serviceusage.googleapis.com",
    "iam.googleapis.com",
    "compute.googleapis.com",
  ]
}
