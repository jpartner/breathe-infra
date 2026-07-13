output "project_id" {
  description = "The staging project ID"
  value       = module.project.project_id
}

output "project_number" {
  description = "The staging project number"
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
