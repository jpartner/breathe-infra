# Breathe Infrastructure

Terraform-managed infrastructure for the Breathe multi-tenant B2B e-commerce platform.

## Architecture

```
breathe-shared              breathe-dev-env         breathe-staging-env     breathe-production-env
├── Artifact Registry       ├── Cloud Run (backend) ├── Cloud Run (backend) ├── Cloud Run (backend)
├── Cloud Build triggers    ├── Cloud Run (admin)   ├── Cloud Run (admin)   ├── Cloud Run (admin)
├── VPC + Connector         ├── Cloud Run Job       ├── Cloud Run Job       ├── Cloud Run Job
├── Zitadel (auth server)   ├── GCS (product data)  ├── GCS (product data)  ├── GCS (product data)
├── Terraform state bucket  ├── GCS (raw feeds)     ├── GCS (raw feeds)     ├── GCS (raw feeds)
└── Cloud SQL (shared)      ├── GCS (images)        ├── GCS (images)        ├── GCS (images)
                            ├── Secrets             ├── Secrets             ├── Secrets
                            └── Service Accounts    └── Service Accounts    └── Service Accounts
```

## Structure

```
breathe-infra/
├── modules/                          # Reusable Terraform modules
│   ├── networking/                   # VPC, subnets, connectors
│   ├── cloud-sql/                    # PostgreSQL instance
│   ├── zitadel/                      # Self-hosted auth server (Cloud Run)
│   └── ...
├── environments/
│   ├── multi-shared/                 # Shared infrastructure (AR, builds, auth, networking)
│   ├── multi-dev/                    # Dev environment
│   ├── multi-staging/                # Staging environment
│   ├── multi-prod/                   # Production environment
│   └── _archived/                    # Old single-tenant configs (reference only)
└── README.md
```

## Remote State

All state is stored in GCS: `gs://breathe-terraform-state/{environment}`

The bucket itself is **not** managed by this repo — it is the backend that holds
the state, so it cannot be in the state it holds. It is a prerequisite for a
rebuild rather than an oversight; see
[docs/rebuilding-environments.md](docs/rebuilding-environments.md).

## Deployment Order

1. **multi-shared** first (networking, Artifact Registry, Zitadel, Cloud Build)
2. **multi-dev** — OIDC client IDs flow from `multi-shared`'s outputs
   automatically, so the two applies are all that is needed (§6)

`environments/multi-staging` and `environments/multi-prod` exist as directories
but contain **no Terraform**. That is a gap waiting rather than a problem: as of
2026-08-13 both projects are empty — no Cloud Run services, no Cloud SQL, two
secrets apiece — so there is nothing built outside this repo. They need writing
before either environment goes live, not reconciling.

**Can this be rebuilt from scratch?** Not unattended — four manual steps remain,
and [docs/rebuilding-environments.md](docs/rebuilding-environments.md) lists them
in order along with what is deliberately excluded.

### Deploy

```bash
cd environments/multi-shared
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

terraform init
terraform plan
terraform apply
```

> **Read [docs/zitadel-and-terraform-variables.md](docs/zitadel-and-terraform-variables.md) before applying `multi-shared`.**
> `terraform.tfvars` is gitignored, and the Zitadel resources are gated behind a
> flag — an apply that omits it plans to destroy 75 identity resources including
> production. That doc also covers which of the two near-identical `zitadel_*` /
> `unifeed_zitadel_*` variable sets is live, and the two-phase client-ID dance
> between `multi-shared` and `multi-dev`.

### Continuous plan

Every push to `main` runs [`cloudbuild/terraform-plan.yaml`](cloudbuild/terraform-plan.yaml)
in Cloud Build (trigger `breathe-infra-plan`, `breathe-shared`/`europe-west2`).
It plans both live environments and **never applies** — it runs as
`sa-terraform-plan`, which holds `roles/viewer` and nothing that can mutate GCP.

The build is red only when the plan errors, or when it proposes **destroying**
anything. Adds and updates pass: this repo carries standing drift by design, so
failing on a non-empty plan would leave the build permanently red. Applying is
still a deliberate local `terraform apply` — see the destroy-trap warning above,
which is exactly what the gate watches for.

**Drift is reported, not gated.** Anything changed outside Terraform — the
classic `gcloud run services update` that the next apply silently reverts — is
posted to Slack with the resource and the attributes that differ. It does not
fail the build: knowing is the point, and whether to reconcile or re-codify is
a judgement call rather than something CI should force.

This uses Terraform's `resource_drift` (state vs reality) rather than
`resource_changes` (config vs reality), which is the difference between "someone
changed this by hand" and "you have not applied your own work yet".

Raw drift is mostly noise and is filtered hard: on real data all 11 raw entries
were server-assigned churn — `etag`, `generation`, revision names, and the image
tags CI moves on every deploy and that `lifecycle ignore_changes` exists to
tolerate. Unfiltered, this would fire on every deploy and be ignored within a
week. If you add resources whose server-side fields churn, extend the `NOISE`
pattern in the gate step rather than muting the report.

### Build notifications

Every Cloud Build in `breathe-shared` — app deploys as well as the plan job —
is posted to Slack by the `cloud-build-slack-notifier` function
([`functions/cloud-build-slack/`](functions/cloud-build-slack/)), which
subscribes to the `cloud-builds` Pub/Sub topic. Only terminal statuses are
posted: Cloud Build emits `QUEUED` and `WORKING` for the same build, and
relaying those would mean three messages each.

The channel is the `slack_build_channel` variable; credentials come from the
`slack-bot-token` secret. Changing the function's code redeploys it because the
source object name carries the archive hash — a static name looks like no diff
and silently keeps the old code running.

## Multi-Tenancy

Tenancy is managed at the application layer, not infrastructure. All tenants share:
- The same Cloud Run services (tenant resolved from `X-Tenant-Id` header)
- The same database (tenant isolation via `tenant_id` column)
- The same GCS buckets (tenant isolation via path prefix)

Tenant-specific configuration (supplier credentials, Stripe keys, margins) is stored
in the database, not in environment variables.

## Auth (Zitadel)

Self-hosted Zitadel runs on Cloud Run in the shared project. Each tenant is a
Zitadel Organization. New environments use Zitadel; the existing `breathe-dev`
project continues using Auth0 unchanged.

Zitadel runs as the `unifeed-zitadel` Cloud Run service in `breathe-shared`,
served at `auth.unifeed.io`, with Breathe, PA and Unifeed as Organizations
within it. Note there are two similarly-named variable sets — `unifeed_zitadel_*`
drives the provider and module that manage the orgs, projects and OIDC apps. See
[docs/zitadel-and-terraform-variables.md](docs/zitadel-and-terraform-variables.md).

## Important

- **NEVER modify `breathe-dev`** — this is the live single-tenant system
- **NEVER commit `terraform.tfvars`** — contains project-specific values
- All changes go through Terraform — no manual GCP console changes
- **This includes creating secrets.** `gcloud secrets create` leaves a secret
  invisible to `plan` and able to survive a destroy, and nothing warns you. On
  2026-08-12, 28 of 50 secrets had accumulated that way in under a month.
  Declare them, or adopt them in the same change —
  `environments/multi-shared/adopted-secrets.tf` is the pattern
- Production changes require review
