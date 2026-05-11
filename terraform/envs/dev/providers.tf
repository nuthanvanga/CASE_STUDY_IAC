terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.100.0, < 4.0.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5.0"
    }
  }

  # Remote state in an Azure storage account.
  # Initialise with: terraform init -backend-config=backend.hcl
  # (in CI the four backend coordinates are pulled from kv-tfstate-dev)
  backend "azurerm" {}
}

provider "azurerm" {
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id

  # Use AAD (Entra) for Storage data-plane operations. Required because the
  # storage module sets shared_access_key_enabled = false. The SPN running
  # Terraform must have "Storage Blob Data Owner" on the subscription (or
  # the platform RG) for the post-create readiness probe to succeed.
  storage_use_azuread = true

  features {
    key_vault {
      purge_soft_delete_on_destroy    = false
      recover_soft_deleted_key_vaults = true
    }
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
  }
}
