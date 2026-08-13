# =============================================================================
# OIDC client IDs, read from multi-shared instead of pasted in by hand
# =============================================================================
#
# multi-shared creates the Zitadel OIDC applications; this environment consumes
# their client IDs. That used to require a manual step between the two applies:
# run `terraform output -json` against multi-shared, then edit the *defaults* of
# six variables in variables.tf. It was documented (§6) and it worked, but it
# meant a rebuild edited tracked source in the middle of a deploy — so the act
# of deploying left the working tree dirty, and getting it wrong produced a
# login failure rather than a Terraform error.
#
# Reading multi-shared's outputs directly makes it an ordinary dependency. The
# variables survive as an override for the rare case where you need to pin an
# ID by hand; left null, the value comes from the other state.
#
# Requires read access to the multi-shared state prefix. Operators have it; CI
# has it through sa-terraform-plan's objectViewer grant on the bucket.

data "terraform_remote_state" "shared" {
  backend = "gcs"

  config = {
    bucket = "breathe-terraform-state"
    prefix = "multi-shared"
  }
}

locals {
  # Both outputs are maps keyed "<zitadel-tenant>-<env>". Note the tenant key
  # for the Uniten deployment is `unifeed`, not `uniten` — see §4 of the Zitadel
  # doc. Deriving it from the deployment slug yields a key that does not exist,
  # and the resulting failure looks like a Zitadel bug rather than a name
  # mismatch, so the mapping is written out explicitly here.
  shared_customer_client_ids = data.terraform_remote_state.shared.outputs.unifeed_customer_client_ids
  shared_admin_client_ids    = data.terraform_remote_state.shared.outputs.unifeed_admin_client_ids

  # Storefront (customer-facing) OIDC clients, keyed by storefront name.
  storefront_client_ids = {
    breathe = coalesce(var.storefront_breathe_client_id, local.shared_customer_client_ids["breathe-dev"])
    pa      = coalesce(var.storefront_pa_client_id, local.shared_customer_client_ids["pa-dev"])
    uniten  = coalesce(var.storefront_uniten_client_id, local.shared_customer_client_ids["unifeed-dev"])
  }

  # Zitadel admin UI OIDC clients, keyed by admin deployment slug.
  admin_client_ids = {
    breathe = coalesce(var.admin_breathe_client_id, local.shared_admin_client_ids["breathe-dev"])
    pa      = coalesce(var.admin_pa_client_id, local.shared_admin_client_ids["pa-dev"])
    uniten  = coalesce(var.admin_uniten_client_id, local.shared_admin_client_ids["unifeed-dev"])
  }
}

# If multi-shared was last applied with unifeed_zitadel_manage_config = false,
# both outputs are empty maps and the lookups above fail on a missing key. That
# is the right outcome — the applications genuinely do not exist — but the raw
# error is unhelpful, so say what it means.
check "shared_outputs_present" {
  assert {
    condition     = length(local.shared_customer_client_ids) > 0 && length(local.shared_admin_client_ids) > 0
    error_message = "multi-shared exported no OIDC client IDs. It was last applied with unifeed_zitadel_manage_config = false; re-apply it with the flag set (see docs §1) before applying multi-dev."
  }
}
