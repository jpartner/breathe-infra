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

## Deployment Order

1. **multi-shared** first (networking, Artifact Registry, Zitadel, Cloud Build)
2. **multi-dev** (can deploy after shared is up)
3. **multi-staging** / **multi-prod** (same structure as dev)

### Deploy

```bash
cd environments/multi-shared
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

terraform init
terraform plan
terraform apply
```

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

## Important

- **NEVER modify `breathe-dev`** — this is the live single-tenant system
- **NEVER commit `terraform.tfvars`** — contains project-specific values
- All changes go through Terraform — no manual GCP console changes
- Production changes require review
