data "terraform_remote_state" "azure" {
  backend = "azurerm"
  config = {
    resource_group_name  = var.tfstate_resource_group
    storage_account_name = var.tfstate_storage_account
    container_name       = "tfstate"
    key                  = "${var.env}/azure.tfstate"
    use_azuread_auth     = true
    subscription_id      = var.subscription_id
  }
}

data "terraform_remote_state" "sources" {
  backend = "azurerm"
  config = {
    resource_group_name  = var.tfstate_resource_group
    storage_account_name = var.tfstate_storage_account
    container_name       = "tfstate"
    key                  = "${var.env}/sources.tfstate"
    use_azuread_auth     = true
    subscription_id      = var.subscription_id
  }
}

locals {
  p   = data.terraform_remote_state.azure.outputs
  src = data.terraform_remote_state.sources.outputs
  env = var.env

  ws_keys = sort(keys(local.p.workspaces))
  ws_urls = [for k in local.ws_keys : local.p.workspaces[k].url]
  ws_ids  = [for k in local.ws_keys : tonumber(local.p.workspaces[k].workspace_id)]
  has_ws2 = length(local.ws_keys) > 1

  layers = ["bronze", "silver", "gold", "platform"]

  # Zweiter Workspace (Analytics) liest Bronze/Silver nur, schreibt Gold/Platform.
  ws2_binding = {
    bronze   = "BINDING_TYPE_READ_ONLY"
    silver   = "BINDING_TYPE_READ_ONLY"
    gold     = "BINDING_TYPE_READ_WRITE"
    platform = "BINDING_TYPE_READ_WRITE"
  }

  deploy_sp = var.deploy_sp_client_id

  # NCC-Private-Endpoint-Ziele (Serverless -> private Ressourcen)
  ncc_targets = {
    uc-dfs   = { resource_id = local.p.uc_storage.id, group_id = "dfs" }
    uc-blob  = { resource_id = local.p.uc_storage.id, group_id = "blob" }
    src-dfs  = { resource_id = local.src.src_storage.id, group_id = "dfs" }
    src-blob = { resource_id = local.src.src_storage.id, group_id = "blob" }
    sql      = { resource_id = local.src.sql.server_id, group_id = "sqlServer" }
  }
}

# ---------------------------------------------------------------------------
# Metastore-Zuweisung (ein Metastore je Region; Auto-Zuweisung nicht vorausgesetzt)
# ---------------------------------------------------------------------------
data "databricks_metastores" "all" {
  provider = databricks.account
}

data "databricks_metastore" "candidates" {
  provider     = databricks.account
  for_each     = data.databricks_metastores.all.ids
  metastore_id = each.value
}

locals {
  metastore_id = one([for m in data.databricks_metastore.candidates : m.metastore_id if m.metastore_info[0].region == local.p.location])
}

resource "databricks_metastore_assignment" "this" {
  provider     = databricks.account
  for_each     = toset([for id in local.ws_ids : tostring(id)])
  workspace_id = tonumber(each.key)
  metastore_id = local.metastore_id
}

# ---------------------------------------------------------------------------
# Serverless-Netzwerk: NCC je Stage + Private Endpoints
# ---------------------------------------------------------------------------
resource "databricks_mws_network_connectivity_config" "this" {
  provider = databricks.account
  name     = "ncc-${var.prefix}-${local.env}-${var.location_short}"
  region   = local.p.location
}

resource "databricks_mws_ncc_binding" "this" {
  provider                       = databricks.account
  for_each                       = toset([for id in local.ws_ids : tostring(id)])
  network_connectivity_config_id = databricks_mws_network_connectivity_config.this.network_connectivity_config_id
  workspace_id                   = tonumber(each.key)
}

resource "databricks_mws_ncc_private_endpoint_rule" "this" {
  provider                       = databricks.account
  for_each                       = local.ncc_targets
  network_connectivity_config_id = databricks_mws_network_connectivity_config.this.network_connectivity_config_id
  resource_id                    = each.value.resource_id
  group_id                       = each.value.group_id
}

