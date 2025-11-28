output "repository_urls" {
  description = "Map of repository names to their URLs"
  value = {
    for name, repo in google_artifact_registry_repository.docker :
    name => "${var.region}-docker.pkg.dev/${var.project_id}/${repo.repository_id}"
  }
}

output "repository_ids" {
  description = "Map of repository names to their IDs"
  value = {
    for name, repo in google_artifact_registry_repository.docker :
    name => repo.repository_id
  }
}
