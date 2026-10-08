output "ncc_id" { value = databricks_mws_network_connectivity_config.this.network_connectivity_config_id }
output "catalogs" { value = [for c in databricks_catalog.layer : c.name] }
output "workspace_urls" { value = local.ws_urls }
output "warehouse_id" { value = databricks_sql_endpoint.ws1.id }
output "landing_volume" { value = "/Volumes/${databricks_volume.landing.catalog_name}/${databricks_volume.landing.schema_name}/${databricks_volume.landing.name}" }
