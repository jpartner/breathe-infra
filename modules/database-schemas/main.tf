# Database Schema Management
# Creates PostgreSQL schemas within Cloud SQL databases
#
# Note: This module requires Cloud SQL Proxy to be running or Terraform to be
# executed from within the VPC with access to the Cloud SQL private IP.

terraform {
  required_providers {
    postgresql = {
      source  = "cyrilgdn/postgresql"
      version = "~> 1.22"
    }
  }
}

# Create schemas in each database
resource "postgresql_schema" "schemas" {
  for_each = { for item in local.schema_database_pairs : "${item.database}-${item.schema}" => item }

  database = each.value.database
  name     = each.value.schema
  owner    = var.schema_owner

  # Ensure the app user can use the schema
  policy {
    usage = true
    role  = var.app_user
  }

  policy {
    create = true
    role   = var.app_user
  }
}

locals {
  # Create a flat list of database-schema pairs
  schema_database_pairs = flatten([
    for db in var.databases : [
      for schema in var.schemas : {
        database = db
        schema   = schema
      }
    ]
  ])
}

# Grant privileges to app user on each schema
resource "postgresql_grant" "schema_usage" {
  for_each = { for item in local.schema_database_pairs : "${item.database}-${item.schema}" => item }

  database    = each.value.database
  schema      = each.value.schema
  role        = var.app_user
  object_type = "schema"
  privileges  = ["CREATE", "USAGE"]

  depends_on = [postgresql_schema.schemas]
}

# Grant default privileges so app user owns objects it creates
resource "postgresql_default_privileges" "tables" {
  for_each = { for item in local.schema_database_pairs : "${item.database}-${item.schema}" => item }

  database    = each.value.database
  schema      = each.value.schema
  role        = var.app_user
  owner       = var.schema_owner
  object_type = "table"
  privileges  = ["SELECT", "INSERT", "UPDATE", "DELETE", "TRUNCATE", "REFERENCES", "TRIGGER"]

  depends_on = [postgresql_schema.schemas]
}

resource "postgresql_default_privileges" "sequences" {
  for_each = { for item in local.schema_database_pairs : "${item.database}-${item.schema}" => item }

  database    = each.value.database
  schema      = each.value.schema
  role        = var.app_user
  owner       = var.schema_owner
  object_type = "sequence"
  privileges  = ["SELECT", "UPDATE", "USAGE"]

  depends_on = [postgresql_schema.schemas]
}
