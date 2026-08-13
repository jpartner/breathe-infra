# Zitadel and Terraform variables

Operational notes for `environments/multi-shared` and `environments/multi-dev`.
Everything here was verified against live state and the running Zitadel instance
on **2026-08-11**; re-check before trusting the specifics.

---

## 1. The dangerous default

`terraform.tfvars` is gitignored, and most variables already carry working
defaults, so an apply only needs three values supplied (see §8). That is fine in
itself — the hazard was narrower and sharper: two variables gate large blocks of
resources with `count = var.<flag> ? 1 : 0`, and **both defaulted to `false`**:

| Variable | Default | Resources in `multi-shared` state |
|---|---|---|
| `unifeed_zitadel_manage_config` | was `false` | **75** — every org, project, OIDC app (dev **and production**), plus the e2e machine users and their PATs |
| `zitadel_manage_config` | `false` | 0 — legacy, see §2 |

A completely bare `terraform apply` was never the danger — it fails immediately
on the required `environment_project_numbers`. The reachable path was a
*partial* invocation: supply the project numbers but not the gating flag, and
the plan succeeds and proposes **destroying all 75 Zitadel resources**,
including production orgs and the PATs the e2e suite authenticates with.
Nothing warns you; the flag simply evaluates to `false` and the resources fall
out of the configuration.

That was easy to hit because `terraform.tfvars.example` — the file everyone
copies — listed `environment_project_numbers` and never mentioned the gating
flag. Copy the example, fill it in, apply. The example now documents all three
required values and the flag.

The default has since been flipped to `true` so that the common case matches
reality: the resources exist and are managed. With no valid credentials an apply
now fails loudly at refresh instead of silently proposing destruction. Set it to
`false` explicitly only when bootstrapping an environment where Zitadel does not
yet exist.

Only **one** variable in `multi-shared` has no default at all:
`environment_project_numbers`.

## 2. Zitadel deployment and the two variable sets

Zitadel is the **`unifeed-zitadel`** Cloud Run service in `breathe-shared`, served
at **auth.unifeed.io** (the OIDC issuer it reports is `https://auth.unifeed.io`).
Breathe, PA and Unifeed are Organizations within it — `zitadel_org.tenants` in
`modules/zitadel-config`.

The config carries two similarly-named variable sets, and telling them apart
matters:

- `unifeed_zitadel_*` (`unifeed_zitadel_domain`, `unifeed_zitadel_key_path`,
  `unifeed_zitadel_manage_config`) — drives the `zitadel.unifeed` provider alias
  and the `unifeed_zitadel_config` module. This is what manages the orgs,
  projects, OIDC apps and roles described here.
- `zitadel_*` (`zitadel_domain`, `zitadel_manage_config`,
  `zitadel_service_account_key_path`, `zitadel_default_org_id`, `zitadel_smtp_*`)
  — the older set. `zitadel_manage_config` currently has no resources in
  `multi-shared` state.

`auth.breathebranding.co.uk` resolves to the platform load balancer but has no
host rule or certificate there, so it returns a Google Frontend 404 today.

## 3. Provider credentials

The provider authenticates with a JSON machine-user key:

```hcl
provider "zitadel" {
  alias            = "unifeed"
  domain           = var.unifeed_zitadel_domain      # auth.unifeed.io
  jwt_profile_file = var.unifeed_zitadel_key_path    # path to a JSON key file
}
```

`unifeed_zitadel_key_path` defaults to `""`, so the path is supplied at apply
time and the key file lives outside this repo.

**There are two machine-user keys, and only one of them works. This is the single
easiest thing to get wrong here.**

| Key | Machine user | Works against auth.unifeed.io | Notes |
|---|---|---|---|
| `~/.zitadel/unifeed-terraform-key.json` | `384306430871645708` | **yes** — token issued | The one the provider needs. Also in Secret Manager as **`unifeed-zitadel-terraform-key`**. Expires **2026-11-30** |
| `~/.zitadel/terraform-key.json` | `381750983966886573` | no — `HTTP 500 Errors.Internal` | Legacy, from the Breathe-era instance. This is what the badly-named `zitadel-service-account-key` secret contains |

