# Artifact Registry repositories for container images

resource "google_artifact_registry_repository" "docker" {
  for_each = toset(var.repositories)

  project       = var.project_id
  location      = var.region
  repository_id = each.value
  format        = "DOCKER"
  description   = "Docker images for ${each.value}"

  labels = {
    managed_by = "terraform"
  }

  cleanup_policies {
    id     = "keep-recent-versions"
    action = "KEEP"

    most_recent_versions {
      keep_count = var.keep_count
    }
  }

  cleanup_policies {
    id     = "delete-old-untagged"
    action = "DELETE"

    condition {
      tag_state  = "UNTAGGED"
      older_than = "${var.untagged_retention_days * 24 * 60 * 60}s"
    }
  }
}

# Grant read access to environment projects
resource "google_artifact_registry_repository_iam_member" "env_readers" {
  for_each = {
    for pair in setproduct(toset(var.repositories), toset(var.reader_projects)) :
    "${pair[0]}-${pair[1]}" => {
      repository = pair[0]
      project    = pair[1]
    }
  }

  project    = var.project_id
  location   = var.region
  repository = google_artifact_registry_repository.docker[each.value.repository].repository_id
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:service-${each.value.project}@serverless-robot-prod.iam.gserviceaccount.com"
}
