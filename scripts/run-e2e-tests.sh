#!/bin/bash
# Run E2E tests against a deployed environment
#
# Usage:
#   ./scripts/run-e2e-tests.sh <environment> [commit_sha]
#
# Examples:
#   ./scripts/run-e2e-tests.sh dev
#   ./scripts/run-e2e-tests.sh staging abc123def456
#
# If commit_sha is not provided, it will be extracted from the currently
# deployed Cloud Run service.
#
# Slack notifications are sent to the deployments channel using config
# from the environment's config.json in GCS.

set -e

ENVIRONMENT="${1:-}"
COMMIT_SHA="${2:-}"

if [ -z "$ENVIRONMENT" ]; then
  echo "Usage: $0 <environment> [commit_sha]"
  echo "  environment: dev, staging (not production)"
  echo "  commit_sha: optional, defaults to currently deployed version"
  exit 1
fi

# Validate environment
if [ "$ENVIRONMENT" != "dev" ] && [ "$ENVIRONMENT" != "staging" ]; then
  echo "Error: Environment must be 'dev' or 'staging' (not production)"
  exit 1
fi

# Set project ID and config bucket based on environment
case "$ENVIRONMENT" in
  dev)
    PROJECT_ID="breathe-dev-env"
    CONFIG_BUCKET="breathe-dev-config"
    ;;
  staging)
    PROJECT_ID="breathe-staging-env"
    CONFIG_BUCKET="breathe-staging-config"
    ;;
esac

REGION="europe-west2"

echo "Fetching ecommerce service details from ${ENVIRONMENT}..."

# Get the service URL
ECOMMERCE_URL=$(gcloud run services describe breathe-ecommerce \
  --project="${PROJECT_ID}" \
  --region="${REGION}" \
  --format="value(status.url)")

if [ -z "$ECOMMERCE_URL" ]; then
  echo "Error: Could not get ecommerce service URL"
  exit 1
fi

echo "Ecommerce URL: ${ECOMMERCE_URL}"

# Get the commit SHA from the deployed image if not provided
if [ -z "$COMMIT_SHA" ]; then
  IMAGE=$(gcloud run services describe breathe-ecommerce \
    --project="${PROJECT_ID}" \
    --region="${REGION}" \
    --format="value(spec.template.spec.containers[0].image)")

  # Extract tag from image (format: .../breathe-ecommerce:COMMIT_SHA)
  COMMIT_SHA=$(echo "$IMAGE" | sed 's/.*://')

  if [ -z "$COMMIT_SHA" ] || [ "$COMMIT_SHA" = "latest" ]; then
    echo "Error: Could not extract commit SHA from image tag"
    echo "Image: ${IMAGE}"
    exit 1
  fi
fi

echo "Commit SHA: ${COMMIT_SHA}"
echo "Config bucket: ${CONFIG_BUCKET}"
echo ""
echo "Starting E2E tests..."
echo "========================================"

# Run the trigger with the specified commit
gcloud builds triggers run e2e-tests-manual \
  --project="breathe-shared" \
  --region="europe-west2" \
  --sha="${COMMIT_SHA}" \
  --substitutions="_ENVIRONMENT=${ENVIRONMENT},_ECOMMERCE_URL=${ECOMMERCE_URL},_CONFIG_BUCKET=${CONFIG_BUCKET}"

echo ""
echo "Build triggered. View progress at:"
echo "https://console.cloud.google.com/cloud-build/builds?project=breathe-shared&region=europe-west2"