Reaching for `zitadel-service-account-key` because it is the only obviously-named
secret gets you the **legacy** key, and the failure mode is misleading: Zitadel
answers a JWT-profile grant for an unknown machine user with a generic
`HTTP 500 Errors.Internal`, which reads like the server is broken rather than
like the wrong credential. Terraform surfaces the same thing as
`error while getting org by id ...: Errors.Internal` during refresh.

To use it:

```bash
gcloud secrets versions access latest --secret=unifeed-zitadel-terraform-key \
  --project=breathe-shared > ~/.zitadel/unifeed-terraform-key.json

terraform plan -var "unifeed_zitadel_key_path=$HOME/.zitadel/unifeed-terraform-key.json" ...
```

Two follow-ups worth doing:

- **The working key expires 2026-11-30.** After that, applies fail until a new key
  is created for machine user `384306430871645708` and the secret updated.
- `zitadel-service-account-key` is now labelled `status=superseded`. It is
  referenced only by `google_secret_manager_secret_iam_member.backend_zitadel_sa`
  in `environments/multi-dev/main.tf`, which grants the backend read access "for
  role lookups" — but the backend has no volume mount, no matching env var and no
  code reference for it, so that grant appears vestigial. Removing the grant and
  then deleting the secret would remove the trap entirely.

## 3a. Pre-existing drift a plan will show

A `multi-shared` plan on 2026-08-11 reported changes that belong to nobody's
current work. Expect them, and decide deliberately rather than waving them
through:

- **The three e2e PATs want replacing.** `zitadel_personal_access_token.test_*`
  shows `expiration_date = "9999-12-31T23:59:59Z" -> null # forces replacement`:
  the live tokens carry a non-null expiry that the configuration does not
  declare, so every apply wants to destroy and recreate them. That issues **new
  tokens** and writes new versions of `unifeed-test-{admin,customer,norole}-pat`.
  The e2e runner reads those secrets at `version = "latest"`, so it recovers on
  the next instance start — but any copy pasted elsewhere goes stale. Setting
  `expiration_date` explicitly on the resource (or `lifecycle { ignore_changes }`)
  would stop the churn.
- **`gcloud`-made changes get reverted.** Anything set imperatively with
  `gcloud run services update` shows up as drift and is removed on the next
  apply — e.g. an `ADMIN_URL` env var added by hand to `unifeed-test-runner`, and
  the `client`/`client_version` metadata gcloud stamps on a service. Make runtime
  config changes in Terraform, or expect to lose them.

Because of this, prefer a **targeted apply** when landing an unrelated change:

```bash
terraform apply -target='module.unifeed_zitadel_config[0].zitadel_application_oidc.admin' ...
```

## 4. Tenant key vs deployment slug

The Zitadel tenant key and the Cloud Run deployment name do not always match:

| Zitadel tenant key | Admin UI deployment | Admin hostname (dev) |
|---|---|---|
| `unifeed` | `admin-uniten` | `admin-uniten.dev.unifeed.io` |
| `breathe` | `admin-breathe` | `admin.dev.breathebranding.co.uk` — its own brand domain |
| `pa` | `admin-pa` | `admin-pa.dev.unifeed.io` |

Breathe's admin is served on its own brand domain, so no
`admin-breathe.dev.unifeed.io` record was ever created — that absence is by
design, not a gap. DNS for unifeed.io is healthy and lives in its own Cloudflare
zone (`unifeed_cloudflare_zone_id`, with its own API token), separate from the
breathebranding.co.uk and breathebranding.eu zones; each brand's hostnames are
managed in its own zone. What matters per app is that its `AUTH_URL` and its
Zitadel redirect URIs name the same host — whichever brand domain that is.

That is why `var.tenants` carries an optional `admin_slug`. Deriving the admin
hostname from the tenant key alone yields `admin-unifeed...`, which does not
exist — and the resulting failure looks like a Zitadel bug rather than a naming
mismatch.

