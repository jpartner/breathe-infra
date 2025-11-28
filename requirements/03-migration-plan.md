# Staged Migration Plan

## Principles

1. **Zero downtime** - Existing infrastructure remains untouched until new environments are validated
2. **Incremental migration** - One service/component at a time
3. **Rollback capability** - Easy to revert at each stage
4. **Data migration last** - Infrastructure first, data migration when confident

---

## Phase 0: Foundation (Week 1-2)

### 0.1 Create GCP Projects
```
Terraform:
- breathe-shared
- breathe-dev-env
- breathe-staging-env
- breathe-production-env
```

**Actions:**
- [ ] Create projects via Terraform
- [ ] Enable required APIs in each project
- [ ] Set up billing accounts
- [ ] Configure IAM for Terraform service account

### 0.2 Set Up Shared Networking
```
Terraform:
- VPC in breathe-shared
- Private Service Connection for Cloud SQL
- VPC Connectors for environment projects
```

**Actions:**
- [ ] Create shared VPC
- [ ] Configure VPC peering
- [ ] Set up firewall rules
- [ ] Create VPC connectors for Cloud Run

### 0.3 Create Artifact Registry
```
Terraform:
- Docker repositories in breathe-shared
```

**Actions:**
- [ ] Create repository for each service
- [ ] Configure lifecycle policies (retain last 10 versions)
- [ ] Set up cross-project access for environment projects

---

## Phase 1: Build Pipeline (Week 2-3)

### 1.1 Migrate Cloud Build Triggers
```
Terraform:
- Cloud Build triggers in breathe-shared
- Build configurations for each service
```

**Current triggers to migrate:**
- [x] backend (ecommerce + pf-feed-processor)
- [x] breathe-admin-nuxt-claude
- [x] breathe-nginx-reverse-proxy
- [x] breathe-ts-client
- [ ] breathe-pricing-rust (new)

**Actions:**
- [ ] Create new build triggers pointing to shared Artifact Registry
- [ ] Update cloudbuild.yaml files to push to new registry
- [ ] Remove deployment steps from builds (build only)
- [ ] Test builds produce correct images

### 1.2 Create Promotion Tool
```
Options:
A) Simple bash script + gcloud commands
B) Cloud Function with web UI
C) Cloud Run service with API
```

**MVP (Option A):**
```bash
./promote.sh --service ecommerce --from dev --to staging --version abc123
```

**Actions:**
- [ ] Create promotion script/tool
- [ ] Document promotion workflow
- [ ] Set up IAM permissions for promotions

---

## Phase 2: Development Environment (Week 3-4)

### 2.1 Create Cloud SQL Database
```
Terraform:
- Cloud SQL instance in breathe-shared (or new in shared)
- Database: breathe_dev_new
```

**Decision Point:**
- Option A: Create new Cloud SQL instance (cleaner, but more cost)
- Option B: Add database to existing instance (cheaper, slight risk)

**Recommended: Option A for production, Option B for dev/staging**

**Actions:**
- [ ] Create Cloud SQL instance with private IP
- [ ] Create breathe_dev database
- [ ] Set up users and permissions
- [ ] Test connectivity from VPC

### 2.2 Create Shared Buckets
```
Terraform in breathe-shared:
- breathe-pf-feeds (migrate data from pf_feeds)
- breathe-product-images (migrate from breathe_images)
- breathe-generated-data (migrate from breathe_generated_product_data)
```

**Actions:**
- [ ] Create buckets with correct IAM
- [ ] Set up lifecycle policies
- [ ] Plan data sync strategy (gsutil rsync)

### 2.3 Create Dev Environment Buckets
```
Terraform in breathe-dev-env:
- breathe-dev-artwork-uploaded
- breathe-dev-artwork-processed
- breathe-dev-basket-storage
- breathe-dev-cost-pricing
```

**Actions:**
- [ ] Create buckets
- [ ] Set up cross-project access to shared buckets

### 2.4 Create Dev Service Accounts
```
Terraform in breathe-dev-env:
- sa-ecommerce@breathe-dev-env
- sa-nginx@breathe-dev-env
- sa-feed-processor@breathe-dev-env
etc.
```

**Actions:**
- [ ] Create service accounts
- [ ] Assign minimal IAM roles
- [ ] Grant cross-project access where needed

### 2.5 Deploy Services to Dev
```
Terraform in breathe-dev-env:
- Cloud Run: breathe-ecommerce
- Cloud Run: breathe-nginx
- Cloud Run Job: pf-feed-processor
- Cloud Scheduler triggers
```

