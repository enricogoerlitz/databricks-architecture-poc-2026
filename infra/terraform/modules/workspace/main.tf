# Ein VNet-injizierter Premium-Workspace mit Secure Cluster Connectivity (kein Public IP),
# NAT-Egress und Workspace Storage Firewall (DBFS-Root privat).
locals {
  base            = "${var.prefix}-${var.env}-${var.location_short}-${var.index}"
  managed_rg_name = "rg-${var.prefix}-${var.env}-${var.location_short}-dbw${var.index}-managed"
  root_storage    = "st${var.prefix}${var.env}dbw${var.index}${var.suffix}"
  root_storage_id = "/subscriptions/${var.subscription_id}/resourceGroups/${local.managed_rg_name}/providers/Microsoft.Storage/storageAccounts/${local.root_storage}"
}

resource "azurerm_network_security_group" "this" {
  name                = "nsg-${local.base}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
  # Regeln verwaltet Azure Databricks selbst (Subnet-Delegation).
}

resource "azurerm_subnet" "dbw" {
  for_each             = { host = var.host_cidr, container = var.container_cidr }
  name                 = "snet-dbw${var.index}-${each.key}"
  resource_group_name  = var.resource_group_name
  virtual_network_name = var.vnet_name
  address_prefixes     = [each.value]
  # Seit 2026-03-31 kein Default-Outbound mehr; Egress kommt über das NAT Gateway.
  default_outbound_access_enabled = false

  delegation {
    name = "databricks"
    service_delegation {
      name = "Microsoft.Databricks/workspaces"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
        "Microsoft.Network/virtualNetworks/subnets/prepareNetworkPolicies/action",
        "Microsoft.Network/virtualNetworks/subnets/unprepareNetworkPolicies/action",
      ]
    }
  }
}

resource "azurerm_subnet_network_security_group_association" "dbw" {
  for_each                  = azurerm_subnet.dbw
  subnet_id                 = each.value.id
  network_security_group_id = azurerm_network_security_group.this.id
}

resource "azurerm_subnet_nat_gateway_association" "dbw" {
  for_each       = azurerm_subnet.dbw
  subnet_id      = each.value.id
  nat_gateway_id = var.nat_gateway_id
}

resource "azurerm_databricks_workspace" "this" {
  name                          = "dbw-${local.base}"
  location                      = var.location
  resource_group_name           = var.resource_group_name
  sku                           = "premium"
  managed_resource_group_name   = local.managed_rg_name
  public_network_access_enabled = true

  # Workspace Storage Firewall: DBFS-Root nur über Private Endpoints + Access Connector
  default_storage_firewall_enabled = true
  access_connector_id              = var.access_connector_id

  custom_parameters {
    no_public_ip                                         = true
    virtual_network_id                                   = var.vnet_id
    public_subnet_name                                   = azurerm_subnet.dbw["host"].name
    private_subnet_name                                  = azurerm_subnet.dbw["container"].name
    public_subnet_network_security_group_association_id  = azurerm_subnet_network_security_group_association.dbw["host"].id
    private_subnet_network_security_group_association_id = azurerm_subnet_network_security_group_association.dbw["container"].id
    storage_account_name                                 = local.root_storage
  }

  tags = var.tags

  depends_on = [azurerm_subnet_nat_gateway_association.dbw]
}

# Private Endpoints aus dem VNet auf den Workspace-Root-Storage (für klassisches Compute)
module "pe_root" {
  source   = "../private_endpoint"
  for_each = var.private_dns_zone_ids

  name                = "pe-${local.base}-root-${each.key}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.pe_subnet_id
  target_resource_id  = local.root_storage_id
  subresource         = each.key
  private_dns_zone_id = each.value
  tags                = var.tags

  depends_on = [azurerm_databricks_workspace.this]
}
