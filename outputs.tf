output "db_vm_public_ip" {
  description = "Public IP address of the database VM"
  value       = azurerm_public_ip.db.ip_address
}

output "private_subnet_cidr" {
  description = "CIDR block of the private subnet reserved for AKS"
  value       = azurerm_subnet.private.address_prefixes[0]
}
