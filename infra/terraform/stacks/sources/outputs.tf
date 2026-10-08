output "sql" {
  value = {
    server_id = azurerm_mssql_server.this.id
    host      = azurerm_mssql_server.this.fully_qualified_domain_name
    database  = azapi_resource.salesdb.name
  }
}

output "src_storage" {
  value = {
    id       = azurerm_storage_account.src.id
    name     = azurerm_storage_account.src.name
    dfs_host = azurerm_storage_account.src.primary_dfs_host
  }
}
