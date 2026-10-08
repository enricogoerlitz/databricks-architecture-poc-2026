# Kein azuread-Provider: Die CI-Identitäten haben bewusst keine Microsoft-Graph-Rechte.
# Objekt-IDs (AzureDatabricks-App, Key-Vault-Admins) kommen als Variablen (Bootstrap -> GitHub-Secrets).
data "azurerm_client_config" "current" {}

data "azurerm_resource_group" "platform" {
  name = "rg-${var.prefix}-${var.env}-${var.location_short}"
}

locals {
  base = "${var.prefix}-${var.env}-${var.location_short}"
  tags = merge({
    project     = var.prefix
    env         = var.env
    owner       = "enrico-goerlitz"
    cost-center = "poc"
    managed-by  = "terraform"
    repo        = "databricks-architecture-poc-2026"
  }, var.tags)
  rg        = data.azurerm_resource_group.platform.name
  vnet_cidr = var.vnet_cidrs[var.env]
  location  = var.location

  # /22 -> /26-Blöcke: Workspace i belegt host=2i, container=2i+1; PE-Subnet = /27 am Ende
  ws = {
    for i, idx in var.workspace_indexes[var.env] : idx => {
      host_cidr      = cidrsubnet(local.vnet_cidr, 4, 2 * i)
      container_cidr = cidrsubnet(local.vnet_cidr, 4, 2 * i + 1)
    }
  }
  pe_cidr = cidrsubnet(local.vnet_cidr, 5, 31)

  dns_zones = {
    dfs   = "privatelink.dfs.core.windows.net"
    blob  = "privatelink.blob.core.windows.net"
    sql   = "privatelink.database.windows.net"
    vault = "privatelink.vaultcore.azure.net"
  }

  uc_containers = ["bronze", "silver", "gold", "platform"]
}

# ---------------------------------------------------------------------------
# Netzwerk
# ---------------------------------------------------------------------------
resource "azurerm_virtual_network" "this" {
  name                = "vnet-${local.base}"
  location            = local.location
  resource_group_name = local.rg
  address_space       = [local.vnet_cidr]
  tags                = local.tags
}

resource "azurerm_subnet" "pe" {
  name                            = "snet-pe"
  resource_group_name             = local.rg
  virtual_network_name            = azurerm_virtual_network.this.name
  address_prefixes                = [local.pe_cidr]
  default_outbound_access_enabled = false
}

