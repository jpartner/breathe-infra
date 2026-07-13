output "project_id" {
  description = "The dev project ID"
  value       = module.project.project_id
}

output "project_number" {
  description = "The dev project number"
  value       = module.project.project_number
}

output "service_accounts" {
  description = "Service account emails"
  value       = module.environment.service_accounts
}

output "buckets" {
  description = "Environment bucket names"
  value       = module.environment.buckets
}

output "config_url" {
  description = "GCS URL to the environment configuration file"
  value       = module.environment.config_url
}

output "config_bucket" {
  description = "Name of the config bucket"
  value       = module.environment.config_bucket
}
