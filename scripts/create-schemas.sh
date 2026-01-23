#!/bin/bash
# Create database schemas for all environments
# Run this from Cloud Shell or a machine with VPC access

set -e

PROJECT="breathe-shared"
INSTANCE="breathe-db"
USER="postgres"
APP_USER="breathe_app"
SCHEMA="app"

DATABASES=("breathe_dev" "breathe_staging" "breathe_prod")

SQL=$(cat <<EOF
CREATE SCHEMA IF NOT EXISTS ${SCHEMA};
GRANT ALL ON SCHEMA ${SCHEMA} TO ${APP_USER};
GRANT USAGE ON SCHEMA ${SCHEMA} TO ${APP_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA ${SCHEMA} GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON TABLES TO ${APP_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA ${SCHEMA} GRANT SELECT, UPDATE, USAGE ON SEQUENCES TO ${APP_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA ${SCHEMA} GRANT EXECUTE ON FUNCTIONS TO ${APP_USER};
EOF
)

echo "Creating '${SCHEMA}' schema in all databases..."
echo ""

for DB in "${DATABASES[@]}"; do
    echo "=== Creating schema in ${DB} ==="
    gcloud sql connect ${INSTANCE} \
        --user=${USER} \
        --project=${PROJECT} \
        --database=${DB} \
        --quiet <<< "${SQL}"
    echo "Done: ${DB}"
    echo ""
done

echo "All schemas created successfully!"
echo ""
echo "Verify with:"
echo "  gcloud sql connect ${INSTANCE} --user=${USER} --project=${PROJECT} --database=breathe_dev"
echo "  \\dn"
