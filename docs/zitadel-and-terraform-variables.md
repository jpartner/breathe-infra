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

## 6. Client IDs are a two-phase apply

`multi-shared` creates the OIDC applications; `multi-dev` consumes their client
IDs through variables whose **defaults hold the real values**
(`storefront_*_client_id`, `admin_*_client_id` in
`environments/multi-dev/variables.tf`).

So the order is:

1. Apply `multi-shared`.
2. Read the IDs back:
   ```bash
   terraform output -json unifeed_admin_client_ids
   terraform output -json unifeed_customer_client_ids
   ```
3. Update the corresponding defaults in `environments/multi-dev/variables.tf`.
4. Apply `multi-dev`.

Step 3 is easy to forget and matters whenever an apply **replaces** an
application rather than updating it in place — changing `app_type`, for example,
forces replacement and issues a new client ID. A stale ID produces a login
failure that looks like a misconfigured tenant.

## 7. Secret inventory — and what Terraform actually owns

`breathe-shared` holds 42 secrets. **Terraform manages 16 of them.** The other 26
were created out of band, so they are invisible to `plan` and survive a destroy.
Knowing which is which avoids two failure modes: assuming Terraform will recreate
something it has never seen, and hand-editing something an apply will overwrite.

Counts verified 2026-08-11 against `multi-shared` state.

**Terraform-managed (16)** — an apply can create, rotate or destroy these:

| Secret | Used for |
|---|---|
| `db-admin-password`, `db-app-password` | Cloud SQL users |
| `unifeed-zitadel-masterkey`, `unifeed-zitadel-db-password` | The Zitadel deployment itself |
| `storefront-{breathe,breathe-eu,pa,uniten}-auth-secret` | NextAuth session encryption per storefront |
| `admin-{breathe,pa,uniten}-auth-secret` | NextAuth session encryption per admin UI (added alongside admin auth) |
| `ingest-zitadel-client-secret`, `ingest-auth-secret` | Ingest tool OIDC client + NextAuth secret |
| `unifeed-test-{admin,customer,norole}-pat` | e2e machine-user PATs |
| `unifeed-test-login-password` | e2e human login (`e2e-test@unifeed.io`) |
| `pa-migration-api-key`, `postmark-api-key` | PA migration service, transactional email |

Note the e2e PATs are generated by the Zitadel block: destroying it (see §1)
invalidates the tokens the test suite authenticates with, and new versions are
written on the next apply.

**Not managed by Terraform (26)** — created by hand or by a script, and nothing
in this repo will recreate them:

`zitadel-service-account-key`, `worker-api-key`, `typesense-api-key`,
`test-user-credentials`, `cloudflare-api-token`, `unifeed-cloudflare-api-token`,
`github-ssh-key`, `slack-bot-token`, `anthropic-api-key`, `db-password`,
`VECTORIZER_API_ID`, `VECTORIZER_API_SECRET`, and the supplier credentials
(`bic-graphic-*`, `crystal-galleries-api-key`, `goldstar-api-password`,
`impression-europe-password`, `keramikos-password`, `laltex-api-key`,
`midocean-api-key`, `outdoors-company-user-token`, `pinpoint-api-key`,
`preseli-secret-key`, `umbrella-api-key`, `usbgroup-api-key`, `xoopar-password`).

Supplier credentials being manual is reasonable — they come from third parties.
But two are worth attention:

- **`zitadel-service-account-key`** relates to the credential Terraform itself
  needs, and is not managed by Terraform — so nothing in this repo recreates or
  rotates it. See the TODO in §3: the authoritative source of the provider key
  should be written down.
- **`worker-api-key`** authenticates the GPU enrichment worker against endpoints
  that Spring Security leaves open, so it is the only thing protecting them. The
  backend now refuses worker requests outright when it is unset rather than
  falling back to a default key.

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

## 8. Running a plan without terraform.tfvars

Every other variable has a usable default, so a plan needs only the required
variable plus the Zitadel inputs. Project numbers come from `gcloud`:

```bash
cd environments/multi-shared

# Zitadel key -> a file the provider can read (see §3 — currently fails)
umask 077
gcloud secrets versions access latest --secret=zitadel-service-account-key \
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
