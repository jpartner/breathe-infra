variable "project_id" {
  type = string
}

variable "backends" {
  description = "Map of backend name to Cloud Run service config"
  type = map(object({
    cloud_run_service = string
    region            = string
    timeout_sec       = optional(number, 300)
  }))
}

variable "host_rules" {
  description = "Map of host rules routing domains to backends"
  type = map(object({
    hosts   = list(string)
    backend = string
  }))
}

variable "default_backend" {
  description = "Name of the default backend (must be a key in backends)"
  type        = string
}

variable "domains" {
  description = "All domains that need SSL certificates"
  type        = list(string)
}
