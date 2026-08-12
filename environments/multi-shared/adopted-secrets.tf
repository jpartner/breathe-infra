# =============================================================================
# Secrets created out of band, adopted into Terraform on 2026-08-12
# =============================================================================
#
# `breathe-shared` held 50 secrets; Terraform owned 22. The other 28 were made
# by hand or by a script, which meant they were invisible to `plan` and would
# survive a destroy — so nothing in this repo would ever recreate them, and
# nothing warned you of that. This file adopts 25 of them. All carry automatic
# replication, verified against the API.
#
# Only the secret *containers* are managed here. Versions are deliberately left
# out: these hold third-party and vendor credentials whose values would land in
# the state file if Terraform managed the versions too. Rotating a value stays a
# `gcloud secrets versions add` operation.
#
# Three of the 28 are deliberately not adopted:
#   - test-user-credentials    no reference anywhere in any repo
#   - goldstar-api-password    Goldstar is supplier SP016 but was never wired to
#                              a secret; every other supplier has an explicit
#                              secret_key_ref in multi-dev/main.tf
#   - zitadel-service-account-key
#                              the legacy Breathe-era key, labelled superseded;
#                              it no longer authenticates and its only consumer
#                              (a vestigial backend IAM grant) was removed in
#                              the same change. Pending deletion.
#
# See docs/zitadel-and-terraform-variables.md §7 for the full inventory and the
# command that re-derives the managed/unmanaged split.

locals {
  # secret_id => labels already present on the live secret. Labels must be
  # declared to match, or the first apply plans to strip them.
  adopted_secrets = {
    "anthropic-api-key"            = {}
    "bic-graphic-client-secret"    = {}
    "bic-graphic-password"         = {}
    "breathe-legacy-db-password"   = {}
    "cloudflare-api-token"         = {}
    "crystal-galleries-api-key"    = {}
    "db-password"                  = { managed_by = "terraform" }
    "github-ssh-key"               = {}
    "impression-europe-password"   = {}
    "keramikos-password"           = {}
    "laltex-api-key"               = {}
    "midocean-api-key"             = {}
    "outdoors-company-user-token"  = {}
    "pinpoint-api-key"             = {}
    "preseli-secret-key"           = {}
    "slack-bot-token"              = {}
    "typesense-api-key"            = {}
    "umbrella-api-key"             = {}
    "unifeed-cloudflare-api-token" = {}
    "usbgroup-api-key"             = {}
    "VECTORIZER_API_ID"            = {}
    "VECTORIZER_API_SECRET"        = {}
    "worker-api-key"               = {}
    "xoopar-password"              = {}
    "unifeed-zitadel-terraform-key" = {
      instance = "unifeed"
      owner    = "terraform"
      purpose  = "zitadel-provider-key"
    }
  }
}

resource "google_secret_manager_secret" "adopted" {
  for_each = local.adopted_secrets

  project   = var.project_id
  secret_id = each.key
  labels    = each.value

  replication {
    auto {}
  }

  # Terraform manages the container but not the value, so a destroy here loses
  # a credential nothing in this repo can reissue — supplier API keys come from
  # third parties and the Zitadel provider key is what Terraform authenticates
  # with. Removing one is meant to be a deliberate edit, not something a
  # mistyped variable can reach (see §1 of the doc for how that happened once).
  lifecycle {
    prevent_destroy = true
  }
}

# One-time adoption. Remove these blocks once the apply has landed, matching how
# previous imports in this repo were retired.
import {
  for_each = local.adopted_secrets

  to = google_secret_manager_secret.adopted[each.key]
  id = "projects/${var.project_id}/secrets/${each.key}"
}
