variable "tenants" {
  description = "Map of tenant key to tenant config"
  type = map(object({
    display_name = string
    domains      = map(list(string)) # env_key → list of customer app domains
  }))
}

variable "environments" {
  description = "Map of environment key to environment config"
  type = map(object({
    display_name = string
    api_domain   = string
    admin_domain = string
  }))
}

variable "roles" {
  description = "Project roles to create in every project"
  type = list(object({
    key          = string
    display_name = string
    group        = string
  }))
  default = [
    { key = "admin",    display_name = "Administrator",          group = "staff" },
    { key = "csr",      display_name = "Customer Service",       group = "staff" },
    { key = "customer", display_name = "Customer",               group = "customers" },
  ]
}
