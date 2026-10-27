# What an engineer records on the project's page in the factory (Production → Record production).

output "resource_group" {
  value = azurerm_resource_group.production.name
}

output "registry" {
  value = azurerm_container_registry.production.name
}

output "apps" {
  description = "Each app's Container App and its address."
  value = {
    for name, app in azurerm_container_app.app : name => {
      container_app = app.name
      address       = "https://${app.ingress[0].fqdn}"
      health        = var.apps[name].health
    }
  }
}

output "migrations_job" {
  value = var.migrations == null ? null : azurerm_container_app_job.migrate[0].name
}

output "vault" {
  description = "Where the database's connection string goes, at a hidden prompt (README.md)."
  value       = azurerm_key_vault.production.name
}

output "previews_environment" {
  description = "Where the project's previews run."
  value       = azurerm_container_app_environment.previews.name
}

output "apps_identity" {
  description = "What the apps, the migrations and the previews pull images as."
  value       = azurerm_user_assigned_identity.apps.name
}
