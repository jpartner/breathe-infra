# Shared Project Infrastructure
# Contains: Artifact Registry, Cloud SQL, shared GCS buckets, networking

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }

  # Uncomment and configure for remote state
  # backend "gcs" {
  #   bucket = "breathe-terraform-state"
  #   prefix = "shared"
  # }
}

provider "google" {
  region = var.region
}

provider "google-beta" {
  region = var.region
}

# Create the shared project
module "project" {
  source = "../../modules/project"

  project_name    = "Breathe Shared"
  project_id      = var.project_id
  billing_account = var.billing_account
  org_id          = var.org_id
  environment     = "shared"

  apis = [
    "cloudresourcemanager.googleapis.com",
    "serviceusage.googleapis.com",
    "iam.googleapis.com",
    "compute.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
    "run.googleapis.com",
    "sqladmin.googleapis.com",
    "sql-component.googleapis.com",
    "servicenetworking.googleapis.com",
    "secretmanager.googleapis.com",
    "vpcaccess.googleapis.com",
    "storage.googleapis.com",
  ]
}

# Networking
module "networking" {
  source = "../../modules/networking"

  project_id = module.project.project_id
  region     = var.region

  depends_on = [module.project]
}

# Artifact Registry
module "artifact_registry" {
  source = "../../modules/artifact-registry"

  project_id = module.project.project_id
  region     = var.region

  repositories = [
    "breathe-ecommerce",
    "breathe-pf-feed-processor",
    "breathe-nginx",
    "breathe-admin",
    "breathe-pricing-rust",
    "breathe-feed-puller",
  ]

  # Will be populated with environment project numbers after they're created
  reader_projects = var.environment_project_numbers

  depends_on = [module.project]
}

# Cloud SQL
module "cloud_sql" {
  source = "../../modules/cloud-sql"

  project_id             = module.project.project_id
  region                 = var.region
  network_id             = module.networking.network_id
  private_vpc_connection = module.networking.private_vpc_connection

  instance_name       = "breathe-db"
  tier                = var.db_tier
  availability_type   = var.db_availability_type
  deletion_protection = var.environment == "production"

  databases = ["breathe_dev", "breathe_staging", "breathe_prod"]

  depends_on = [module.networking]
}

# Shared GCS buckets
resource "google_storage_bucket" "feeds" {
  project                     = module.project.project_id
  name                        = "breathe-pf-feeds"
  location                    = var.region
  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      num_newer_versions = 5
    }
    action {
      type = "Delete"
    }
  }

  labels = {
    purpose    = "supplier-feeds"
    managed_by = "terraform"
  }

  depends_on = [module.project]
}

resource "google_storage_bucket" "generated_data" {
  project                     = module.project.project_id
  name                        = "breathe-generated-product-data"
  location                    = var.region
  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      num_newer_versions = 3
    }
    action {
      type = "Delete"
    }
  }

  labels = {
    purpose    = "generated-product-data"
    managed_by = "terraform"
  }

  depends_on = [module.project]
}

resource "google_storage_bucket" "images" {
  project                     = module.project.project_id
  name                        = "breathe-product-images"
  location                    = var.region
  uniform_bucket_level_access = true

  labels = {
    purpose    = "product-images"
    managed_by = "terraform"
  }

  depends_on = [module.project]
}

resource "google_storage_bucket" "build_cache" {
  project                     = module.project.project_id
  name                        = "breathe-build-cache"
  location                    = var.region
  uniform_bucket_level_access = true

  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }

  labels = {
    purpose    = "build-cache"
    managed_by = "terraform"
  }

  depends_on = [module.project]
}