# Databricks legt die PEs in seinem Serverless-Netz an; die Verbindung muss auf der
# Zielressource freigegeben werden. azurerm kann das nicht -> Azure CLI.
resource "terraform_data" "approve_ncc_pe" {
  for_each         = toset(distinct([for t in local.ncc_targets : t.resource_id]))
  triggers_replace = [for k, r in databricks_mws_ncc_private_endpoint_rule.this : r.rule_id if local.ncc_targets[k].resource_id == each.key]

  provisioner "local-exec" {
    command     = "${path.module}/../../../scripts/approve-private-endpoints.sh '${each.key}' ${length([for t in local.ncc_targets : t if t.resource_id == each.key])}"
    interpreter = ["bash", "-c"]
  }
}

# ---------------------------------------------------------------------------
# Identitäten im Workspace
# ---------------------------------------------------------------------------
resource "databricks_service_principal" "deploy_ws1" {
  depends_on            = [databricks_metastore_assignment.this]
  provider              = databricks.ws1
  application_id        = local.deploy_sp
  display_name          = "sp-${var.prefix}-${local.env}-deploy"
  workspace_access      = true
  databricks_sql_access = true
}

resource "databricks_service_principal" "deploy_ws2" {
  provider              = databricks.ws2
  count                 = local.has_ws2 ? 1 : 0
  application_id        = local.deploy_sp
  display_name          = "sp-${var.prefix}-${local.env}-deploy"
  workspace_access      = true
  databricks_sql_access = true
}

# Rollen-Gruppen der Stage in die Workspaces holen (Workspace-Zugriff)
data "databricks_group" "role" {
  provider     = databricks.account
  for_each     = var.group_grants_enabled ? toset(["ws-admins", "engineers", "analysts"]) : toset([])
  display_name = "sg-${var.prefix}-${local.env}-${each.key}"
}

resource "databricks_mws_permission_assignment" "role" {
  provider = databricks.account
  for_each = {
    for pair in setproduct(keys(data.databricks_group.role), [for id in local.ws_ids : tostring(id)]) :
    "${pair[0]}-${pair[1]}" => { kind = pair[0], ws = pair[1] }
  }
  workspace_id = tonumber(each.value.ws)
  principal_id = data.databricks_group.role[each.value.kind].id
  permissions  = each.value.kind == "ws-admins" ? ["ADMIN"] : ["USER"]
  depends_on   = [databricks_metastore_assignment.this]
}

# ---------------------------------------------------------------------------
# Unity Catalog: Credential, External Locations, Catalogs (metastore-weit, über ws1)
# ---------------------------------------------------------------------------
resource "databricks_storage_credential" "uc" {
  provider       = databricks.ws1
  depends_on     = [databricks_metastore_assignment.this]
  name           = "sc_${local.env}_uc"
  comment        = "Access Connector der Stage ${local.env}"
  isolation_mode = "ISOLATION_MODE_ISOLATED"
  force_destroy  = true
  azure_managed_identity {
    access_connector_id = local.p.access_connector.id
  }
}

resource "databricks_external_location" "layer" {
  provider        = databricks.ws1
  for_each        = toset(local.layers)
  name            = "el_${local.env}_${each.key}"
  url             = "abfss://${each.key}@${local.p.uc_storage.dfs_host}/"
  credential_name = databricks_storage_credential.uc.name
  isolation_mode  = "ISOLATION_MODE_ISOLATED"
  force_destroy   = true
  comment         = "Managed Location für ${local.env}_${each.key}"

  depends_on = [terraform_data.approve_ncc_pe]
}

resource "databricks_external_location" "landing" {
  provider           = databricks.ws1
  name               = "el_${local.env}_landing"
  url                = "abfss://landing@${local.src.src_storage.dfs_host}/"
  credential_name    = databricks_storage_credential.uc.name
  isolation_mode     = "ISOLATION_MODE_ISOLATED"
  force_destroy      = true
  comment            = "Source Storage (Fremdsystem) – Landing-Dateien"
  enable_file_events = var.enable_file_events

  dynamic "file_event_queue" {
    for_each = var.enable_file_events ? [1] : []
    content {
      managed_aqs {
        resource_group  = "rg-${var.prefix}-${local.env}-src-${var.location_short}"
        subscription_id = var.subscription_id
      }
    }
  }

  depends_on = [terraform_data.approve_ncc_pe]
}

