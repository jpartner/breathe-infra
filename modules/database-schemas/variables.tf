variable "databases" {
  description = "List of database names to create schemas in"
  type        = list(string)
}

variable "schemas" {
  description = "List of schema names to create in each database"
  type        = list(string)
  default     = ["app"]
}

variable "schema_owner" {
  description = "Owner role for the schemas (usually postgres or the admin user)"
  type        = string
  default     = "postgres"
}

variable "app_user" {
  description = "Application user to grant schema access to"
  type        = string
}
