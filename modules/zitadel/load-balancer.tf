# Application Load Balancer for Zitadel
# Provides custom domain support with managed TLS certificates.
# New tenant auth domains are added by extending the `domains` variable.

# Static IP for the load balancer
resource "google_compute_global_address" "zitadel" {
  project = var.project_id
  name    = "zitadel-lb-ip"
}

# Serverless NEG pointing at the Zitadel Cloud Run service
resource "google_compute_region_network_endpoint_group" "zitadel" {
  project               = var.project_id
  name                  = "zitadel-neg"
  region                = var.region
  network_endpoint_type = "SERVERLESS"

  cloud_run {
    service = google_cloud_run_v2_service.zitadel.name
  }
}

# Backend service
resource "google_compute_backend_service" "zitadel" {
  project = var.project_id
  name    = "zitadel-backend"

  protocol    = "HTTPS"
  port_name   = "https"
  timeout_sec = 300

  backend {
    group = google_compute_region_network_endpoint_group.zitadel.id
  }

  log_config {
    enable = false
  }
}

# URL map (simple — all traffic to zitadel backend)
resource "google_compute_url_map" "zitadel" {
  project         = var.project_id
  name            = "zitadel-url-map"
  default_service = google_compute_backend_service.zitadel.id
}

# Managed SSL certificates — one per domain
resource "google_compute_managed_ssl_certificate" "zitadel" {
  for_each = toset(var.domains)

  project = var.project_id
  name    = "zitadel-cert-${replace(each.value, ".", "-")}"

  managed {
    domains = [each.value]
  }
}

# HTTPS proxy
resource "google_compute_target_https_proxy" "zitadel" {
  project = var.project_id
  name    = "zitadel-https-proxy"
  url_map = google_compute_url_map.zitadel.id

  ssl_certificates = [for cert in google_compute_managed_ssl_certificate.zitadel : cert.id]
}

# HTTPS forwarding rule
resource "google_compute_global_forwarding_rule" "zitadel_https" {
  project    = var.project_id
  name       = "zitadel-https"
  target     = google_compute_target_https_proxy.zitadel.id
  port_range = "443"
  ip_address = google_compute_global_address.zitadel.address

  labels = {
    service    = "zitadel"
    managed_by = "terraform"
  }
}

# HTTP to HTTPS redirect
resource "google_compute_url_map" "zitadel_redirect" {
  project = var.project_id
  name    = "zitadel-http-redirect"

  default_url_redirect {
    https_redirect = true
    strip_query    = false
  }
}

resource "google_compute_target_http_proxy" "zitadel_redirect" {
  project = var.project_id
  name    = "zitadel-http-proxy"
  url_map = google_compute_url_map.zitadel_redirect.id
}

resource "google_compute_global_forwarding_rule" "zitadel_http" {
  project    = var.project_id
  name       = "zitadel-http"
  target     = google_compute_target_http_proxy.zitadel_redirect.id
  port_range = "80"
  ip_address = google_compute_global_address.zitadel.address
}
