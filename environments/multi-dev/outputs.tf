output "backend_url" {
  value = google_cloud_run_v2_service.backend.uri
}

output "product_data_bucket" {
  value = google_storage_bucket.product_data.name
}

output "raw_feeds_bucket" {
  value = google_storage_bucket.raw_feeds.name
}

output "images_bucket" {
  value = google_storage_bucket.images.name
}
