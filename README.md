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
├── modules/                   # Reusable Terraform modules (TODO)
│   ├── shared/               # Shared project resources
│   ├── environment/          # Per-environment resources
│   └── networking/           # VPC and connectivity
│
├── environments/             # Environment-specific configs (TODO)
│   ├── shared/
│   ├── dev/
│   ├── staging/
│   └── production/
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
└── GCS (shared)        └── SAs            └── SAs                └── SAs
```

## Getting Started

### Prerequisites

- Terraform >= 1.5
- gcloud CLI authenticated
- Appropriate GCP permissions

### Initial Setup

```bash
# Clone repository
git clone git@github.com:jpartner/breathe-infra.git
cd breathe-infra

# Review requirements documentation
ls requirements/

# (Once Terraform is set up)
cd environments/shared
terraform init
terraform plan
```

## Documentation

- [Current State Analysis](requirements/01-current-state.md)
- [Target Architecture](requirements/02-target-architecture.md)
- [Migration Plan](requirements/03-migration-plan.md)
- [Service Inventory](requirements/04-service-inventory.md)

## Migration Status

- [x] Phase 0.0: Create repository
- [x] Phase 0.0: Document current state
- [x] Phase 0.0: Document target architecture
- [ ] Phase 0.1: Create GCP projects
- [ ] Phase 0.2: Set up networking
- [ ] Phase 0.3: Create Artifact Registry
- [ ] Phase 1: Build pipeline migration
- [ ] Phase 2: Dev environment
- [ ] Phase 3: Staging environment
- [ ] Phase 4: Production environment
- [ ] Phase 5: Traffic migration
- [ ] Phase 6: Cleanup

## Contributing

1. Create a feature branch
2. Make changes
3. Run `terraform fmt` and `terraform validate`
4. Create PR for review

## Important Notes

- **Do NOT modify existing `breathe-dev` infrastructure** until new environments are validated
- All infrastructure changes must go through Terraform
- Production changes require approval
