terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.90"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.53"
    }
  }

  # Deliberately NO backend block here. This config's only job is to
  # create the remote backend the MAIN config uses — it can't also store
  # its own state there (nothing would exist yet to store it in). Its
  # state stays local, in bootstrap/terraform.tfstate, forever. That's an
  # accepted, standard tradeoff: this config is tiny and changes rarely.
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

provider "azuread" {}
