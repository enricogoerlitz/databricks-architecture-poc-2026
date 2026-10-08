output "metastore" {
  value = {
    id     = local.metastore.metastore_id
    name   = local.metastore.name
    region = local.metastore.region
    owner  = local.metastore.owner
  }
}

output "groups" {
  value = {
    metastore_admins = databricks_group.metastore_admins.display_name
    deploy_sps       = databricks_group.deploy_sps.display_name
  }
}
