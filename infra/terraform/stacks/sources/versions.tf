terraform {
  required_version = ">= 1.14"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 5.8" }
    azapi   = { source = "azure/azapi", version = "~> 2.13" }
    random  = { source = "hashicorp/random", version = "~> 3.9" }
  }
  backend "azurerm" {}
}

provider "azurerm" {
  features {}
  subscription_id     = var.subscription_id
  storage_use_azuread = true
}

provider "azapi" {
  subscription_id = var.subscription_id
}
