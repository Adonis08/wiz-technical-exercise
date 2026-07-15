resource "random_string" "storage_suffix" {
  length  = 6
  lower   = true
  upper   = false
  numeric = true
  special = false
}

# INTENTIONAL MISCONFIG: overrides Azure's default guardrail (which blocks
# anonymous access account-wide on new storage accounts) so that the
# container below can actually grant public access.
resource "azurerm_storage_account" "backups" {
  name                = "${var.prefix}dbbackup${random_string.storage_suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  account_tier             = "Standard"
  account_replication_type = "LRS"

  public_network_access_enabled   = true
  allow_nested_items_to_be_public = true
}

# INTENTIONAL MISCONFIG: "container" access type grants anonymous READ and
# LIST on this container — anyone on the internet can enumerate every
# backup file's name and download it, no credentials required.
resource "azurerm_storage_container" "backups" {
  name                  = "mongo-backups"
  storage_account_name  = azurerm_storage_account.backups.name
  container_access_type = "container"
}

# Properly least-privilege, unlike Stage 1's subscription-wide Contributor
# grant: this only lets the VM's identity write blobs to this one storage
# account, nothing else in the subscription.
resource "azurerm_role_assignment" "db_vm_storage_blob_contributor" {
  scope                = azurerm_storage_account.backups.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_virtual_machine.db.identity[0].principal_id
}
