variable "project_id" {
  description = "GCP project ID for shared resources"
  type        = string
  default     = "breathe-shared"
}

variable "region" {
  description = "Primary GCP region"
  type        = string
  default     = "europe-west2"
}

variable "github_owner" {
  description = "GitHub repository owner"
  type        = string
  default     = "jpartner"
}

variable "environment_project_ids" {
  description = "List of environment project IDs that need access to shared resources"
  type        = list(string)
  default     = ["breathe-dev-env", "breathe-staging-env", "breathe-production-env"]
}

# Zitadel
variable "zitadel_domain" {
  description = "Domain for Zitadel auth server"
  type        = string
  default     = "auth.breathebranding.co.uk"
}

variable "unifeed_zitadel_domain" {
  description = "Domain for Unifeed Zitadel auth server"
  type        = string
  default     = "auth.unifeed.io"
}

variable "unifeed_zitadel_key_path" {
  description = "Path to Unifeed Zitadel service account JSON key"
  type        = string
  default     = null
}

variable "unifeed_zitadel_manage_config" {
  description = "Whether to manage Unifeed Zitadel orgs/projects/apps"
  type        = bool
  # Defaults to true because these resources exist and are managed: state holds
  # 75 of them, including production orgs/projects/OIDC apps and the e2e machine
  # users and PATs. With a false default, an apply that forgot to pass this flag
  # planned to destroy every one of them. Set false explicitly only when
  # bootstrapping an environment whose Zitadel does not exist yet.
  # See docs/zitadel-and-terraform-variables.md
  default = true
}

variable "unifeed_cloudflare_zone_id" {
  description = "Cloudflare zone ID for unifeed.io"
  type        = string
  default     = "5f93decf4a452ae42913b147b4f6ed74"
}

variable "unifeed_cloudflare_api_token" {
  description = "Cloudflare API token for unifeed.io DNS management"
  type        = string
  sensitive   = true
  default     = null
}

variable "zitadel_service_account_key_path" {
  description = "Path to Zitadel service account JSON key (for Terraform provider auth)"
  type        = string
  default     = ""
}

variable "zitadel_manage_config" {
  description = "Whether to manage Zitadel orgs/projects/apps (requires Zitadel running + service user key)"
  type        = bool
  default     = false
}

variable "zitadel_smtp_sender" {
  description = "Sender email address for Zitadel auth emails"
  type        = string
  default     = "hello@breathebranding.co.uk"
}

variable "zitadel_smtp_password" {
  description = "Postmark Server API token for SMTP auth"
  type        = string
  sensitive   = true
  default     = ""
}

# Zitadel default org (ZITADEL org, used for platform-level resources)
variable "zitadel_default_org_id" {
  description = "Default Zitadel organization ID for platform resources"
  type        = string
  default     = "381719479391980205"
}

# Google OAuth (for Zitadel Google IdP)
variable "google_oauth_client_id" {
  description = "Google OAuth client ID for Zitadel Google login"
  type        = string
  default     = "869820587346-cud6q2doompdsdif7ckvm40rkreu512a.apps.googleusercontent.com"
}

variable "google_oauth_client_secret" {
  description = "Google OAuth client secret"
  type        = string
  sensitive   = true
  default     = ""
}

# Test user PATs (for authenticated API tests in test runner)
variable "test_admin_pat" {
  description = "PAT for e2e-test-admin machine user"
  type        = string
  sensitive   = true
  default     = ""
}

variable "test_customer_pat" {
  description = "PAT for e2e-test-customer machine user"
  type        = string
  sensitive   = true
  default     = ""
}

variable "test_norole_pat" {
  description = "PAT for e2e-test-norole machine user"
  type        = string
  sensitive   = true
  default     = ""
}

# Unifeed test users
variable "unifeed_test_user_password" {
  description = "Password for the e2e-test-login human user in Unifeed Zitadel"
  type        = string
  sensitive   = true
  default     = "E2eTest!Unifeed2026"
}

# Cloudflare
variable "cloudflare_api_token" {
  description = "Cloudflare API token with Zone:DNS:Edit for breathebranding.co.uk"
  type        = string
  sensitive   = true
  default     = null
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID for breathebranding.co.uk"
  type        = string
  default     = "4dc7218313de868751814ec5055e7fd7"
}

# Database
variable "db_tier" {
  description = "Cloud SQL machine tier"
  type        = string
  default     = "db-custom-2-8192"
}

variable "slack_build_channel" {
  description = "Slack channel ID for Cloud Build notifications"
  type        = string
  default     = "C0BPQ4R7HC6"
}

# PA legacy lookup — the live Breathe system it reads from. Not per-environment:
# there is one legacy database and one service in front of it.
variable "breathe_live_project_id" {
  description = "Legacy Breathe project holding the live Cloud SQL instance"
  type        = string
  default     = "breathe-dev"
}

variable "breathe_sql_connection_name" {
  description = "Cloud SQL connection name for the live Breathe Postgres"
  type        = string
  default     = "breathe-dev:europe-west2:breathe-branding"
}