resource "databricks_catalog" "layer" {
  provider       = databricks.ws1
  for_each       = toset(local.layers)
  name           = "${local.env}_${each.key}"
  storage_root   = databricks_external_location.layer[each.key].url
  isolation_mode = "ISOLATED"
  force_destroy  = true
  comment        = "Stage ${local.env}, Layer ${each.key}. Managed by Terraform."
  properties = {
    env   = local.env
    layer = each.key
  }
}

# Bindings: Credential + Locations nur an ws1; Catalogs an alle Workspaces der Stage
resource "databricks_workspace_binding" "credential" {
  provider       = databricks.ws1
  securable_type = "storage_credential"
  securable_name = databricks_storage_credential.uc.name
  workspace_id   = local.ws_ids[0]
}

resource "databricks_workspace_binding" "location" {
  provider       = databricks.ws1
  for_each       = merge({ for l in local.layers : l => databricks_external_location.layer[l].name }, { landing = databricks_external_location.landing.name })
  securable_type = "external_location"
  securable_name = each.value
  workspace_id   = local.ws_ids[0]
}

resource "databricks_workspace_binding" "catalog_ws1" {
  provider       = databricks.ws1
  for_each       = databricks_catalog.layer
  securable_type = "catalog"
  securable_name = each.value.name
  workspace_id   = local.ws_ids[0]
  binding_type   = "BINDING_TYPE_READ_WRITE"
}

resource "databricks_workspace_binding" "catalog_ws2" {
  provider       = databricks.ws1
  for_each       = local.has_ws2 ? databricks_catalog.layer : {}
  securable_type = "catalog"
  securable_name = each.value.name
  workspace_id   = local.ws_ids[1]
  binding_type   = local.ws2_binding[each.key]
}

# Landing-Volume (Zero-Copy auf den Source Storage)
resource "databricks_schema" "landing" {
  provider      = databricks.ws1
  catalog_name  = databricks_catalog.layer["bronze"].name
  name          = "landing"
  comment       = "External Volumes auf Quell-Storage (Zero-Copy)"
  force_destroy = true
}

resource "databricks_volume" "landing" {
  provider         = databricks.ws1
  catalog_name     = databricks_catalog.layer["bronze"].name
  schema_name      = databricks_schema.landing.name
  name             = "files"
  volume_type      = "EXTERNAL"
  storage_location = databricks_external_location.landing.url
  comment          = "Landing-Dateien des Quellsystems"
}

# ---------------------------------------------------------------------------
# Grants
# ---------------------------------------------------------------------------
data "databricks_current_metastore" "this" {
  provider   = databricks.ws1
  depends_on = [databricks_metastore_assignment.this]
}

# Deploy-SP besitzt die Workloads der Stage.
resource "databricks_grants" "catalog" {
  provider   = databricks.ws1
  for_each   = databricks_catalog.layer
  catalog    = each.value.name
  depends_on = [databricks_mws_permission_assignment.role]

  grant {
    principal  = local.deploy_sp
    privileges = ["ALL_PRIVILEGES", "MANAGE"]
  }

  dynamic "grant" {
    for_each = var.group_grants_enabled ? [1] : []
    content {
      principal  = "sg-${var.prefix}-${local.env}-engineers"
      privileges = local.env == "dev" ? ["ALL_PRIVILEGES"] : ["USE_CATALOG", "USE_SCHEMA", "SELECT", "BROWSE"]
    }
  }

  dynamic "grant" {
    for_each = var.group_grants_enabled && each.key == "gold" ? [1] : []
    content {
      principal  = "sg-${var.prefix}-${local.env}-analysts"
      privileges = ["USE_CATALOG", "USE_SCHEMA", "SELECT"]
    }
  }
}

resource "databricks_grants" "landing_location" {
  provider          = databricks.ws1
  external_location = databricks_external_location.landing.name
  grant {
    principal  = local.deploy_sp
    privileges = ["READ_FILES", "WRITE_FILES"]
  }
}

# Connection + Foreign Catalog legt der Setup-Job (Deploy-SP) per SQL an, damit das Passwort
# nie im Terraform-State landet.
resource "databricks_grants" "metastore" {
  provider  = databricks.ws1
  metastore = data.databricks_current_metastore.this.id
  grant {
    principal  = local.deploy_sp
    privileges = ["CREATE_CONNECTION", "CREATE_CATALOG"]
  }
}

