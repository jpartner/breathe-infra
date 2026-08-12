variable "tenants" {
  description = "Map of tenant key to tenant config"
  type = map(object({
    display_name = string
    domains      = map(list(string)) # env_key → list of customer app domains
    # Hostname slug for this tenant's admin UI (admin-<slug>.<env domain>).
    # Defaults to the tenant key — set it where the two differ, as the
    # "unifeed" tenant deploys its admin UI as admin-uniten.
    admin_slug = optional(string)
    # Full admin host override per env_key — for tenants whose admin UI lives
    # on their own domain (breathe: admin.dev.breathebranding.co.uk) rather
    # than the environment's admin_domain_pattern.
    admin_hosts = optional(map(string), {})
  }))
}

variable "environments" {
  description = "Map of environment key to environment config"
  type = map(object({
    display_name = string
    api_domain   = string
    # Admin UI hostname, with "{tenant}" replaced by the tenant key. The admin
    # UI is deployed once per tenant (admin-uniten.dev.unifeed.io), so a single
    # hostname per environment cannot address it. Omit the placeholder to point
    # every tenant at one consolidated admin host.
    admin_domain_pattern = string
    ops_domain           = string
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
    { key = "admin", display_name = "Administrator", group = "staff" },
    { key = "csr", display_name = "Customer Service", group = "staff" },
    { key = "designer", display_name = "Graphic Designer", group = "staff" },
    { key = "customer", display_name = "Customer", group = "customers" },
  ]
}
