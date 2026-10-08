terraform {
  required_version = ">= 1.14"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 5.8" }
    azuread = { source = "hashicorp/azuread", version = "~> 3.10" }
    github  = { source = "integrations/github", version = "~> 6.13" }
  }
}

provider "azurerm" {
  features {}
  subscription_id     = var.subscription_id
  storage_use_azuread = true
}

provider "azuread" {}

# Token: export GITHUB_TOKEN=$(gh auth token)
provider "github" {
  owner = var.github_owner
}
