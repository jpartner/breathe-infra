output "schemas" {
  description = "Map of created schemas by database"
  value = {
    for item in local.schema_database_pairs : item.database => item.schema...
  }
}

output "schema_names" {
  description = "List of all schema names created"
  value       = var.schemas
}
