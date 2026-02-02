billing_account = "0154B9-FB54B7-DB5B17"

# Bucket names for production environment
shared_generated_data_bucket = "breathe-production-generated-product-data"
shared_images_bucket         = "breathe-production-product-images"

# Database configuration (from shared project)
db_private_ip      = "10.219.0.3"
db_connection_name = "breathe-shared:europe-west2:breathe-db"

# VPC configuration
vpc_connector_id = "projects/breathe-shared/locations/europe-west2/connectors/breathe-vpc-connector"

# Service URLs
customer_frontend_url = "https://breathebranding.co.uk"

# Container image tags - use same version as dev initially
ecommerce_image_tag      = "6205fe59c43bf021322016302e5351a0e656b3ff"
feed_processor_image_tag = "6205fe59c43bf021322016302e5351a0e656b3ff"
