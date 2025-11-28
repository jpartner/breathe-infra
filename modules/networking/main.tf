# VPC Network for Breathe infrastructure
# Shared VPC allows Cloud SQL private IP access from all environments

resource "google_compute_network" "vpc" {
  project                 = var.project_id
  name                    = var.network_name
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

# Subnet for Cloud Run VPC connectors
resource "google_compute_subnetwork" "serverless" {
  project       = var.project_id
  name          = "${var.network_name}-serverless"
  ip_cidr_range = var.serverless_cidr
  region        = var.region
  network       = google_compute_network.vpc.id

  private_ip_google_access = true
}

# Subnet for Cloud SQL
resource "google_compute_subnetwork" "database" {
  project       = var.project_id
  name          = "${var.network_name}-database"
  ip_cidr_range = var.database_cidr
  region        = var.region
  network       = google_compute_network.vpc.id

  private_ip_google_access = true
}

# Private IP range for Cloud SQL
resource "google_compute_global_address" "private_ip_range" {
  project       = var.project_id
  name          = "${var.network_name}-private-ip-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.vpc.id
}

# Private connection for Cloud SQL
resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_range.name]
}

# Firewall rule to allow internal traffic
resource "google_compute_firewall" "allow_internal" {
  project = var.project_id
  name    = "${var.network_name}-allow-internal"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = [var.serverless_cidr, var.database_cidr]
}

# VPC Connector for Cloud Run (in shared project)
resource "google_vpc_access_connector" "connector" {
  project = var.project_id
  name    = "${var.network_name}-connector"
  region  = var.region

  subnet {
    name = google_compute_subnetwork.serverless.name
  }

  min_instances = 2
  max_instances = 3
}
