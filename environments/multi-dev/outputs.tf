output "unifeed_backend_url" {
  value = google_cloud_run_v2_service.unifeed_backend.uri
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

output "lb_ip" {
  value = module.dev_lb.ip_address
}
