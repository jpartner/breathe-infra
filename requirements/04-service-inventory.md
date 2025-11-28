# Service Inventory

## Cloud Run Services

### 1. breathe-ecommerce

**Source:** `backend/ecommerce`
**Language:** Kotlin/Ktor
**Current Location:** europe-west2

#### Resource Requirements
| Config | Dev | Staging | Production |
|--------|-----|---------|------------|
| CPU | 1 | 2 | 2 |
| Memory | 512Mi | 1Gi | 1Gi |
| Min instances | 0 | 0 | 1 |
| Max instances | 2 | 5 | 10 |
| Concurrency | 80 | 80 | 80 |

#### Dependencies
- **Cloud SQL:** Read/write access to database
- **GCS Buckets:**
  - `breathe-cost-pricing` (read, mounted via GCSFUSE)
  - `breathe-basket-storage` (read/write)
  - `breathe-uploaded-artwork` (read/write)
- **Secrets:**
  - Database credentials
  - Anthropic API key
  - Stripe API key
  - Auth0 configuration

#### Service Account Permissions
```
roles/cloudsql.client
roles/storage.objectViewer (cost-pricing)
roles/storage.objectAdmin (basket-storage, uploaded-artwork)
roles/secretmanager.secretAccessor
```

#### Environment Variables
| Variable | Description |
|----------|-------------|
| `BREATHE_ENV` | Environment identifier |
| `DB_NAME` | Database name |
| `DB_HOST` | Cloud SQL private IP |
| `DB_USER` | Database username |
| `DB_PASSWORD` | From Secret Manager |

---

### 2. breathe-nginx-reverse-proxy

**Source:** `breathe-nginx-reverse-proxy`
**Language:** Nginx
**Current Location:** europe-west2

#### Resource Requirements
| Config | Dev | Staging | Production |
|--------|-----|---------|------------|
| CPU | 1 | 1 | 1 |
| Memory | 256Mi | 512Mi | 512Mi |
| Min instances | 0 | 0 | 1 |
| Max instances | 10 | 50 | 100 |
| Concurrency | 80 | 80 | 80 |

#### Dependencies
- **GCS Buckets (read-only, mounted via GCSFUSE):**
  - `breathe-generated-product-data`
  - `breathe-images`

#### Service Account Permissions
```
roles/storage.objectViewer (generated-data, images)
```

#### Environment Variables
None required (configuration via nginx.conf)

---

### 3. breathe-admin

**Source:** `breathe-admin-nuxt-claude`
**Language:** TypeScript/Nuxt
**Current Location:** us-central1 (should move to europe-west2)

#### Resource Requirements
| Config | Dev | Staging | Production |
|--------|-----|---------|------------|
| CPU | 1 | 1 | 1 |
| Memory | 512Mi | 512Mi | 512Mi |
| Min instances | 0 | 0 | 1 |
| Max instances | 2 | 5 | 10 |
| Concurrency | 80 | 80 | 80 |

#### Dependencies
- **External API:** breathe-ecommerce

#### Service Account Permissions
```
(minimal - no GCP resources needed)
```

#### Environment Variables
| Variable | Description |
|----------|-------------|
| `NUXT_PUBLIC_API_BASE` | E-commerce API URL |
| `AUTH0_*` | Auth0 configuration |

---

### 4. breathe-pricing-rust (NEW)

**Source:** `breathe-pricing-rust`
**Language:** Rust
**Target Location:** europe-west2

#### Resource Requirements
| Config | Dev | Staging | Production |
|--------|-----|---------|------------|
| CPU | 1 | 1 | 2 |
| Memory | 512Mi | 512Mi | 1Gi |
| Min instances | 0 | 1 | 1 |
| Max instances | 5 | 10 | 100 |
| Concurrency | 100 | 100 | 100 |

#### Dependencies
- **GCS Buckets:**
  - `breathe-cost-pricing` (read)
- **Secrets:**
  - Internal service token

#### Service Account Permissions
```
roles/storage.objectViewer (cost-pricing)
roles/secretmanager.secretAccessor
```

---

## Cloud Run Jobs

