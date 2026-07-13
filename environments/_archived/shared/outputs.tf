output "project_id" {
  description = "The shared project ID"
  value       = module.project.project_id
}

output "project_number" {
  description = "The shared project number"
  value       = module.project.project_number
}

output "artifact_registry_urls" {
  description = "Artifact Registry repository URLs"
  value       = module.artifact_registry.repository_urls
}

output "cloud_sql_connection_name" {
  description = "Cloud SQL connection name"
  value       = module.cloud_sql.instance_connection_name
}

output "cloud_sql_private_ip" {
  description = "Cloud SQL private IP"
  value       = module.cloud_sql.private_ip_address
}

output "db_password_secret_id" {
  description = "Secret ID for database password"
  value       = module.cloud_sql.password_secret_id
}

output "vpc_connector_name" {
  description = "VPC connector name for Cloud Run"
  value       = module.networking.vpc_connector_name
}

output "network_id" {
  description = "VPC network ID"
  value       = module.networking.network_id
}

output "buckets" {
  description = "Shared bucket names"
  value = {
    feeds       = google_storage_bucket.feeds.name
    build_cache = google_storage_bucket.build_cache.name
  }
}

output "environment_buckets" {
  description = "Per-environment bucket names"
  value = {
    for env, _ in local.environments : env => {
      generated_data = google_storage_bucket.generated_data[env].name
      images         = google_storage_bucket.images[env].name
    }
  }
}

output "database_schemas" {
  description = "Database schemas created in each environment database"
  value       = var.manage_db_schemas ? module.database_schemas[0].schemas : {}
}

output "database_names" {
  description = "List of database names"
  value       = module.cloud_sql.database_names
}
