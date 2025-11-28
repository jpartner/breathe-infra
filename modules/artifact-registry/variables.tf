variable "project_id" {
  description = "Project ID where repositories will be created"
  type        = string
}

variable "region" {
  description = "Region for the repositories"
  type        = string
}

variable "repositories" {
  description = "List of repository names to create"
  type        = list(string)
  default = [
    "breathe-ecommerce",
    "breathe-pf-feed-processor",
    "breathe-nginx",
    "breathe-admin",
    "breathe-pricing-rust",
    "breathe-feed-puller",
  ]
}

variable "reader_projects" {
  description = "List of project numbers that need read access"
  type        = list(string)
  default     = []
}

variable "keep_count" {
  description = "Number of recent image versions to keep"
  type        = number
  default     = 20
}

variable "untagged_retention_days" {
  description = "Days to keep untagged images"
  type        = number
  default     = 7
}
