billing_account = "0154B9-FB54B7-DB5B17"

# Database configuration - start small for dev, can scale later
db_tier              = "db-custom-2-8192"
db_availability_type = "ZONAL"

# Environment project numbers for Artifact Registry access
# Cloud Run service agents need read access to pull images
environment_project_numbers = [
  "815682864674",   # breathe-dev-env
  "400245265670",   # breathe-staging-env
  "375280996820",   # breathe-production-env
]

# Default compute service account for dev environment (used by Cloud Run Jobs)
dev_compute_service_account = "815682864674-compute@developer.gserviceaccount.com"
