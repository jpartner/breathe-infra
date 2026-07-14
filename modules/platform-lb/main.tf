# Platform Load Balancer
# Single Application Load Balancer serving all services across all environments.
# Host-based routing directs traffic to the correct Cloud Run service.
#
# Adding a new service or tenant domain:
#   1. Add a backend entry to `backends` variable
#   2. Add host rules to `host_rules` variable
#   3. Add domain to `domains` variable (for SSL cert)

# Static IP
resource "google_compute_global_address" "platform" {
  project = var.project_id
  name    = "platform-lb-ip"
}

# Serverless NEGs — one per Cloud Run service
resource "google_compute_region_network_endpoint_group" "backends" {
  for_each = var.backends

  project               = var.project_id
  name                  = "neg-${each.key}"
  region                = each.value.region
  network_endpoint_type = "SERVERLESS"

  cloud_run {
    service = each.value.cloud_run_service
  }
}

# Backend services — one per NEG
resource "google_compute_backend_service" "backends" {
  for_each = var.backends

  project = var.project_id
  name    = "backend-${each.key}"

  protocol    = "HTTP"
  timeout_sec = each.value.timeout_sec

  backend {
    group = google_compute_region_network_endpoint_group.backends[each.key].id
  }

  log_config {
    enable = false
  }
}

# URL map with host-based routing
resource "google_compute_url_map" "platform" {
  project         = var.project_id
  name            = "platform-url-map"
  default_service = google_compute_backend_service.backends[var.default_backend].id

  dynamic "host_rule" {
    for_each = var.host_rules

    content {
      hosts        = host_rule.value.hosts
      path_matcher = host_rule.value.backend
    }
  }

  dynamic "path_matcher" {
    for_each = var.host_rules

    content {
      name            = path_matcher.value.backend
      default_service = google_compute_backend_service.backends[path_matcher.value.backend].id
    }
  }
}

# Managed SSL certificates — one per domain
resource "google_compute_managed_ssl_certificate" "certs" {
  for_each = toset(var.domains)

  project = var.project_id
  name    = "cert-${replace(each.value, ".", "-")}"

  managed {
    domains = [each.value]
  }
}

# HTTPS proxy
resource "google_compute_target_https_proxy" "platform" {
  project = var.project_id
  name    = "platform-https-proxy"
  url_map = google_compute_url_map.platform.id

  ssl_certificates = [for cert in google_compute_managed_ssl_certificate.certs : cert.id]
}

# HTTPS forwarding rule
resource "google_compute_global_forwarding_rule" "https" {
  project    = var.project_id
  name       = "platform-https"
  target     = google_compute_target_https_proxy.platform.id
  port_range = "443"
  ip_address = google_compute_global_address.platform.address

  labels = {
    managed_by = "terraform"
  }
}

# HTTP → HTTPS redirect
resource "google_compute_url_map" "redirect" {
  project = var.project_id
  name    = "platform-http-redirect"

  default_url_redirect {
    https_redirect         = true
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
    strip_query            = false
  }
}

resource "google_compute_target_http_proxy" "redirect" {
  project = var.project_id
  name    = "platform-http-proxy"
  url_map = google_compute_url_map.redirect.id
}

resource "google_compute_global_forwarding_rule" "http" {
  project    = var.project_id
  name       = "platform-http"
  target     = google_compute_target_http_proxy.redirect.id
  port_range = "80"
  ip_address = google_compute_global_address.platform.address
}
