output "org_ids" {
  description = "Map of tenant key to Zitadel organization ID"
  value       = { for k, org in zitadel_org.tenants : k => org.id }
}

output "project_ids" {
  description = "Map of tenant-env key to Zitadel project ID"
  value       = { for k, proj in zitadel_project.envs : k => proj.id }
}

output "admin_client_ids" {
  description = "Map of tenant-env key to Admin UI OIDC client ID"
  value       = { for k, app in zitadel_application_oidc.admin : k => app.client_id }
}

output "customer_client_ids" {
  description = "Map of tenant-env key to Customer App OIDC client ID"
  value       = { for k, app in zitadel_application_oidc.customer : k => app.client_id }
}
