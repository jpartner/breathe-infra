#!/bin/bash
# Setup secrets required for E2E test Cloud Build job
#
# This script creates the Slack bot token secret in the shared project
# and grants Cloud Build access to it.
#
# The bot token is the same one used by the ecommerce service for order notifications.
# Channel IDs:
#   - Staging: C07TGMGH3AA (default)
#   - Production: C09403US7FH

set -e

PROJECT_ID="breathe-shared"

echo "Setting up E2E test secrets in ${PROJECT_ID}..."
echo ""

# Create slack-bot-token secret if it doesn't exist
if gcloud secrets describe slack-bot-token --project="$PROJECT_ID" &>/dev/null; then
  echo "✓ Secret 'slack-bot-token' already exists"
else
  echo "Creating secret 'slack-bot-token'..."
  gcloud secrets create slack-bot-token \
    --project="$PROJECT_ID" \
    --replication-policy="automatic" \
    --labels="purpose=notifications,managed_by=script"
  echo "✓ Created secret 'slack-bot-token'"
fi

echo ""
echo "Granting Cloud Build service account access to secret..."

# Get the Cloud Build service account
CB_SA=$(gcloud projects describe "$PROJECT_ID" --format="value(projectNumber)")@cloudbuild.gserviceaccount.com

gcloud secrets add-iam-policy-binding slack-bot-token \
  --project="$PROJECT_ID" \
  --member="serviceAccount:${CB_SA}" \
  --role="roles/secretmanager.secretAccessor" \
  --quiet

echo "✓ Granted access to Cloud Build service account"

echo ""
echo "Setup complete!"
echo ""
echo "Next steps:"
echo ""
echo "1. Add the existing Slack bot token to Secret Manager:"
echo "   (This is the same token used by ecommerce for order notifications)"
echo ""
echo "   echo -n 'xoxb-YOUR-BOT-TOKEN' | \\"
echo "     gcloud secrets versions add slack-bot-token --project=${PROJECT_ID} --data-file=-"
echo ""
echo "2. Test the setup:"
echo "   ./scripts/run-e2e-tests.sh dev"
echo ""
echo "Channel IDs for reference:"
echo "  - Staging notifications: C07TGMGH3AA"
echo "  - Production notifications: C09403US7FH"