**Deploy order:**
1. breathe-nginx (no dependencies)
2. breathe-ecommerce (depends on SQL + GCS)
3. pf-feed-processor (depends on SQL + GCS)
4. breathe-admin (depends on ecommerce)

**Actions:**
- [ ] Deploy each service using Terraform
- [ ] Verify service health
- [ ] Test end-to-end flow
- [ ] Set up monitoring

---

## Phase 3: Staging Environment (Week 5)

### 3.1 Replicate Dev Setup
```
Copy breathe-dev-env Terraform to breathe-staging-env with:
- Different project ID
- Production-like resource limits
- Database: breathe_staging
```

**Actions:**
- [ ] Create staging database
- [ ] Create staging buckets
- [ ] Deploy services
- [ ] Test promotion from dev -> staging

---

## Phase 4: Production Environment (Week 6-7)

### 4.1 Create Production Infrastructure
```
Terraform in breathe-production-env:
- All services with production configuration
- Higher resource limits
- Monitoring and alerting
```

**Actions:**
- [ ] Create production database (in shared Cloud SQL)
- [ ] Create production buckets
- [ ] Deploy services (not yet receiving traffic)
- [ ] Configure monitoring/alerting

### 4.2 Data Migration Planning
```
Data to migrate:
- Cloud SQL: breathe_prod -> breathe_production
- GCS: Various buckets
```

**Actions:**
- [ ] Document data migration procedure
- [ ] Create migration scripts
- [ ] Plan maintenance window
- [ ] Set up data sync (continuous) during transition

---

## Phase 5: Traffic Migration (Week 7-8)

### 5.1 DNS/Load Balancer Setup
```
Options:
A) Direct Cloud Run URLs (simple)
B) Cloud Load Balancer with custom domain
C) Keep Vercel for frontend, migrate backend only
```

**Actions:**
- [ ] Set up load balancer (if needed)
- [ ] Configure SSL certificates
- [ ] Set up health checks

### 5.2 Gradual Traffic Shift
```
Day 1: 10% traffic to new production
Day 2: 25% traffic
Day 3: 50% traffic
Day 4: 100% traffic
```

**Actions:**
- [ ] Configure traffic splitting
- [ ] Monitor error rates
- [ ] Rollback plan ready

### 5.3 Decommission Old Infrastructure
```
After 2 weeks stable on new infra:
- Disable old Cloud Build triggers
- Remove old Cloud Run services
- Archive old buckets
- Document for billing purposes
```

---

## Phase 6: Cleanup (Week 9+)

### 6.1 Old Project Cleanup
**Do NOT delete old projects immediately**

**Actions:**
- [ ] Export all configurations
- [ ] Archive important data
- [ ] Disable billing alerts
- [ ] Schedule deletion (90 days)

### 6.2 Documentation
**Actions:**
- [ ] Update runbooks
- [ ] Document new deployment process
- [ ] Train team on new workflow

---

## Risk Mitigation

### Rollback Procedures

**Service deployment failure:**
```bash
# Revert to previous image version
./promote.sh --service ecommerce --env production --version previous-sha
```

**Database issues:**
- Point-in-time recovery enabled
- Daily backups retained for 30 days

**Data sync issues:**
- Keep old buckets read-only during migration
- Bi-directional sync during transition period

### Testing Strategy

**Per phase:**
1. Unit/integration tests in build pipeline
2. Smoke tests after deployment
3. E2E tests before traffic migration

**Production readiness checklist:**
- [ ] All health checks passing
- [ ] Error rate < 0.1%
- [ ] P95 latency acceptable
- [ ] Logs flowing to Cloud Logging
- [ ] Alerts configured

---

## Timeline Summary

| Phase | Description | Duration | Dependencies |
|-------|-------------|----------|--------------|
| 0 | Foundation | 1-2 weeks | None |
| 1 | Build Pipeline | 1 week | Phase 0 |
| 2 | Dev Environment | 1-2 weeks | Phase 1 |
| 3 | Staging Environment | 1 week | Phase 2 |
| 4 | Production Environment | 1-2 weeks | Phase 3 |
| 5 | Traffic Migration | 1 week | Phase 4 |
| 6 | Cleanup | Ongoing | Phase 5 |

**Total estimated duration: 7-10 weeks**

---

## Next Steps

1. **Review and approve architecture** - Confirm target architecture meets requirements
2. **Create Terraform modules** - Start with foundation (projects, networking)
3. **Set up CI/CD for Terraform** - Version control infrastructure changes
4. **Begin Phase 0** - Create projects and networking
