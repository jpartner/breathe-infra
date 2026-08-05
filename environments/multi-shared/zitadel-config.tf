# Old Breathe Zitadel provider — kept for state cleanup only.
# Will be removed once all old Zitadel resources are fully destroyed.

provider "zitadel" {
  domain           = var.zitadel_domain
  port             = "443"
  insecure         = false
  jwt_profile_file = var.zitadel_service_account_key_path
}
