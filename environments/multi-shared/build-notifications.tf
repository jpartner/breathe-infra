# =============================================================================
# Cloud Build -> Slack notifications
# =============================================================================
#
# Cloud Build publishes every build status transition in this project to the
# `cloud-builds` Pub/Sub topic. A Cloud Function subscribes and posts the
# terminal ones to Slack, so a red build is something you are told about rather
# than something you find in the console later.
#
# This covers ALL builds in breathe-shared — every app deploy trigger as well as
# the Terraform plan job — because a notifier that only watches one pipeline
# leaves the same blind spot everywhere else.
#
# The topic must exist for Cloud Build to publish to it. Cloud Build creates it
# on demand, but nothing had ever created it here, which is why no notifications
# were possible before now.

resource "google_project_service" "notifications" {
  for_each = toset([
    "cloudfunctions.googleapis.com",
    "eventarc.googleapis.com",
  ])

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_pubsub_topic" "cloud_builds" {
  project = var.project_id
  # This exact name is required — Cloud Build publishes to `cloud-builds` and
  # the name is not configurable.
  name = "cloud-builds"
}

# -----------------------------------------------------------------------------
# Function source
# -----------------------------------------------------------------------------

resource "google_storage_bucket" "function_source" {
  project                     = var.project_id
  name                        = "${var.project_id}-function-source"
  location                    = var.region
  uniform_bucket_level_access = true

  # Source archives are build inputs, not state. Old versions are replaced on
  # every deploy and are worth nothing once superseded.
  lifecycle_rule {
    condition {
      num_newer_versions = 3
    }
    action {
      type = "Delete"
    }
  }

  versioning {
    enabled = true
  }
}

data "archive_file" "build_slack_notifier" {
  type        = "zip"
  source_dir  = "${path.module}/../../functions/cloud-build-slack"
  output_path = "${path.module}/.terraform/tmp/cloud-build-slack.zip"

  # Local bytecode is not source. Without this, running python locally against
  # the function changes the archive hash and redeploys the function on the
  # next apply, for no change in behaviour.
  excludes = ["__pycache__", "*.pyc"]
}

# The hash in the object name is what makes a code change redeploy the function.
# With a static name, Terraform sees no diff and the function keeps running the
# old source.
#
# The hash is computed from the source files' CONTENT, not from the zip.
# archive_file's output_md5 covers the archive bytes, which include file
# modification times — so a fresh git checkout produces a different hash from a
# working tree with the same content, and CI and a laptop disagree forever. That
# made the plan job propose replacing this object on every run, which the
# destroy gate then failed on: a permanently red build caused entirely by the
# tooling. Content hashing is stable wherever it runs.
locals {
  notifier_source_dir = "${path.module}/../../functions/cloud-build-slack"

  notifier_source_files = sort([
    for f in fileset(local.notifier_source_dir, "**") :
    f if !startswith(f, "__pycache__") && !endswith(f, ".pyc")
  ])

  notifier_source_hash = substr(sha256(join("", [
    for f in local.notifier_source_files :
    "${f}:${filesha256("${local.notifier_source_dir}/${f}")}"
  ])), 0, 32)
}

resource "google_storage_bucket_object" "build_slack_notifier" {
  name   = "cloud-build-slack-${local.notifier_source_hash}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.build_slack_notifier.output_path
}

# -----------------------------------------------------------------------------
# Runtime identity
# -----------------------------------------------------------------------------

resource "google_service_account" "build_notifier" {
  project      = var.project_id
  account_id   = "sa-build-notifier"
  display_name = "Cloud Build Slack notifier"
  description  = "Reads build events from Pub/Sub and posts them to Slack."
}

resource "google_secret_manager_secret_iam_member" "build_notifier_slack_token" {
  project   = var.project_id
  secret_id = "slack-bot-token"
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.build_notifier.email}"
}

resource "google_project_iam_member" "build_notifier_invoker" {
  project = var.project_id
  role    = "roles/run.invoker"
  member  = "serviceAccount:${google_service_account.build_notifier.email}"
}

resource "google_project_iam_member" "build_notifier_event_receiver" {
  project = var.project_id
  role    = "roles/eventarc.eventReceiver"
  member  = "serviceAccount:${google_service_account.build_notifier.email}"
}

# -----------------------------------------------------------------------------
# The function
# -----------------------------------------------------------------------------

resource "google_cloudfunctions2_function" "build_slack_notifier" {
  project  = var.project_id
  name     = "cloud-build-slack-notifier"
  location = var.region

  build_config {
    runtime     = "python312"
    entry_point = "notify"

    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.build_slack_notifier.name
      }
    }
  }

  service_config {
    # Notifications are tiny and bursty. One instance is plenty, and capping it
    # means a storm of builds cannot fan out into a storm of containers.
    max_instance_count    = 3
    available_memory      = "256M"
    timeout_seconds       = 60
    service_account_email = google_service_account.build_notifier.email

    environment_variables = {
      SLACK_CHANNEL = var.slack_build_channel
    }

    secret_environment_variables {
      key        = "SLACK_BOT_TOKEN"
      project_id = var.project_id
      secret     = "slack-bot-token"
      version    = "latest"
    }
  }

  event_trigger {
    trigger_region        = var.region
    event_type            = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic          = google_pubsub_topic.cloud_builds.id
    service_account_email = google_service_account.build_notifier.email
    # A build result that cannot be delivered is not worth retrying forever —
    # the build history remains the source of truth.
    retry_policy = "RETRY_POLICY_DO_NOT_RETRY"
  }

  depends_on = [
    google_project_service.notifications,
    google_secret_manager_secret_iam_member.build_notifier_slack_token,
  ]
}
