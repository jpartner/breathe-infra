#!/usr/bin/env bash
#
# Report which Terraform-managed secrets have no value.
#
# Every secret in breathe-shared is declared, but Terraform owns the *values* of
# only some of them. The 25 adopted secrets are managed as containers only —
# their values are supplied by hand, deliberately, so that supplier and vendor
# credentials never land in the state file.
#
# The consequence is that a rebuild produces the full set of secrets with
# nothing in them, and the failures that follow are indirect: a service starts,
# then 401s against a supplier API. This script turns that into a list you can
# work through, rather than a discovery you make one incident at a time.
#
#   ./scripts/check-secret-values.sh [PROJECT]

set -euo pipefail

PROJECT="${1:-breathe-shared}"

missing=0
total=0

while read -r secret; do
  [ -z "${secret}" ] && continue
  total=$((total + 1))
  versions=$(gcloud secrets versions list "${secret}" --project="${PROJECT}" \
    --filter="state=enabled" --format="value(name)" 2>/dev/null | wc -l | tr -d ' ')
  if [ "${versions}" = "0" ]; then
    printf '  EMPTY  %s\n' "${secret}"
    missing=$((missing + 1))
  fi
done < <(gcloud secrets list --project="${PROJECT}" --format="value(name)" 2>/dev/null)

echo
if [ "${missing}" = "0" ]; then
  echo "All ${total} secrets in ${PROJECT} have at least one enabled version."
else
  echo "${missing} of ${total} secrets have no enabled version."
  echo
  echo "Supply each with:"
  echo "  printf %s \"\$VALUE\" | gcloud secrets versions add SECRET --project=${PROJECT} --data-file=-"
  echo
  echo "Supplier API keys cannot be regenerated — they come from the supplier."
  echo "See docs/rebuilding-environments.md."
  exit 1
fi
