# Breathe Infrastructure

Terraform-based Infrastructure as Code for Breathe B2B e-commerce platform.

## Overview

This repository contains Terraform configurations for managing Breathe's GCP infrastructure across multiple environments.

## Project Structure

```
breathe-infra/
├── requirements/              # Architecture documentation
│   ├── 01-current-state.md   # Analysis of existing infrastructure
│   ├── 02-target-architecture.md  # Target state design
│   ├── 03-migration-plan.md  # Staged migration approach
│   └── 04-service-inventory.md    # Service requirements
│
├── modules/                   # Reusable Terraform modules
│   ├── project/              # GCP project creation
│   ├── artifact-registry/    # Container image repositories
│   ├── networking/           # VPC, subnets, connectors
│   ├── cloud-sql/            # PostgreSQL instance
│   └── environment/          # Per-environment resources
│
├── environments/             # Environment-specific configs
│   ├── shared/               # Shared project (builds, DB, artifacts)
│   ├── dev/                  # Development environment
│   ├── staging/              # Staging environment
│   └── production/           # Production environment
│
└── tools/                    # Operational tooling (TODO)
    └── promote/              # Image promotion tool
```

## Target Architecture

```
breathe-shared          breathe-dev-env    breathe-staging-env    breathe-production-env
├── Artifact Registry   ├── Cloud Run      ├── Cloud Run          ├── Cloud Run
├── Cloud Build         ├── Cloud Jobs     ├── Cloud Jobs         ├── Cloud Jobs
├── Cloud SQL           ├── GCS (env)      ├── GCS (env)          ├── GCS (env)
├── VPC + Connector     ├── Secrets        ├── Secrets            ├── Secrets
└── GCS (shared)        └── Service Accts  └── Service Accts      └── Service Accts
```

## Getting Started

### Prerequisites

- Terraform >= 1.5
- gcloud CLI authenticated with appropriate permissions
- Billing account ID

### Deployment Order

Infrastructure must be deployed in this order:

1. **Shared project first** (contains Artifact Registry, Cloud SQL, VPC)
2. **Environment projects** (can be deployed in parallel after shared)

### Deploy Shared Project

```bash
cd environments/shared

# Create terraform.tfvars from example
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your billing_account

terraform init
terraform plan
terraform apply
```

### Deploy Environment Project

```bash
cd environments/dev  # or staging, production

# Create terraform.tfvars from example
cp terraform.tfvars.example terraform.tfvars
# Edit with your billing_account and shared project outputs

terraform init
terraform plan
terraform apply
```

### Create Database Schemas

Database schemas are **opt-in** to avoid requiring Cloud SQL Proxy for normal Terraform operations.

```bash
cd environments/shared

# 1. Start Cloud SQL Proxy in a separate terminal
cloud-sql-proxy --port 5432 breathe-shared:europe-west2:breathe-db

# 2. Get the database admin password from Secret Manager
gcloud secrets versions access latest --secret=db-password --project=breathe-shared

# 3. Apply with schema management enabled
terraform apply \
  -var="manage_db_schemas=true" \
  -var="db_admin_password=<password_from_step_2>"
```

This creates an `app` schema in each environment database (breathe_dev, breathe_staging, breathe_prod).

**Note:** Normal `terraform plan/apply` commands work without the proxy - schema management is disabled by default.

## Modules

### project
Creates a GCP project with required APIs enabled.

### artifact-registry
Creates Docker repositories with lifecycle policies for image cleanup.

### networking
Creates VPC, subnets, VPC connector for Cloud Run, and private service connection for Cloud SQL.

### cloud-sql
Creates PostgreSQL instance with private IP, multiple databases, and stores password in Secret Manager.

### environment
Creates per-environment resources: service accounts, GCS buckets, and IAM bindings.

### database-schemas
Creates PostgreSQL schemas within Cloud SQL databases. Requires Cloud SQL Proxy running locally.

## Documentation

- [Current State Analysis](requirements/01-current-state.md)
- [Target Architecture](requirements/02-target-architecture.md)
- [Migration Plan](requirements/03-migration-plan.md)
- [Service Inventory](requirements/04-service-inventory.md)

## Migration Status

- [x] Phase 0.0: Create repository
- [x] Phase 0.0: Document current state
- [x] Phase 0.0: Document target architecture
- [x] Phase 0.0: Create Terraform modules
- [ ] Phase 0.1: Deploy shared project
- [ ] Phase 0.2: Deploy dev environment
- [ ] Phase 0.3: Deploy staging environment
- [ ] Phase 0.4: Deploy production environment
- [ ] Phase 1: Create Cloud Build triggers
- [ ] Phase 2: Deploy services to dev
- [ ] Phase 3: Test and validate
- [ ] Phase 4: Traffic migration
- [ ] Phase 5: Cleanup old infrastructure

## Important Notes

- **Do NOT modify existing `breathe-dev` project** until new environments are validated
- Deploy shared project before any environment projects
- All infrastructure changes must go through Terraform
- Production changes require approval
- Never commit `terraform.tfvars` files (they contain billing info)
