# Cloud SQL PostgreSQL instance

resource "random_password" "db_password" {
  length  = 32
  special = false
}

resource "google_sql_database_instance" "main" {
  project          = var.project_id
  name             = var.instance_name
  database_version = var.database_version
  region           = var.region

  deletion_protection = var.deletion_protection

  depends_on = [var.private_vpc_connection]

  settings {
    tier              = var.tier
    availability_type = var.availability_type
    disk_size         = var.disk_size
    disk_type         = "PD_SSD"
    disk_autoresize   = true

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = var.network_id
      enable_private_path_for_google_cloud_services = true
    }

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
      start_time                     = "03:00"
      backup_retention_settings {
        retained_backups = var.backup_retention_days
        retention_unit   = "COUNT"
      }
    }

    maintenance_window {
      day          = 7 # Sunday
      hour         = 4 # 4am UTC
      update_track = "stable"
    }

    insights_config {
      query_insights_enabled  = true
      query_plans_per_minute  = 5
      query_string_length     = 1024
      record_application_tags = true
      record_client_address   = true
    }

    database_flags {
      name  = "log_statement"
      value = "ddl"
    }

    user_labels = {
      managed_by = "terraform"
    }
  }
}

# Create databases for each environment
resource "google_sql_database" "databases" {
  for_each = toset(var.databases)

  project  = var.project_id
  instance = google_sql_database_instance.main.name
  name     = each.value
  charset  = "UTF8"
}

# Main application user
resource "google_sql_user" "app_user" {
  project  = var.project_id
  instance = google_sql_database_instance.main.name
  name     = var.app_user_name
  password = random_password.db_password.result
}

# Store password in Secret Manager
resource "google_secret_manager_secret" "db_password" {
  project   = var.project_id
  secret_id = "db-password"

  replication {
    auto {}
  }

  labels = {
    managed_by = "terraform"
  }
}

resource "google_secret_manager_secret_version" "db_password" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = random_password.db_password.result
}
