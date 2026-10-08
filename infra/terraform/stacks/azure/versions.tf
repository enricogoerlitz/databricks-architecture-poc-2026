terraform {
  required_version = ">= 1.14"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 5.8" }
  }
  # Partial config: terraform init -backend-config=../../envs/backend.hcl -backend-config="key=<env>/azure.tfstate"
  backend "azurerm" {}
}

provider "azurerm" {
  features {
    key_vault {
      # Neuaufbau am selben Tag möglich (D3): Soft-Delete beim Destroy purgen.
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    databricks_workspace {
      # Kein 7-Tage-Soft-Delete, Managed RG wird mit gelöscht.
      force_delete = true
    }
  }
  subscription_id     = var.subscription_id
  storage_use_azuread = true
}
