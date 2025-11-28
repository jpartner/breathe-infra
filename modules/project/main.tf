# Creates a GCP project with required APIs enabled

resource "google_project" "project" {
  name            = var.project_name
  project_id      = var.project_id
  billing_account = var.billing_account
  org_id          = var.org_id != "" ? var.org_id : null
  folder_id       = var.folder_id != "" ? var.folder_id : null

  labels = merge(
    {
      environment = var.environment
      managed_by  = "terraform"
    },
    var.labels
  )
}

# Enable required APIs
resource "google_project_service" "apis" {
  for_each = toset(var.apis)

  project = google_project.project.project_id
  service = each.value

  disable_dependent_services = false
  disable_on_destroy         = false
}

# Wait for APIs to be enabled before other resources can be created
resource "time_sleep" "api_propagation" {
  depends_on = [google_project_service.apis]

  create_duration = "60s"
}