resource "azurerm_public_ip" "nat" {
  name                = "pip-ng-${local.base}"
  location            = local.location
  resource_group_name = local.rg
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

resource "azurerm_nat_gateway" "this" {
  name                = "ng-${local.base}"
  location            = local.location
  resource_group_name = local.rg
  sku_name            = "Standard"
  tags                = local.tags
}

resource "azurerm_nat_gateway_public_ip_association" "this" {
  nat_gateway_id       = azurerm_nat_gateway.this.id
  public_ip_address_id = azurerm_public_ip.nat.id
}

resource "azurerm_private_dns_zone" "this" {
  for_each            = local.dns_zones
  name                = each.value
  resource_group_name = local.rg
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  for_each            = local.dns_zones
  name                = "link-${azurerm_virtual_network.this.name}"
  private_dns_zone_id = azurerm_private_dns_zone.this[each.key].id
  virtual_network_id  = azurerm_virtual_network.this.id
  tags                = local.tags
}

# ---------------------------------------------------------------------------
# Access Connector (Managed Identity für Unity Catalog + Workspace Storage Firewall)
# ---------------------------------------------------------------------------
resource "azurerm_databricks_access_connector" "this" {
  name                = "dbac-${local.base}"
  location            = local.location
  resource_group_name = local.rg
  tags                = local.tags
  identity {
    type = "SystemAssigned"
  }
}

# ---------------------------------------------------------------------------
# Unity-Catalog-Storage (privat)
# ---------------------------------------------------------------------------
resource "azurerm_storage_account" "uc" {
  name                            = "st${var.prefix}${var.env}uc${var.suffix}"
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

  # "privat": keine IP-/VNet-Freigaben. Zugriff nur über Private Endpoints (VNet + NCC) und
  # die explizit erlaubte Ressource (Access Connector) für die UC-Control-Plane.
  public_network_access = "Enabled"
  network_rules {
    # Fallback, solange die NCC-Private-Endpoints für Serverless noch nicht greifen (bis zu 24 h)
    default_action = var.storage_public_fallback ? "Allow" : "Deny"
    bypass         = ["AzureServices"]
    private_link_access {
      endpoint_resource_id = azurerm_databricks_access_connector.this.id
    }
  }
  tags = local.tags
}

resource "azurerm_storage_container" "uc" {
  for_each           = toset(local.uc_containers)
  name               = each.key
  storage_account_id = azurerm_storage_account.uc.id
}

resource "azurerm_role_assignment" "ac_uc_blob" {
  scope                = azurerm_storage_account.uc.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_databricks_access_connector.this.identity[0].principal_id
}

module "pe_uc" {
  source   = "../../modules/private_endpoint"
  for_each = toset(["dfs", "blob"])

  name                = "pe-${local.base}-uc-${each.key}"
  location            = local.location
  resource_group_name = local.rg
  subnet_id           = azurerm_subnet.pe.id
  target_resource_id  = azurerm_storage_account.uc.id
  subresource         = each.key
  private_dns_zone_id = azurerm_private_dns_zone.this[each.key].id
  tags                = local.tags
}

# ---------------------------------------------------------------------------
# Key Vault je Stage (Access-Policy-Modell: Pflicht für Key-Vault-backed Secret Scopes)
# ---------------------------------------------------------------------------
resource "azurerm_key_vault" "this" {
  name                       = "kv-${var.prefix}-${var.env}-${var.suffix}"
  location                   = local.location
  resource_group_name        = local.rg
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = false
  soft_delete_retention_days = 7
  purge_protection_enabled   = false
  # PoC-Kompromiss: public erreichbar (Entra-geschützt), damit GitHub-hosted Runner Secrets setzen
  # können. Zielbild: privat + Deployment-Agents im VNet (siehe solution-design).
  public_network_access_enabled = true
  network_acls {
    default_action = "Allow"
    bypass         = "AzureServices"
  }
  tags = local.tags
}

resource "azurerm_key_vault_access_policy" "admins" {
  for_each           = toset(var.kv_admin_object_ids)
  key_vault_id       = azurerm_key_vault.this.id
  tenant_id          = data.azurerm_client_config.current.tenant_id
  object_id          = each.key
  secret_permissions = ["Get", "List", "Set", "Delete", "Purge", "Recover"]
}

resource "azurerm_key_vault_access_policy" "azure_databricks" {
  key_vault_id       = azurerm_key_vault.this.id
  tenant_id          = data.azurerm_client_config.current.tenant_id
  object_id          = var.azure_databricks_sp_object_id
  secret_permissions = ["Get", "List"]
}

# ---------------------------------------------------------------------------
# Workspaces
# ---------------------------------------------------------------------------
module "workspace" {
  source   = "../../modules/workspace"
  for_each = local.ws

  prefix              = var.prefix
  env                 = var.env
  index               = each.key
  suffix              = var.suffix
  location            = local.location
  location_short      = var.location_short
  subscription_id     = var.subscription_id
  resource_group_name = local.rg
  vnet_id             = azurerm_virtual_network.this.id
  vnet_name           = azurerm_virtual_network.this.name
  host_cidr           = each.value.host_cidr
  container_cidr      = each.value.container_cidr
  pe_subnet_id        = azurerm_subnet.pe.id
  nat_gateway_id      = azurerm_nat_gateway.this.id
  access_connector_id = azurerm_databricks_access_connector.this.id
  private_dns_zone_ids = {
    dfs  = azurerm_private_dns_zone.this["dfs"].id
    blob = azurerm_private_dns_zone.this["blob"].id
  }
  tags = local.tags

  depends_on = [azurerm_nat_gateway_public_ip_association.this]
}

# ---------------------------------------------------------------------------
# Kostenwächter
# ---------------------------------------------------------------------------
resource "azurerm_consumption_budget_resource_group" "this" {
  count             = length(var.budget_contact_emails) > 0 ? 1 : 0
  name              = "budget-${local.base}"
  resource_group_id = data.azurerm_resource_group.platform.id
  amount            = var.budget_amount
  time_grain        = "Monthly"

  time_period {
    start_date = formatdate("YYYY-MM-01'T'00:00:00Z", timestamp())
  }

  dynamic "notification" {
    for_each = [50, 80, 100]
    content {
      enabled        = true
      threshold      = notification.value
      operator       = "GreaterThanOrEqualTo"
      threshold_type = "Actual"
      contact_emails = var.budget_contact_emails
    }
  }

  lifecycle {
    ignore_changes = [time_period]
  }
}
