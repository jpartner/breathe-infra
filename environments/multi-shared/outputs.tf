output "vpc_connector_id" {
  value = module.networking.vpc_connector_id
}

output "cloudbuild_sa_email" {
  value = google_service_account.cloudbuild.email
}

output "zitadel_url" {
  value = module.zitadel.service_url
}
