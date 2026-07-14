output "ip_address" {
  value = google_compute_global_address.platform.address
}

output "domains" {
  value = var.domains
}

output "certificate_statuses" {
  value = { for domain, cert in google_compute_managed_ssl_certificate.certs : domain => cert.managed[0].status }
}
