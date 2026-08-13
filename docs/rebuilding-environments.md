# Rebuilding an environment from scratch

The goal is that an environment can be rebuilt without manual work. This
document is an honest account of how close that is today, what still requires a
human, and in what order those gaps are worth closing.

Verified 2026-08-13. Re-check before trusting the specifics — this file goes
stale the same way §7 of
[zitadel-and-terraform-variables.md](zitadel-and-terraform-variables.md) did.

---

## 1. Where it stands

Good, and better than it was on 2026-08-11:

- **Every secret in `breathe-shared` is declared.** 50 live, 50 managed, no
  unmanaged secrets and none in state that do not exist (§7).
- **No drift.** `multi-shared` reports 0 of 0 raw drift entries; `multi-dev` is
  clean. Anything that reappears is reported to Slack by the plan job.
- **Plans run on every push**, so a config that has stopped matching reality
  says so within minutes rather than at the next apply.

None of that means an environment can be rebuilt unattended. Managed is not the
same as reproducible: Terraform knowing a secret exists says nothing about
whether a rebuild can put the right value in it.

`multi-staging` and `multi-prod` have no Terraform, but both projects are empty
as of 2026-08-13 — no Cloud Run, no Cloud SQL, two secrets apiece. Nothing has
been built outside this repo; those environments simply have not been written
yet.

## 2. What a from-scratch rebuild actually needs

In order. Steps marked **MANUAL** cannot currently be done by Terraform.

1. **MANUAL — create the state bucket.** `gs://breathe-terraform-state` is the
   backend for both roots and is declared by neither. It was created by hand and
   nothing recreates it. This is the ordinary bootstrap problem (state cannot
   hold the bucket that holds state), and the fix is not to manage it but to
   write down that it is a prerequisite:
   ```bash
   gcloud storage buckets create gs://breathe-terraform-state \
     --project=breathe-shared --location=europe-west2 --uniform-bucket-level-access
   gcloud storage buckets update gs://breathe-terraform-state --versioning
   ```
2. **MANUAL — supply the three `multi-shared` inputs.** `terraform.tfvars` is
   gitignored and the real values exist only on an operator's machine. §8 has the
   recipe; the values are project numbers, the Zitadel key path and the
   Cloudflare tokens.
3. Apply `multi-shared`. This creates the projects, networking, Cloud SQL,
   Artifact Registry, Zitadel and its config, and all 50 secret containers.
4. **MANUAL — populate 25 secret values.** The adopted secrets are managed as
   containers only, so a rebuild creates them empty. Supplier API keys come from
   third parties and cannot be regenerated at all; they must be retrieved from
   wherever they are held and added with `gcloud secrets versions add`. This is a
   deliberate trade — managing the versions would put third-party credentials in
   the state file — but it is a real limit on unattended rebuild.
5. Apply `multi-dev`. Its OIDC client IDs come from `multi-shared`'s outputs
   automatically (§6) — this was a manual hand-edit until 2026-08-13.
6. **MANUAL — connect the repo to Cloud Build.** Triggers are declared in
   Terraform, but the GitHub App connection they depend on is an interactive
   OAuth flow. Applying a `google_cloudbuild_trigger` for an unconnected repo
   fails with `Error 400: Repository mapping does not exist`. Connect at
   `console.cloud.google.com/cloud-build/triggers` first.
7. **MANUAL — grant the CI service account out of band, once.** The config
   manages the IAM of the very service account that CI uses, so the first grant
   has to come from somewhere else. After that Terraform keeps it in sync.

## 3. The gaps, worst first

1. **Secret values (step 4).** Partly irreducible — nobody can regenerate a
   supplier's API key — but the *list* of what must be supplied should live
   somewhere better than this paragraph.
2. **`terraform.tfvars` values on one laptop (step 2).** A bus-factor problem
   more than a rebuild problem, since §8 documents how to derive them.
3. **`.terraform.lock.hcl` is gitignored** (`.gitignore:6`), so provider
   versions are not pinned reproducibly. Two rebuilds a month apart can resolve
   different provider versions from the same commit. Committing the lock file
   would fix this outright.

## 4. What is deliberately not in Terraform

Not gaps — decisions, recorded so nobody "fixes" them by accident:

| Thing | Why |
|---|---|
| Secret *versions* for the 25 adopted secrets | Managing them puts supplier and vendor credentials in the state file |
| Cloud Run image tags | CI moves them every deploy; `lifecycle ignore_changes` exists so Terraform tolerates that |
| `client` / `client_version` | Server-assigned record of which tool last wrote a service. No input exists |
| Cloud SQL `disk_size` | `disk_autoresize` grows it; Terraform would plan to shrink it back and Cloud SQL rejects that |
| The state bucket | Bootstrap ordering — see step 1 |

## 5. Checking you are still clean

```bash
# Secrets: both should print nothing
cd environments/multi-shared
gcloud secrets list --project=breathe-shared --format="value(name)" \
  | LC_ALL=C sort > /tmp/gcp.txt
terraform state pull | python3 -c "
import json,sys
st=json.load(sys.stdin)
print('\n'.join({i['attributes']['secret_id']
     for r in st.get('resources',[]) if r.get('type')=='google_secret_manager_secret'
     for i in r.get('instances',[])}))" | LC_ALL=C sort > /tmp/tf.txt
LC_ALL=C comm -23 /tmp/gcp.txt /tmp/tf.txt   # live but unmanaged
LC_ALL=C comm -13 /tmp/gcp.txt /tmp/tf.txt   # in state but gone
```

Drift is checked for you on every push to `main` and reported to Slack — see
"Continuous plan" in the [README](../README.md). A green build means no
proposed destroys; it does **not** mean no drift, because drift is reported
rather than gated.

## 6. Things that will bite during a rebuild

- **`LC_ALL=C`** on the `sort`/`comm` above. Without it they disagree about case
  and the comparison silently reports nonsense rather than failing.
- **A failed Cloud Functions gen2 deploy leaves orphans.** If the Eventarc
  trigger fails validation, the underlying Cloud Run service, the Eventarc
  trigger and a function entry in state `UNKNOWN` survive, none of them in
  Terraform state. The retry then fails with a misleading
  `409 already exists` instead of the original error. Delete all three.
- **Newly enabled APIs need a minute.** Enabling `eventarc.googleapis.com` and
  immediately creating a trigger fails with
  `Permission "iam.serviceAccounts.ActAs" denied` even for a project owner. It
  is service-agent propagation, not a permission gap. Wait and retry.
- **`terraform force-unlock` wants the GCS object generation**, not the lock
  UUID printed in the error:
  ```bash
  gcloud storage objects describe gs://breathe-terraform-state/multi-shared/default.tflock \
    --format="value(generation)"
  ```
  Check no `terraform` process is actually running first — this checkout is
  shared between sessions.
- **Data-access audit logging is off.** There are no `AccessSecretVersion`
  records, so "nothing reads this secret" can never be concluded from logs. Only
  admin activity (create, delete, SetIamPolicy) is recorded.