The admin UI is deployed **per tenant**, so `admin_domain_pattern` takes a
`{tenant}` placeholder rather than a single hostname per environment. Drop the
placeholder if the admin UIs are ever consolidated onto one host.

## 5. OIDC redirect URIs must include the callback path

Apps consumed by NextAuth complete the handshake at
`/api/auth/callback/zitadel`. Registering a bare origin (`https://admin.dev.unifeed.io`)
makes Zitadel reject the callback. The customer apps already did this correctly;
the admin apps did not, and were additionally registered as
`OIDC_APP_TYPE_USER_AGENT` when they run server-side under Next.js and should be
`OIDC_APP_TYPE_WEB`, matching the customer app. Both were corrected on
2026-08-11 — the nine admin applications updated **in place**, so their client
IDs did not change.

### AUTH_URL is required on every NextAuth service

Each storefront and admin service must set `AUTH_URL` to its own public origin
(e.g. `https://admin-uniten.dev.unifeed.io`). Without it, NextAuth derives the
origin from the container's bind address and sends Zitadel
`redirect_uri=https://0.0.0.0:3000/api/auth/callback/zitadel`; the browser then
cannot load the callback and login dies on an error page **after** the password
has been accepted. `trustHost: true` alone did not cover this behind the load
balancer.

This had been broken on the customer storefronts and went unnoticed because the
e2e login test only asserted that no "Sign In" link was visible — trivially true
of a browser error page. If you add a NextAuth-based service, set `AUTH_URL` at
the same time you set `AUTH_ZITADEL_ID`.

Relatedly, middleware that builds a sign-in redirect must pass a **relative**
`callbackUrl`. `req.url` inside Next.js middleware on Cloud Run is the internal
address, so `callbackUrl=https://0.0.0.0:3000/account` sends the user nowhere
after a successful login.