### 1. pf-feed-processor

**Source:** `backend/pf-feed-processor`
**Language:** Kotlin
**Current Location:** europe-west2

#### Resource Requirements
| Config | Dev | Staging | Production |
|--------|-----|---------|------------|
| CPU | 4 | 8 | 8 |
| Memory | 2Gi | 4Gi | 4Gi |
| Timeout | 1h | 1h | 1h |
| Max retries | 1 | 1 | 1 |

#### Schedule
| Environment | Schedule |
|-------------|----------|
| Dev | 08:00 UTC |
| Staging | 07:00 UTC |
| Production | 06:00, 12:00 UTC |

#### Dependencies
- **Cloud SQL:** Read/write access
- **GCS Buckets:**
  - `breathe-pf-feeds` (read)
  - `breathe-generated-product-data` (write)
  - `breathe-images` (write)

#### Service Account Permissions
```
roles/cloudsql.client
roles/storage.objectViewer (pf-feeds)
roles/storage.objectAdmin (generated-data, images)
```

---

### 2. pf-feed-puller (from breathe-gcp)

**Source:** `breathe-gcp/jobs/pfFeedPuller`
**Language:** Go
**Current Location:** Not deployed (scheduler exists but disabled)

#### Resource Requirements
| Config | Dev | Staging | Production |
|--------|-----|---------|------------|
| CPU | 1 | 1 | 1 |
| Memory | 512Mi | 512Mi | 512Mi |
| Timeout | 30m | 30m | 30m |
| Max retries | 3 | 3 | 3 |

#### Schedule
| Environment | Schedule |
|-------------|----------|
| Dev | Hourly |
| Staging | Hourly |
| Production | Hourly |

#### Dependencies
- **GCS Buckets:**
  - `breathe-pf-feeds` (write)
- **External:** Supplier feed URLs

#### Service Account Permissions
```
roles/storage.objectAdmin (pf-feeds)
```

---

## External Services (Not in Terraform)

### Customer Frontend
**Source:** `customer-fe`
**Deployed to:** Vercel
**Notes:** Remains on Vercel, not migrating to GCP

### TypeScript Client Library
**Source:** `breathe-ts-client`
**Published to:** NPM (via Artifact Registry)
**Notes:** Build trigger only, no deployment

---

## Service Dependencies Graph

```
┌─────────────────┐
│  customer-fe    │ (Vercel)
│  (Next.js)      │
└────────┬────────┘
         │ API calls
         ▼
┌─────────────────┐     ┌─────────────────┐
│ breathe-nginx   │◄────│ pf-feed-        │
│ (static data)   │     │ processor       │
└────────┬────────┘     └────────┬────────┘
         │                       │
         │ GCS                   │ writes
         ▼                       ▼
    ┌─────────┐            ┌─────────┐
    │ GCS     │            │ GCS     │
    │ images  │            │ data    │
    └─────────┘            └─────────┘
                                 ▲
                                 │ reads
┌─────────────────┐     ┌────────┴────────┐
│ breathe-admin   │────►│ breathe-        │
│ (Nuxt)          │     │ ecommerce       │
└─────────────────┘     └────────┬────────┘
                                 │
                        ┌────────┴────────┐
                        ▼                 ▼
                   ┌─────────┐      ┌──────────┐
                   │ Cloud   │      │ GCS      │
                   │ SQL     │      │ baskets  │
                   └─────────┘      └──────────┘
```

---

## Image Tagging Strategy

All images tagged with:
- `{commit-sha}` - Unique build identifier
- `{branch-name}` - Branch that triggered build
- `latest-{env}` - Latest promoted to environment

Example:
```
europe-west2-docker.pkg.dev/breathe-shared/breathe-ecommerce/breathe-ecommerce:abc1234
europe-west2-docker.pkg.dev/breathe-shared/breathe-ecommerce/breathe-ecommerce:main
europe-west2-docker.pkg.dev/breathe-shared/breathe-ecommerce/breathe-ecommerce:latest-dev
europe-west2-docker.pkg.dev/breathe-shared/breathe-ecommerce/breathe-ecommerce:latest-production
```
