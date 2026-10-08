output "tfstate" {
  value = {
    resource_group  = azurerm_resource_group.shared.name
    storage_account = azurerm_storage_account.tfstate.name
    container       = azurerm_storage_container.tfstate.name
  }
}

output "service_principals" {
  description = "Client-IDs (keine Secrets) je Stage und Rolle."
  value       = { for k, v in azuread_application.sp : k => v.client_id }
}

output "resource_groups" {
  value = {
    for env in var.environments : env => {
      platform = azurerm_resource_group.platform[env].name
      sources  = azurerm_resource_group.sources[env].name
    }
  }
}

output "groups" {
  value = merge(
    { for k, g in azuread_group.global : k => g.display_name },
    { for k, g in azuread_group.env : k => g.display_name },
  )
}

output "kv_admin_object_ids" {
  value = { for env in var.environments : env => [azuread_service_principal.sp["${env}-infra"].object_id, azuread_group.env["${env}-ws-admins"].object_id] }
}

output "azure_databricks_sp_object_id" {
  value = data.azuread_service_principal.azure_databricks.object_id
}
