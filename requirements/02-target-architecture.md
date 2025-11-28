# Target Architecture Requirements

## Overview

Move to a multi-project architecture with clear separation between shared resources and environment-specific deployments.

---

## GCP Project Structure

```
breathe-shared (NEW)
├── Artifact Registry (all Docker images)
├── Cloud Build (all build triggers)
├── Cloud SQL (shared instance, environment databases)
├── GCS Buckets (shared feed data, build caches)
└── Promotion Tool

breathe-dev-env (NEW)
├── Cloud Run Services (dev)
├── Cloud Run Jobs (dev)
├── GCS Buckets (dev-specific: artwork, baskets)
└── Service Accounts (minimal permissions)

breathe-staging-env (NEW)
├── Cloud Run Services (staging)
├── Cloud Run Jobs (staging)
├── GCS Buckets (staging-specific)
└── Service Accounts (minimal permissions)

breathe-production-env (NEW)
├── Cloud Run Services (prod)
├── Cloud Run Jobs (prod)
├── GCS Buckets (prod-specific)
└── Service Accounts (minimal permissions)
```

---

## Shared Project (breathe-shared)

### Purpose
Central hub for builds, artifacts, and shared data that doesn't change per environment.

### Artifact Registry
- `breathe-ecommerce` - E-commerce service images
- `breathe-pf-feed-processor` - Feed processor job images
- `breathe-nginx` - Nginx reverse proxy images
- `breathe-admin` - Admin panel images
- `breathe-pricing-rust` - Rust pricing service images
- `breathe-feed-puller` - Go feed puller job images (future)

### Cloud SQL
- Single instance: `breathe-db`
- Databases per environment: `breathe_dev`, `breathe_staging`, `breathe_prod`
- Private IP with VPC peering to environment projects

### Cloud Storage (Shared)
| Bucket                         | Purpose                              |
|-------------------------------|--------------------------------------|
| `breathe-pf-feeds`            | Raw supplier product feeds           |
| `breathe-product-images`      | Product images (read by all envs)    |
| `breathe-generated-data`      | Processed product JSON               |
| `breathe-build-cache`         | Gradle/Cargo build caches            |

### Cloud Build
All build triggers in shared project:
- Build on commit to main/master
- Tag images with commit SHA and branch name
- Push to Artifact Registry
- NO automatic deployment (promotion tool handles this)

### Promotion Tool
Internal service/CLI to promote images between environments:
- List available images per service
- Promote specific version from dev -> staging -> production
- Track deployment history
- Rollback support

---

## Environment Projects

Each environment project (dev, staging, production) follows identical structure.

### Cloud Run Services
| Service                   | Purpose                          |
|--------------------------|----------------------------------|
| `breathe-ecommerce`      | E-commerce backend API           |
| `breathe-nginx`          | Static product data server       |
| `breathe-admin`          | Admin panel                      |
| `breathe-pricing-rust`   | Pricing calculations (future)    |

### Cloud Run Jobs
| Job                      | Purpose                          |
|-------------------------|----------------------------------|
| `pf-feed-processor`     | Product feed processing          |
| `pf-feed-puller`        | Download feeds from suppliers    |

### Cloud Scheduler (per environment)
| Job                          | Schedule          | Target           |
|-----------------------------|-------------------|------------------|
| `pf-feed-processor-trigger` | Configurable      | Feed processor   |
| `pf-feed-puller-trigger`    | Configurable      | Feed puller      |

### Cloud Storage (Environment-Specific)
| Bucket                              | Purpose                        |
|------------------------------------|--------------------------------|
| `breathe-{env}-artwork-uploaded`   | Customer uploaded artwork      |
| `breathe-{env}-artwork-processed`  | Processed artwork files        |
| `breathe-{env}-basket-storage`     | Shopping basket persistence    |
| `breathe-{env}-cost-pricing`       | Cost/pricing data              |
| `breathe-{env}-email-debug`        | Email debugging (dev/staging)  |

---

## Service Accounts (Per Environment)

### Principle of Least Privilege
Each service gets its own service account with minimal required permissions.

| Service Account               | Permissions                                          |
|------------------------------|-----------------------------------------------------|
| `sa-ecommerce@{project}`     | SQL client, GCS (cost-pricing bucket), Secret accessor |
| `sa-nginx@{project}`         | GCS read (generated-data, images)                   |
| `sa-admin@{project}`         | None (calls ecommerce API)                          |
| `sa-feed-processor@{project}`| SQL client, GCS (feeds, generated-data), Secret accessor |
| `sa-feed-puller@{project}`   | GCS write (feeds)                                   |
| `sa-scheduler@{project}`     | Cloud Run invoker                                   |

### Cross-Project Access
- Environment service accounts need read access to shared buckets
- Cloud Build SA needs push access to Artifact Registry
- Promotion tool needs Cloud Run deploy permissions per environment

---

## Networking

### VPC Configuration
- Shared VPC in `breathe-shared`
- Private Service Connection for Cloud SQL
- VPC peering for environment projects

### Cloud Run Configuration
- Private ingress where possible
- Public ingress only for customer-facing services
- Internal service-to-service communication via VPC connector

---

## Secrets Management

Use Secret Manager in each environment project:
| Secret                    | Purpose                          |
|--------------------------|----------------------------------|
| `db-password`            | Database credentials             |
| `anthropic-api-key`      | AI API key                       |
| `auth0-secret`           | Auth0 configuration              |
| `stripe-api-key`         | Payment processing               |
| `internal-service-token` | Service-to-service auth          |

---

## Deployment Workflow

```
Developer commits code
         │
         ▼
Cloud Build (breathe-shared)
         │
         ├─► Build image
         ├─► Run tests
         ├─► Push to Artifact Registry
         │   (tagged: commit-sha, branch)
         │
         ▼
Promotion Tool
         │
         ├─► Deploy to dev (automatic on main)
         │
         ├─► Deploy to staging (manual trigger)
         │
         └─► Deploy to production (manual, with approval)
```

---

## Environment Configuration

### Development (breathe-dev-env)
- Auto-deploy on main branch builds
- Relaxed resource limits
- Debug logging enabled
- Test data/databases

### Staging (breathe-staging-env)
- Manual promotion from dev
- Production-like configuration
- Pre-production testing
- Sanitised production data

### Production (breathe-production-env)
- Manual promotion with approval
- High availability configuration
- Strict resource limits
- Production data
- Monitoring/alerting enabled

---

## Terraform Module Structure

```
breathe-infra/
├── modules/
│   ├── shared/
│   │   ├── artifact-registry/
│   │   ├── cloud-build/
│   │   ├── cloud-sql/
│   │   ├── gcs-shared/
│   │   └── promotion-tool/
│   │
│   ├── environment/
│   │   ├── cloud-run-service/
│   │   ├── cloud-run-job/
│   │   ├── cloud-scheduler/
│   │   ├── gcs-environment/
│   │   ├── service-accounts/
│   │   └── secrets/
│   │
│   └── networking/
│       ├── vpc/
│       └── vpc-connector/
│
├── environments/
│   ├── shared/
│   │   └── main.tf
│   ├── dev/
│   │   └── main.tf
│   ├── staging/
│   │   └── main.tf
│   └── production/
│       └── main.tf
│
└── terraform.tfvars
```

---

## Adding New Environments

To add a new environment (e.g., `breathe-qa-env`):

1. Create new environment directory under `environments/`
2. Configure variables (region, scaling, schedules)
3. Run `terraform apply` in new directory
4. Add environment to promotion tool
5. Create database schema in shared Cloud SQL

The modular structure ensures consistency across environments.
