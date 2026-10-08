output "env" { value = var.env }
output "resource_group" { value = local.rg }
output "location" { value = local.location }
output "tags" { value = local.tags }

output "vnet" {
  value = {
    id           = azurerm_virtual_network.this.id
    name         = azurerm_virtual_network.this.name
    pe_subnet_id = azurerm_subnet.pe.id
  }
}

output "private_dns_zone_ids" {
  value = { for k, z in azurerm_private_dns_zone.this : k => z.id }
}

output "access_connector" {
  value = {
    id           = azurerm_databricks_access_connector.this.id
    principal_id = azurerm_databricks_access_connector.this.identity[0].principal_id
  }
}

output "uc_storage" {
  value = {
    id         = azurerm_storage_account.uc.id
    name       = azurerm_storage_account.uc.name
    dfs_host   = azurerm_storage_account.uc.primary_dfs_host
    containers = local.uc_containers
  }
}

output "key_vault" {
  value = {
    id   = azurerm_key_vault.this.id
    name = azurerm_key_vault.this.name
    uri  = azurerm_key_vault.this.vault_uri
  }
}

output "workspaces" {
  value = {
    for k, w in module.workspace : k => {
      id              = w.id
      name            = w.name
      workspace_id    = w.workspace_id
      url             = w.url
      root_storage_id = w.root_storage_id
    }
  }
}
