# SMTP for the unifeed Zitadel instance (auth.unifeed.io) via Postmark.
#
# Without this no auth email leaves the instance at all — invites, password
# resets and verification codes fail with Errors.SMTPConfig.NotFound (that is
# how it shipped; the first admin invite surfaced it, 2026-08-12).
#
# Postmark SMTP: user and password are both the Server API token. The token
# lives in the postmark-api-key secret (version 2+; version 1 was a
# placeholder), and the same token is what the Breathe backend uses for its
# transactional mail — the sender address is a verified Postmark signature.

data "google_secret_manager_secret_version" "postmark_api_key" {
  project = var.project_id
  secret  = google_secret_manager_secret.postmark_api_key.secret_id
}

resource "zitadel_smtp_config" "unifeed" {
  provider = zitadel.unifeed

  description    = "Postmark"
  host           = "smtp.postmarkapp.com:587"
  tls            = true
  user           = data.google_secret_manager_secret_version.postmark_api_key.secret_data
  password       = data.google_secret_manager_secret_version.postmark_api_key.secret_data
  sender_address = var.zitadel_smtp_sender
  sender_name    = "Unifeed"
  set_active     = true

  # Declared empty on purpose. Left undeclared, Terraform stores null while
  # Zitadel returns "", and the refresh reports the resource as drifted on every
  # single plan — state=None, live="". No one changed anything; it is a
  # null-versus-empty-string round trip. Setting it explicitly makes the two
  # agree. Give it a real address if replies should go somewhere other than
  # the sender.
  reply_to_address = ""
}