Signing in to an admin UI requires the **`admin`** (or `csr`) project role on the
tenant's project for that environment; the backend enforces `hasAnyRole("ADMIN",
"CSR")` on `/api/admin/**`. A user who authenticates without a role reaches the
UI but every request 401s, which looks like a broken proxy rather than a missing
grant. Roles are granted with `zitadel_user_grant`.

## 6. Client IDs flow between the two states automatically

`multi-shared` creates the OIDC applications; `multi-dev` consumes their client
IDs. Since 2026-08-13 it reads them straight from `multi-shared`'s outputs
through a `terraform_remote_state` data source
(`environments/multi-dev/client-ids.tf`). The order is simply: apply
`multi-shared`, then apply `multi-dev`.

**This used to be a manual step and no longer is.** The six
`storefront_*_client_id` / `admin_*_client_id` variables held the real IDs in
their **defaults**, so the procedure was: apply `multi-shared`, run
`terraform output -json`, hand-edit `environments/multi-dev/variables.tf`, then
apply `multi-dev`. Forgetting the edit mattered most exactly when it was easiest
to forget — an apply that **replaces** an application rather than updating it in
place (changing `app_type` forces replacement) issues a new client ID, and a
stale one produces a login failure that looks like a misconfigured tenant rather
than a missed step.

The variables still exist, defaulting to `null`, purely so an ID can be pinned by
hand if it ever needs to be. Left alone they come from the other state, so
there is nothing to refresh after an application is replaced.

Two things worth knowing about the wiring:

- Both outputs are keyed `"<zitadel-tenant>-<env>"`, and the tenant key for the
  Uniten deployment is **`unifeed`**, not `uniten` (§4). The mapping is written
  out explicitly in `client-ids.tf` rather than derived from the slug, because
  deriving it produces a key that does not exist and a failure that reads like a
  Zitadel bug.
- If `multi-shared` was last applied with `unifeed_zitadel_manage_config = false`
  both outputs are empty maps. A `check` block catches that and says so, rather
  than failing on a missing map key.

Reading the other state needs read access to the `multi-shared` prefix in
`gs://breathe-terraform-state`. Operators have it; CI has it through
`sa-terraform-plan`'s `objectViewer` grant on the bucket.

## 7. Secret inventory — and what Terraform actually owns

`breathe-shared` holds 50 secrets and **Terraform manages all 50.** There are no
unmanaged secrets and no secrets in state that do not exist — verified
2026-08-13 with the command at the end of this section.

It was not always so. On 2026-08-12 Terraform owned 22 of 50; the other 28 had
been created with `gcloud` rather than declared, so they were invisible to
`plan` and would have survived a destroy. 25 were adopted into
`environments/multi-shared/adopted-secrets.tf` and 3 were deleted as dead.

**Keeping it at 50/50 is the point.** Creating a secret with `gcloud secrets
create` reopens the gap silently — nothing warns you, and the secret simply
never appears in a plan again. Declare new secrets in Terraform, or adopt them
in the same change.

Adopted secrets are managed as **containers only** — Terraform does not own
their versions, so the values stay out of the state file and rotation remains a
`gcloud secrets versions add`. A rebuild therefore recreates the containers
empty; that is a deliberate trade against putting supplier credentials in state.

**Terraform-managed and value-owning (22)** — an apply can create, rotate or
destroy these, and the values live in state:

| Secret | Used for |
|---|---|
| `db-admin-password`, `db-app-password` | Cloud SQL users |
| `unifeed-zitadel-masterkey`, `unifeed-zitadel-db-password` | The Zitadel deployment itself |
| `storefront-{breathe,breathe-eu,pa,uniten}-auth-secret` | NextAuth session encryption per storefront |
| `admin-{breathe,pa,uniten}-auth-secret` | NextAuth session encryption per admin UI (added alongside admin auth) |
| `ingest-zitadel-client-secret`, `ingest-auth-secret` | Ingest tool OIDC client + NextAuth secret |
| `unifeed-test-{admin,csr,customer,norole}-pat` | e2e machine-user PATs |
| `unifeed-test-admin-key` | Machine-user key prototyped to replace the admin PAT (§7a) |
| `unifeed-staff-manager-pat` | Staff management machine user |
| `unifeed-test-login-password` | e2e human login (`e2e-test@unifeed.io`) |
| `pa-migration-api-key`, `postmark-api-key` | PA migration service, transactional email |

Note the e2e PATs are generated by the Zitadel block: destroying it (see §1)
invalidates the tokens the test suite authenticates with, and new versions are
written on the next apply.

**Adopted as containers (25)** — declared in `adopted-secrets.tf`, imported
2026-08-12. Terraform now knows they exist, but does not own their values:

`worker-api-key`, `typesense-api-key`, `cloudflare-api-token`,
`unifeed-cloudflare-api-token`, `unifeed-zitadel-terraform-key`,
`github-ssh-key`, `slack-bot-token`, `anthropic-api-key`, `db-password`,
`breathe-legacy-db-password`, `VECTORIZER_API_ID`, `VECTORIZER_API_SECRET`,
and the supplier credentials (`bic-graphic-*`, `crystal-galleries-api-key`,
`impression-europe-password`, `keramikos-password`, `laltex-api-key`,
`midocean-api-key`, `outdoors-company-user-token`, `pinpoint-api-key`,
`preseli-secret-key`, `umbrella-api-key`, `usbgroup-api-key`,
`xoopar-password`).

They carry `lifecycle { prevent_destroy = true }`. Terraform cannot reissue any
of these — supplier keys come from third parties and
`unifeed-zitadel-terraform-key` is what Terraform itself authenticates with — so
removing one is meant to be a deliberate edit rather than something a mistyped
variable can reach (§1).

Two are worth attention:

- **`unifeed-zitadel-terraform-key`** is the credential Terraform needs to run at
  all (§3), and it **expires 2026-11-30**. Adoption does not change that: the
  container is managed, the key inside it is not.
- **`worker-api-key`** authenticates the GPU enrichment worker against endpoints
  that Spring Security leaves open, so it is the only thing protecting them. The
  backend now refuses worker requests outright when it is unset rather than
  falling back to a default key.

**Deleted 2026-08-13 (3)** — never adopted, because adopting a secret you intend
to delete just adds a step:

| Secret | Why it went |
|---|---|
| `test-user-credentials` | No reference in any repo — code, config or cloudbuild |
| `goldstar-api-password` | Goldstar is supplier `SP016`, but unlike every other supplier it had no `secret_key_ref` in `multi-dev/main.tf` |
| `zitadel-service-account-key` | The legacy Breathe-era key (§3), labelled `status=superseded`. It no longer authenticated, and its only consumer — a backend IAM grant that was never mounted or read — was removed in `def3558` and applied 2026-08-13 |

Deleting `zitadel-service-account-key` removes the trap described in §3: it was
the only obviously-named Zitadel secret, so reaching for it was the natural
mistake, and it failed with a generic `HTTP 500 Errors.Internal` that reads like
a broken server rather than a wrong credential.

Note on the evidence: **data-access audit logging is not enabled on this
project**, so there are no `AccessSecretVersion` records and the absence of read
logs proved nothing. The case for these being dead rested on a code search
across all repos and on their having no IAM bindings at all. If you want
deletion decisions to rest on observed access in future, data-access logs for
`secretmanager.googleapis.com` have to be turned on first.

To re-derive the managed/live split at any time:

```bash
cd environments/multi-shared
gcloud secrets list --project=breathe-shared --format="value(name)" \
  | LC_ALL=C sort > /tmp/gcp.txt
terraform state pull | python3 -c "
import json,sys
st=json.load(sys.stdin)
print('\n'.join({i['attributes']['secret_id']
     for r in st.get('resources',[]) if r.get('type')=='google_secret_manager_secret'
     for i in r.get('instances',[])}))" | LC_ALL=C sort > /tmp/tf.txt
LC_ALL=C comm -23 /tmp/gcp.txt /tmp/tf.txt   # live but unmanaged — should be empty
LC_ALL=C comm -13 /tmp/gcp.txt /tmp/tf.txt   # in state but gone — should be empty
```

`LC_ALL=C` matters: without it `comm` and `sort` disagree about case and the
comparison silently reports nonsense.

Environment projects (`breathe-dev-env` and friends) hold only
`anthropic-api-key` and `stripe-api-key`; everything else lives in
`breathe-shared`.

To re-run this comparison:

```bash
cd environments/multi-shared
gcloud secrets list --project=breathe-shared --format="value(name)" | sort > /tmp/gcp.txt
terraform state pull | python3 -c "
import json,sys
st=json.load(sys.stdin)
ids={i['attributes']['secret_id']
     for r in st.get('resources',[]) if r.get('type')=='google_secret_manager_secret'
     for i in r.get('instances',[])}
print('\n'.join(sorted(ids)))" > /tmp/tf.txt
comm -23 /tmp/gcp.txt /tmp/tf.txt   # in GCP, unmanaged
```

## 7a. Follow-up: retire the non-expiring PATs

Done on 2026-08-12: the deploy path no longer uses a PAT. Cloud Build mints a
Google-signed ID token (IAM Credentials `generateIdToken`, self-impersonation —
`sa-cloudbuild` holds `roles/iam.serviceAccountTokenCreator` on itself) and the
hub verifies email, allow-listed service account and audience. Neither
`gcloud auth print-identity-token` nor the worker metadata server can mint an
ID token on Cloud Build; both fail quietly, so don't reach for them.

Still outstanding — the test PATs themselves:

`unifeed-test-{admin,csr,customer,norole}-pat` are **opaque, non-expiring**
bearer tokens with project roles on `unifeed-dev`. Being opaque they cannot
self-expire; revoking means deleting them in Zitadel and rotating the secret.
They are handed to test runs, which produce traces, HAR files and screenshots —
exactly where bearer tokens escape, and a leak of these never ages out.

**The blocker is solved** (2026-08-12). A straight swap did not work, for a
reason worth knowing before attempting it again: Zitadel asserts project roles
under *two* different claim names. Tokens issued to an OIDC application use
`urn:zitadel:iam:org:project:roles`; a token obtained with the
`urn:zitadel:iam:org:projects:roles` scope — which is how a machine user
exchanges a key via the JWT-profile grant — gets a **project-scoped** key
instead, `urn:zitadel:iam:org:project:<projectId>:roles`. The backend read only
the generic name, so machine-key tokens authenticated and then carried no roles
at all: `/api/account/me` returned the right user with `roles: []`, and every
admin and ingest call 403'd, which reads like a broken grant rather than a
claim-name mismatch.

`JwtAuthFilter` and `JwtValidator` now accept either shape (backend 7b4ec72,
with a test). Verified against dev: the same token that returned `roles: []`
and 403 now returns `roles: ['admin']` and 200 on admin, ingest and catalogue.

A prototype key exists — `zitadel_machine_key.test_admin`, stored as
`unifeed-test-admin-key` — and the exchange looks like this (note the scope;
without it there are no roles):

```
scope = "openid profile urn:zitadel:iam:org:project:id:<projectId>:aud
         urn:zitadel:iam:org:projects:roles"
POST https://auth.unifeed.io/oauth/v2/token
  grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=<signed JWT>
```

Tokens come back with a ~12 hour lifetime (Zitadel's default), not one hour —
better than never expiring, but worth shortening in project settings if the
window matters.

Remaining work is now mechanical:

The replacement is the mechanism the Terraform provider itself already uses:

1. Add a `zitadel_machine_key` per test machine user and store the JSON key in
   Secret Manager, replacing the PAT secrets.
2. Have the runner exchange the key for an access token at run start via the
   JWT-profile grant (`POST /oauth/v2/token`,
   `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer`) — see §3 for a
   worked example.
3. Drop `zitadel_personal_access_token` and its `expiration_date` workaround
   (§1), which only exists to stop applies rotating these tokens.

This does not remove a long-lived secret so much as change its shape: the key
becomes the durable thing. The gain is that minted tokens die within the hour,
so a token captured in a test artefact is worthless by the time anyone reads
it, and keys carry a real expiry that forces rotation. A side benefit: a
JWT-profile token carries project roles in its claims, so the backend's primary
role path is exercised rather than the PAT-specific database fallback in
`JwtAuthFilter`.

Also still open: the hub accepts the admin PAT for callers other than the
build — demo recordings take the lock with it. Migrating that caller would let
the PAT branch in `requireBearer` be deleted.

## 8. Running a plan without terraform.tfvars

Every other variable has a usable default, so a plan needs only the required
variable plus the Zitadel inputs. Project numbers come from `gcloud`:

```bash
cd environments/multi-shared

# Zitadel key -> a file the provider can read. Note the secret name: the
# similarly-named `zitadel-service-account-key` is the legacy key and fails
# with a generic HTTP 500 that reads like a broken server (§3).
umask 077
gcloud secrets versions access latest --secret=unifeed-zitadel-terraform-key \
  --project=breathe-shared > /tmp/zitadel-key.json

terraform plan \
  -var 'environment_project_numbers=["815682864674","400245265670","375280996820"]' \
  -var 'unifeed_zitadel_manage_config=true' \
  -var "unifeed_zitadel_key_path=/tmp/zitadel-key.json" \
  -var "unifeed_cloudflare_api_token=$(gcloud secrets versions access latest \
        --secret=unifeed-cloudflare-api-token --project=breathe-shared)"

shred -u /tmp/zitadel-key.json
```

Project numbers: `breathe-dev-env` 815682864674, `breathe-staging-env`
400245265670, `breathe-production-env` 375280996820.

**Always read the plan before applying.** Specifically check for `will be
destroyed` against anything under `module.unifeed_zitadel_config` — that is the
signature of a missing or mistyped gating flag, not a real change.
