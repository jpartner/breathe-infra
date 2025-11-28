output "network_id" {
  description = "The VPC network ID"
  value       = google_compute_network.vpc.id
}

output "network_name" {
  description = "The VPC network name"
  value       = google_compute_network.vpc.name
}

output "network_self_link" {
  description = "The VPC network self link"
  value       = google_compute_network.vpc.self_link
}

output "serverless_subnet_id" {
  description = "The serverless subnet ID"
  value       = google_compute_subnetwork.serverless.id
}

output "database_subnet_id" {
  description = "The database subnet ID"
  value       = google_compute_subnetwork.database.id
}

output "vpc_connector_id" {
  description = "The VPC connector ID"
  value       = google_vpc_access_connector.connector.id
}

output "vpc_connector_name" {
  description = "The VPC connector name for Cloud Run"
  value       = google_vpc_access_connector.connector.name
}

output "private_vpc_connection" {
  description = "The private VPC connection for Cloud SQL"
  value       = google_service_networking_connection.private_vpc_connection.id
}
