output "service_accounts" {
  description = "Map of service account emails"
  value = {
    ecommerce      = google_service_account.ecommerce.email
    nginx          = google_service_account.nginx.email
    admin          = google_service_account.admin.email
    feed_processor = google_service_account.feed_processor.email
    scheduler      = google_service_account.scheduler.email
  }
}

output "buckets" {
  description = "Map of bucket names"
  value = {
    artwork_uploaded  = google_storage_bucket.artwork_uploaded.name
    artwork_processed = google_storage_bucket.artwork_processed.name
    basket_storage    = google_storage_bucket.basket_storage.name
    cost_pricing      = google_storage_bucket.cost_pricing.name
  }
}
