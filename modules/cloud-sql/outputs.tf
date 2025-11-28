output "instance_name" {
  description = "The Cloud SQL instance name"
  value       = google_sql_database_instance.main.name
}

output "instance_connection_name" {
  description = "The connection name for Cloud SQL Proxy"
  value       = google_sql_database_instance.main.connection_name
}

output "private_ip_address" {
  description = "The private IP address of the instance"
  value       = google_sql_database_instance.main.private_ip_address
}

output "database_names" {
  description = "List of created database names"
  value       = [for db in google_sql_database.databases : db.name]
}

output "app_user_name" {
  description = "The application database user name"
  value       = google_sql_user.app_user.name
}

output "password_secret_id" {
  description = "Secret Manager secret ID for the database password"
  value       = google_secret_manager_secret.db_password.secret_id
}
