# Current GCP Infrastructure State

## Overview

Currently, all Breathe infrastructure runs in a single GCP project (`breathe-dev`) with some ad-hoc separation between dev and prod environments using naming conventions and separate database schemas.

---

## GCP Projects

| Project ID      | Project Number   | Purpose                                    |
|-----------------|------------------|-------------------------------------------|
| `breathe-dev`   | 370661120923     | Main project (dev + prod workloads mixed) |
| `breathe-prod`  | 404684462444     | Legacy/unused (1 old service)             |

---

## Cloud Run Services (breathe-dev)

| Service                       | Region        | Description                          | Key Config                                      |
|-------------------------------|---------------|--------------------------------------|------------------------------------------------|
| `breathe-ecommerce`           | europe-west2  | E-commerce backend (dev)             | 2 CPU, 1GB RAM, max 2 instances                |
| `breathe-ecommerce-prod`      | europe-west2  | E-commerce backend (prod)            | Same as dev                                    |
| `breathe-nginx-reverse-proxy` | europe-west2  | Static product data server           | 1 CPU, 512MB RAM, max 100 instances            |
| `breathe-admin-nuxt-claude`   | us-central1   | Admin panel (Nuxt)                   | 1 CPU, 512MB RAM                               |

### Service Dependencies

**breathe-ecommerce:**
- Cloud SQL: `breathe-branding` (database: `breathe_dev` or `breathe_prod`)
- GCS: `breathe_cost_pricing` (mounted via GCSFUSE)
- Environment: `BREATHE_ENV=BREATHE_WEST2_TEST` (dev) or `BREATHE_WEST2_PROD` (prod)

**breathe-nginx-reverse-proxy:**
- GCS (read-only): `breathe_generated_product_data`, `breathe_images`

**breathe-admin-nuxt-claude:**
- Calls breathe-ecommerce API

---

## Cloud Run Jobs (breathe-dev)

| Job               | Region        | Schedule          | Description                                |
|-------------------|---------------|-------------------|-------------------------------------------|
| `pffeedprocessor` | europe-west2  | 06:00, 12:00 UTC  | Product feed processor (Kotlin)           |

### Job Configuration
- CPU: 8 cores, Memory: 4GB
- Timeout: 1 hour
- Max retries: 1
- Environment: `BREATHE_ENV=BREATHE_WEST2_PROD`
- Image: `europe-west2-docker.pkg.dev/breathe-dev/breathe-pf-feed-processor/breathe-pf-feed-processor:latest`

---

## Cloud Scheduler (breathe-dev)

| Job Name                           | Schedule             | Target              |
|------------------------------------|----------------------|---------------------|
| `breathefeedpuller-scheduler-trigger` | Hourly            | HTTP (appears unused) |
| `pffeedprocessor-scheduler-trigger`   | 06:00, 12:00 UTC  | HTTP (triggers job)   |

---

## Cloud SQL (breathe-dev)

### Instance: `breathe-branding`
- **Version:** PostgreSQL 16
- **Location:** europe-west2-c
- **Tier:** db-custom-2-8192 (2 vCPU, 8GB RAM)
- **Public IP:** 34.147.219.154

### Databases
| Database        | Purpose                    |
|-----------------|----------------------------|
| `breathe_dev`   | Development environment    |
| `breathe_prod`  | Production environment     |
| `breathe_test`  | Testing                    |
| `breathe_jp_dev`| JP dev environment         |

---

## Artifact Registry (breathe-dev)

| Repository                   | Format | Location     | Size     |
|------------------------------|--------|--------------|----------|
| `breathe-ecommerce`          | Docker | europe-west2 | 58.9 GB  |
| `breathe-pf-feed-processor`  | Docker | europe-west2 | 33.0 GB  |
| `breathe-docker`             | Docker | europe-west2 | 313 MB   |
| `cloud-run-source-deploy`    | Docker | europe-west2 | 978 MB   |
| `cloud-run-source-deploy`    | Docker | us-central1  | 5.1 GB   |
| `breathe-maven`              | Maven  | europe-west2 | 0 MB     |
| `breathe-npm`                | NPM    | europe-west2 | 0.8 MB   |

---

## Cloud Storage Buckets (breathe-dev)

| Bucket                          | Purpose                                     |
|--------------------------------|---------------------------------------------|
| `pf_feeds`                     | Raw supplier product feeds                  |
| `breathe_generated_product_data` | Processed product JSON/static data        |
| `breathe_images`               | Product images                              |
| `breathe_uploaded_artwork`     | Customer uploaded artwork                   |
| `artwork_files_dev`            | Processed artwork files                     |
| `breathe_cost_pricing`         | Cost/pricing data files                     |
| `breathe_basket_storage`       | Shopping basket persistence                 |
| `breathe-build-caches`         | Gradle build cache                          |
| `email_debug`                  | Email debugging/logs                        |

---

## Service Accounts (breathe-dev)

| Account                                               | Purpose                    |
|------------------------------------------------------|----------------------------|
| `370661120923-compute@developer.gserviceaccount.com` | Default compute (overused) |
| `breathe-dev@appspot.gserviceaccount.com`            | App Engine default         |
| `vercel-npm@breathe-dev.iam.gserviceaccount.com`     | Vercel NPM access          |

**Issue:** All services currently use the default compute service account with broad permissions.

---

## Cloud Build Triggers (breathe-dev)

| Trigger                              | Source Repo                | Branch    | Action                      |
|-------------------------------------|---------------------------|-----------|----------------------------|
| Backend (ecommerce + pf-feed)       | jpartner/backend          | main      | Build & deploy both        |
| breathe-admin-nuxt-claude           | jpartner/breathe-admin... | master    | Build & deploy             |
| breathe-nginx-reverse-proxy         | jpartner/breathe-nginx... | master    | Build & deploy             |
| breathe-ts-client                   | jpartner/breathe-ts-client | .*       | Build NPM package          |
| breathe-gcp (DISABLED)              | jpartner/breathe-gcp      | master    | Build & deploy job         |

---

## Source Repositories

| Repository                  | Language   | Purpose                                   |
|----------------------------|------------|------------------------------------------|
| `backend`                  | Kotlin     | ecommerce service + pf-feed-processor    |
| `customer-fe`              | TypeScript | Customer frontend (Next.js, on Vercel)   |
| `breathe-admin-nuxt-claude`| TypeScript | Admin panel (Nuxt)                       |
| `breathe-gcp`/`gcp`        | Go         | Feed puller job + artwork service        |
| `breathe-nginx-reverse-proxy` | Nginx   | Static content server                    |
| `breathe-ts-client`        | TypeScript | Shared API client library                |
| `breathe-pricing-rust`     | Rust       | New pricing service (not deployed yet)   |

---

## Key Issues with Current Setup

1. **No environment isolation** - Dev and prod share same project, same service accounts
2. **Overprivileged service accounts** - Everything uses default compute account
3. **No image promotion workflow** - Direct deploy from build
4. **Mixed deployment regions** - Admin in us-central1, rest in europe-west2
5. **Manual prod deployments** - No clear CI/CD pipeline for production
6. **Database in same instance** - All environments share one Cloud SQL instance
7. **No secrets management** - API keys in environment variables
8. **Large artifact sizes** - Need cleanup/lifecycle policies