# ---------------------------------------------------------------------------
# Secret Scope "kv" (Key-Vault-backed) – gleicher Name in jedem Workspace
# ---------------------------------------------------------------------------
resource "databricks_secret_scope" "kv_ws1" {
  depends_on = [databricks_metastore_assignment.this]
  provider   = databricks.ws1
  name       = "kv"
  keyvault_metadata {
    resource_id = local.p.key_vault.id
    dns_name    = local.p.key_vault.uri
  }
}

resource "databricks_secret_acl" "kv_ws1" {
  provider   = databricks.ws1
  scope      = databricks_secret_scope.kv_ws1.name
  principal  = local.deploy_sp
  permission = "READ"
}

resource "databricks_secret_scope" "kv_ws2" {
  provider = databricks.ws2
  count    = local.has_ws2 ? 1 : 0
  name     = "kv"
  keyvault_metadata {
    resource_id = local.p.key_vault.id
    dns_name    = local.p.key_vault.uri
  }
}

resource "databricks_secret_acl" "kv_ws2" {
  provider   = databricks.ws2
  count      = local.has_ws2 ? 1 : 0
  scope      = databricks_secret_scope.kv_ws2[0].name
  principal  = local.deploy_sp
  permission = "READ"
}

# ---------------------------------------------------------------------------
# Serverless SQL Warehouse (kleinste Größe, schneller Auto-Stop)
# ---------------------------------------------------------------------------
resource "databricks_sql_endpoint" "ws1" {
  depends_on                = [databricks_metastore_assignment.this]
  provider                  = databricks.ws1
  name                      = "wh-${local.env}-serverless"
  cluster_size              = "2X-Small"
  max_num_clusters          = 1
  auto_stop_mins            = 5
  enable_serverless_compute = true
  warehouse_type            = "PRO"
  tags {
    custom_tags {
      key   = "project"
      value = var.prefix
    }
    custom_tags {
      key   = "env"
      value = local.env
    }
  }
}

resource "databricks_permissions" "wh_ws1" {
  provider        = databricks.ws1
  sql_endpoint_id = databricks_sql_endpoint.ws1.id
  access_control {
    service_principal_name = local.deploy_sp
    permission_level       = "CAN_MANAGE"
  }
}

# ---------------------------------------------------------------------------
# Metastore-weit, nur einmal (Stage dev): System-Schemas + Lesezugriff für alle Deploy-SPs
# ---------------------------------------------------------------------------
resource "databricks_system_schema" "this" {
  provider   = databricks.ws1
  for_each   = local.env == "dev" ? toset(["access", "compute", "lakeflow", "query"]) : toset([])
  schema     = each.key
  depends_on = [databricks_metastore_assignment.this]
}

resource "databricks_grants" "system_catalog" {
  provider = databricks.ws1
  count    = local.env == "dev" ? 1 : 0
  catalog  = "system"
  grant {
    principal  = "${var.prefix}-deploy-sps"
    privileges = ["USE_CATALOG"]
  }
  depends_on = [databricks_metastore_assignment.this]
}

resource "databricks_grants" "system_schema" {
  provider = databricks.ws1
  for_each = local.env == "dev" ? toset(["billing", "lakeflow", "access"]) : toset([])
  schema   = "system.${each.key}"
  grant {
    principal  = "${var.prefix}-deploy-sps"
    privileges = ["USE_SCHEMA", "SELECT"]
  }
  depends_on = [databricks_system_schema.this]
}

# ---------------------------------------------------------------------------
# Wer darf Jobs mit run_as = Deploy-SP anlegen? Die CI (der SP selbst) und die Plattform-Admins
# (Break-Glass/lokales Deploy). Ohne diese Rolle: "must have servicePrincipal.user role".
# ---------------------------------------------------------------------------
resource "databricks_access_control_rule_set" "deploy_sp" {
  provider = databricks.account
  name     = "accounts/${var.databricks_account_id}/servicePrincipals/${local.deploy_sp}/ruleSets/default"

  grant_rules {
    principals = ["groups/${var.prefix}-metastore-admins"]
    role       = "roles/servicePrincipal.user"
  }
  grant_rules {
    principals = ["groups/${var.prefix}-metastore-admins"]
    role       = "roles/servicePrincipal.manager"
  }
}
