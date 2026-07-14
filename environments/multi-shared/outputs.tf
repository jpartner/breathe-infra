output "vpc_connector_id" {
  value = local.vpc_connector_id
}

output "db_instance_name" {
  value = google_sql_database_instance.main.name
}

output "db_private_ip" {
  value = google_sql_database_instance.main.private_ip_address
}

output "db_connection_name" {
  value = google_sql_database_instance.main.connection_name
}

output "cloudbuild_sa_email" {
  value = google_service_account.cloudbuild.email
}

output "zitadel_url" {
  value = "https://${var.zitadel_domain}"
}

output "platform_lb_ip" {
  value = module.platform_lb.ip_address
}
