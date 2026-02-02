#!/bin/bash
# Blue-green deployment with E2E test validation
#
# This script deploys a new version WITHOUT serving traffic, runs E2E tests
# against it, and only switches traffic if tests pass.
#
# Usage:
#   ./scripts/deploy-with-tests.sh <environment> <commit_sha>
#
# Examples:
#   ./scripts/deploy-with-tests.sh staging abc123def456
#   ./scripts/deploy-with-tests.sh dev $(git rev-parse HEAD)
#
# The deployment will:
# 1. Deploy new revision with --no-traffic
# 2. Run E2E tests against the new revision's tagged URL
# 3. If tests pass: switch 100% traffic to new revision
# 4. If tests fail: keep traffic on old revision (safe rollback)

set -e

ENVIRONMENT="${1:-}"
COMMIT_SHA="${2:-}"

if [ -z "$ENVIRONMENT" ] || [ -z "$COMMIT_SHA" ]; then
  echo "Usage: $0 <environment> <commit_sha>"
  echo ""
  echo "  environment: dev, staging"
  echo "  commit_sha:  Git commit SHA to deploy"
  echo ""
  echo "Examples:"
  echo "  $0 staging abc123def456"
  echo "  $0 dev \$(git rev-parse HEAD)"
  exit 1
fi

# Validate environment
if [ "$ENVIRONMENT" != "dev" ] && [ "$ENVIRONMENT" != "staging" ]; then
  echo "Error: Environment must be 'dev' or 'staging'"
  echo ""
  echo "Production deployments should be done through a separate"
  echo "controlled process with additional approval gates."
  exit 1
fi

# Validate commit SHA format
if ! [[ "$COMMIT_SHA" =~ ^[a-f0-9]{7,40}$ ]]; then
  echo "Error: Invalid commit SHA format: $COMMIT_SHA"
  exit 1
fi

echo "=============================================="
echo "Blue-Green Deployment with E2E Tests"
echo "=============================================="
echo ""
echo "Environment:  $ENVIRONMENT"
echo "Commit:       $COMMIT_SHA"
echo ""
echo "This will:"
echo "  1. Deploy new revision (no traffic)"
echo "  2. Run E2E tests against new revision"
echo "  3. Switch traffic only if tests pass"
echo ""
echo "Starting deployment..."
echo ""

# Run the trigger with the specified commit
gcloud builds triggers run deploy-with-tests \
  --project="breathe-shared" \
  --region="europe-west2" \
  --sha="${COMMIT_SHA}" \
  --substitutions="_ENVIRONMENT=${ENVIRONMENT}"

echo ""
echo "Build triggered. View progress at:"
echo "https://console.cloud.google.com/cloud-build/builds?project=breathe-shared&region=europe-west2"
echo ""
echo "You'll receive a Slack notification when the deployment completes."
