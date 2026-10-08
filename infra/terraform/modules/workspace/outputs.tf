output "id" { value = azurerm_databricks_workspace.this.id }
output "name" { value = azurerm_databricks_workspace.this.name }
output "workspace_id" { value = azurerm_databricks_workspace.this.workspace_id }
output "url" { value = "https://${azurerm_databricks_workspace.this.workspace_url}" }
output "root_storage_id" { value = local.root_storage_id }
output "managed_resource_group" { value = local.managed_rg_name }
