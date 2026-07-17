output "tfstate_resource_group_name" {
  description = "Set as repo variable TF_STATE_RESOURCE_GROUP"
  value       = azurerm_resource_group.tfstate.name
}

output "tfstate_storage_account_name" {
  description = "Set as repo variable TF_STATE_STORAGE_ACCOUNT"
  value       = azurerm_storage_account.tfstate.name
}

output "tfstate_container_name" {
  description = "Set as repo variable TF_STATE_CONTAINER"
  value       = azurerm_storage_container.tfstate.name
}
