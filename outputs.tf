output "db_vm_public_ip" {
  description = "Public IP address of the database VM"
  value       = azurerm_public_ip.db.ip_address
}

# Trivial comment-only change to trigger a real end-to-end pipeline test:
# PR -> checkov + terraform plan + PR comment -> merge -> push -> terraform
# apply, all as genuine GitHub Actions events rather than manual dispatch.

output "private_subnet_cidr" {
  description = "CIDR block of the private subnet reserved for AKS"
  value       = azurerm_subnet.private.address_prefixes[0]
}

output "storage_account_name" {
  description = "Name of the storage account holding MongoDB backups"
  value       = azurerm_storage_account.backups.name
}

output "backup_container_url" {
  description = "Public URL of the (intentionally public) MongoDB backup blob container"
  value       = "${azurerm_storage_account.backups.primary_blob_endpoint}${azurerm_storage_container.backups.name}"
}

output "acr_login_server" {
  description = "Login server hostname for the Azure Container Registry"
  value       = azurerm_container_registry.acr.login_server
}

output "aks_cluster_name" {
  description = "Name of the AKS cluster"
  value       = azurerm_kubernetes_cluster.aks.name
}

output "aks_get_credentials_command" {
  description = "Command to configure kubectl to talk to this cluster"
  value       = "az aks get-credentials --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_kubernetes_cluster.aks.name} --overwrite-existing"
}

# No terraform outputs for the GitHub Actions identity's client ID/tenant/
# subscription: since github-ci-auth.tf now looks up a pre-provisioned
# service principal (see that file's header comment for why) rather than
# creating one, those values are already known upfront rather than
# computed by this config — they were set directly as GitHub repo
# variables (AZURE_CLIENT_ID/AZURE_TENANT_ID/AZURE_SUBSCRIPTION_ID) and
# secret (AZURE_CLIENT_SECRET) without needing an output round-trip.
