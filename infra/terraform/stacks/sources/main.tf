# Simuliertes Fremdsystem ("Quell-Team"): Azure SQL + Source Storage.
# Wichtig: Die Passwörter sind ephemeral + write-only -> sie landen NICHT im Terraform-State.
# Das Quell-Team legt sie im Key Vault der Stage ab; Databricks liest sie nur über den Scope "kv".

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

data "azurerm_resource_group" "sources" {
  name = "rg-${var.prefix}-${var.env}-src-${var.location_short}"
}

locals {
  p                = data.terraform_remote_state.azure.outputs
  base             = "${var.prefix}-${var.env}-src-${var.location_short}"
  rg               = data.azurerm_resource_group.sources.name
  location         = local.p.location
  tags             = merge(local.p.tags, { component = "source-system" })
  sql_admin_login  = "sqladmin"
  sql_reader_login = "dbx_reader"
}

# ---------------------------------------------------------------------------
# Secrets (ephemeral, write-only)
# ---------------------------------------------------------------------------
ephemeral "random_password" "sql_admin" {
  length      = 32
  special     = true
  min_special = 2
  # Nur Zeichen, die in Connection-Strings und T-SQL unkritisch sind
  override_special = "!#%*-_=+"
}

ephemeral "random_password" "sql_reader" {
  length           = 32
  special          = true
  min_special      = 2
  override_special = "!#%*-_=+"
}

resource "azurerm_key_vault_secret" "sql" {
  for_each = {
    salesdb-admin-user = local.sql_admin_login
    salesdb-user       = local.sql_reader_login
  }
  name         = each.key
  key_vault_id = local.p.key_vault.id
  value        = each.value
  tags         = local.tags
}

resource "azurerm_key_vault_secret" "sql_admin_password" {
  name             = "salesdb-admin-password"
  key_vault_id     = local.p.key_vault.id
  value_wo         = ephemeral.random_password.sql_admin.result
  value_wo_version = var.sql_password_version
  tags             = local.tags
}

resource "azurerm_key_vault_secret" "sql_reader_password" {
  name             = "salesdb-password"
  key_vault_id     = local.p.key_vault.id
  value_wo         = ephemeral.random_password.sql_reader.result
  value_wo_version = var.sql_password_version
  tags             = local.tags
}

resource "azurerm_key_vault_secret" "sql_host" {
  name         = "salesdb-host"
  key_vault_id = local.p.key_vault.id
  value        = azurerm_mssql_server.this.fully_qualified_domain_name
  tags         = local.tags
}

# ---------------------------------------------------------------------------
# Azure SQL (Free Offer, Serverless, privat)
# ---------------------------------------------------------------------------
resource "azurerm_mssql_server" "this" {
  name                = "sql-${var.prefix}-${var.env}-gwc-${var.suffix}"
  resource_group_name = local.rg
  location            = var.sql_location
  version             = "12.0"
  minimum_tls_version = "1.2"
  # PoC: öffentlich erreichbar, aber nur für Azure-Dienste (Firewall-Regel unten). Grund: Serverless
  # erreicht die SQL in einer anderen Region (gwc) trotz ESTABLISHED NCC-PE nur öffentlich (offener Punkt).
  public_network_access_enabled = var.sql_public_access
  # Proxy statt Redirect: Bei Redirect leitet der Gateway auf einen öffentlich aufgelösten
  # Worker-Host (Port 11xxx) um -> "Deny Public Network Access". Proxy hält alles auf 1433/PE.
  connection_policy                       = "Proxy"
  administrator_login                     = local.sql_admin_login
  administrator_login_password_wo         = ephemeral.random_password.sql_admin.result
  administrator_login_password_wo_version = var.sql_password_version
  tags                                    = local.tags
}

resource "azurerm_mssql_firewall_rule" "azure_services" {
  count            = var.sql_public_access ? 1 : 0
  name             = "AllowAllWindowsAzureIps"
  server_id        = azurerm_mssql_server.this.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# azurerm kennt das Free Offer (useFreeLimit) nicht -> azapi
resource "azapi_resource" "salesdb" {
  type      = "Microsoft.Sql/servers/databases@2023-08-01"
  name      = "sqldb-salesdb"
  parent_id = azurerm_mssql_server.this.id
  location  = var.sql_location
  tags      = local.tags
  body = {
    sku = {
      name     = "GP_S_Gen5"
      tier     = "GeneralPurpose"
      family   = "Gen5"
      capacity = 2
    }
    properties = {
      useFreeLimit                = true
      freeLimitExhaustionBehavior = "AutoPause"
      autoPauseDelay              = 60
      minCapacity                 = 0.5
      maxSizeBytes                = 34359738368
    }
  }
  response_export_values = ["properties.databaseId"]
}

module "pe_sql" {
  source = "../../modules/private_endpoint"

  name                = "pe-${local.base}-sql"
  location            = local.location
  resource_group_name = local.rg
  subnet_id           = local.p.vnet.pe_subnet_id
  target_resource_id  = azurerm_mssql_server.this.id
  subresource         = "sqlServer"
  private_dns_zone_id = local.p.private_dns_zone_ids["sql"]
  tags                = local.tags
}

# ---------------------------------------------------------------------------
# Source Storage (Landing-Dateien, privat)
# ---------------------------------------------------------------------------
resource "azurerm_storage_account" "src" {
  name                            = "st${var.prefix}${var.env}src${var.suffix}"
  resource_group_name             = local.rg
  location                        = local.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  account_kind                    = "StorageV2"
  is_hns_enabled                  = true
  min_tls_version                 = "TLS1_2"
  shared_access_key_enabled       = false
  default_to_oauth_authentication = true
  allow_nested_items_to_be_public = false
  public_network_access           = "Enabled"
  network_rules {
    # Fallback, solange die NCC-Private-Endpoints für Serverless noch nicht greifen (bis zu 24 h)
    default_action = var.storage_public_fallback ? "Allow" : "Deny"
    bypass         = ["AzureServices"]
    private_link_access {
      endpoint_resource_id = local.p.access_connector.id
    }
  }
  tags = local.tags
}

resource "azurerm_storage_container" "landing" {
  name               = "landing"
  storage_account_id = azurerm_storage_account.src.id
}

module "pe_src" {
  source   = "../../modules/private_endpoint"
  for_each = toset(["dfs", "blob"])

  name                = "pe-${local.base}-st-${each.key}"
  location            = local.location
  resource_group_name = local.rg
  subnet_id           = local.p.vnet.pe_subnet_id
  target_resource_id  = azurerm_storage_account.src.id
  subresource         = each.key
  private_dns_zone_id = local.p.private_dns_zone_ids[each.key]
  tags                = local.tags
}

# Quell-Team gewährt der Plattform-Identität (Access Connector) Zugriff.
# Contributor-Rechte, weil der Seed-Job Dummy-Dateien schreibt; Queue/EventGrid für File Events.
resource "azurerm_role_assignment" "ac_src" {
  for_each = {
    blob    = { scope = azurerm_storage_account.src.id, role = "Storage Blob Data Contributor" }
    queue   = { scope = azurerm_storage_account.src.id, role = "Storage Queue Data Contributor" }
    account = { scope = azurerm_storage_account.src.id, role = "Storage Account Contributor" }
    events  = { scope = data.azurerm_resource_group.sources.id, role = "EventGrid EventSubscription Contributor" }
  }
  scope                = each.value.scope
  role_definition_name = each.value.role
  principal_id         = local.p.access_connector.principal_id
}
