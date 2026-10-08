terraform {
  required_version = ">= 1.14"
  required_providers {
    databricks = { source = "databricks/databricks", version = "~> 1.137" }
    azurerm    = { source = "hashicorp/azurerm", version = "~> 5.8" }
  }
  backend "azurerm" {}
}

provider "azurerm" {
  features {}
  subscription_id     = var.subscription_id
  storage_use_azuread = true
}

# Auth überall über die Azure CLI (lokal: dein Login; CI: azure/login mit OIDC).
# Entra-Token sind Pflicht für Key-Vault-backed Secret Scopes.
provider "databricks" {
  alias      = "account"
  host       = "https://accounts.azuredatabricks.net"
  account_id = var.databricks_account_id
  auth_type  = "azure-cli"
}

provider "databricks" {
  alias     = "ws1"
  host      = local.ws_urls[0]
  auth_type = "azure-cli"
}

# Zweiter Workspace (nur dev). Bei einer Stage mit einem Workspace zeigt er auf ws1 und
# alle ws2-Ressourcen haben count = 0.
provider "databricks" {
  alias     = "ws2"
  host      = local.ws_urls[length(local.ws_urls) > 1 ? 1 : 0]
  auth_type = "azure-cli"
}
