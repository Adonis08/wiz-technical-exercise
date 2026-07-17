resource "azurerm_resource_group" "tfstate" {
  # A separate resource group from wiz-rg on purpose: state storage
  # shouldn't share a lifecycle with the infrastructure it describes. If
  # someone ever tears down wiz-rg, the record of what used to be in it
  # (and the lock protecting concurrent applies) must survive that.
  name     = "${var.prefix}-tfstate-rg"
  location = var.location
}

resource "random_string" "tfstate_suffix" {
  length  = 6
  lower   = true
  upper   = false
  numeric = true
  special = false
}

# Deliberately the OPPOSITE of Stage 2's backups storage account.
# "Reachable over the public internet" and "anonymously readable" are two
# different axes — Stage 2 intentionally collapsed them into one
# misconfig; this keeps them separate on purpose:
#   - public_network_access_enabled = true  -> GitHub-hosted runners
#     (outside our VNet) can reach the API endpoint at all.
#   - allow_nested_items_to_be_public = false -> no container/blob can
#     ever be made anonymously readable, even by accident later.
#   - shared_access_key_enabled = false -> the storage account keys
#     (a bearer-token-like shared secret) are disabled outright. The ONLY
#     way in is an Azure AD identity with an explicit role assignment
#     below — same "no stored secret" philosophy as the GitHub OIDC setup.
resource "azurerm_storage_account" "tfstate" {
  name                = "${var.prefix}tfstate${random_string.tfstate_suffix.result}"
  resource_group_name = azurerm_resource_group.tfstate.name
  location            = azurerm_resource_group.tfstate.location

  account_tier             = "Standard"
  account_replication_type = "LRS"

  public_network_access_enabled   = true
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false

  blob_properties {
    # Protects against a corrupted/bad state write clobbering good state —
    # every version of the state blob is kept, so you can roll back.
    versioning_enabled = true
  }
}

resource "azurerm_storage_container" "tfstate" {
  name                  = "tfstate"
  storage_account_name  = azurerm_storage_account.tfstate.name
  container_access_type = "private"
}

# Looks up the GitHub Actions service principal created by the MAIN
# config's github-oidc.tf. Requires that config to be applied first (see
# the apply-order note in the workflow explanation) — this is a read-only
# lookup, not a cross-state reference, so the two configs stay decoupled.
data "azuread_application" "github_actions" {
  display_name = var.github_actions_app_display_name
}

data "azuread_service_principal" "github_actions" {
  client_id = data.azuread_application.github_actions.client_id
}

# The only permission CI needs here: read/write blobs (the state file
# itself). Nothing account-management-level, nothing outside this one
# storage account.
resource "azurerm_role_assignment" "github_actions_tfstate" {
  scope                = azurerm_storage_account.tfstate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azuread_service_principal.github_actions.object_id
}

# Your own az-cli identity needs the same role, to run terraform
# init/plan/apply against this backend from your laptop.
data "azurerm_client_config" "current" {}

resource "azurerm_role_assignment" "operator_tfstate" {
  scope                = azurerm_storage_account.tfstate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}
