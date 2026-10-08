terraform {
  required_version = ">= 1.14"
  required_providers {
    databricks = { source = "databricks/databricks", version = "~> 1.137" }
  }
  # State im tfstate-Storage (key = account.tfstate); lokal von einem Account Admin ausgeführt.
  backend "azurerm" {}
}

provider "databricks" {
  host       = "https://accounts.azuredatabricks.net"
  account_id = var.databricks_account_id
  auth_type  = "azure-cli"
}
