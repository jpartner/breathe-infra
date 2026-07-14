output "ip_address" {
  value = google_compute_global_address.platform.address
}

output "domains" {
  value = var.domains
}

output "certificate_domains" {
  value = var.domains
}
