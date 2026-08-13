#!/usr/bin/env bash
#
# Create the GCS bucket that holds Terraform state.
#
# This is the one thing Terraform cannot manage for itself: it is the backend
# that stores the state, so it cannot live in the state it stores. Rather than
# leaving that as a paragraph in a document, it is a script — the step survives,
# but it stops being something anyone has to reconstruct from memory.
#
# Safe to re-run. If the bucket exists, this verifies its settings and changes
# nothing.
#
#   ./scripts/bootstrap-state-bucket.sh [PROJECT] [LOCATION]

set -euo pipefail

PROJECT="${1:-breathe-shared}"
LOCATION="${2:-europe-west2}"
BUCKET="gs://breathe-terraform-state"

echo "Bucket:   ${BUCKET}"
echo "Project:  ${PROJECT}"
echo "Location: ${LOCATION}"
echo

if gcloud storage buckets describe "${BUCKET}" --project="${PROJECT}" >/dev/null 2>&1; then
  echo "Bucket already exists — verifying settings, changing nothing."
else
  echo "Creating bucket..."
  gcloud storage buckets create "${BUCKET}" \
    --project="${PROJECT}" \
    --location="${LOCATION}" \
    --uniform-bucket-level-access \
    --public-access-prevention
fi

# Versioning is not optional here. State is the only record of what Terraform
# believes exists; a corrupted or truncated write with no previous version is
# unrecoverable except by importing every resource by hand.
echo "Ensuring object versioning is on..."
gcloud storage buckets update "${BUCKET}" --project="${PROJECT}" --versioning

echo
# Field names matter here: it is versioning_enabled and
# uniform_bucket_level_access, not the nested forms the JSON output suggests.
# Getting them wrong prints an empty value, which reads like "versioning is off"
# rather than "you asked for the wrong field".
gcloud storage buckets describe "${BUCKET}" --project="${PROJECT}" \
  --format="value(name, location, versioning_enabled, uniform_bucket_level_access)" \
  | awk '{printf "name=%s location=%s versioning=%s uniform_access=%s\n", $1, $2, $3, $4}'

echo
echo "Done. Next: terraform init in environments/multi-shared, then apply."
echo "Neither root needs -var arguments; see docs/rebuilding-environments.md."
