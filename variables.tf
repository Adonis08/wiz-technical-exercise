variable "subscription_id" {
  description = "Azure subscription ID to deploy into"
  type        = string
}

variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "eastus"
}

variable "prefix" {
  description = "Short prefix used to name all resources (e.g. 'wiz')"
  type        = string
  default     = "wiz"
}

variable "vnet_address_space" {
  description = "Address space for the virtual network"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet (hosts the DB VM)"
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR block for the private subnet (sized generously for AKS in a later stage)"
  type        = string
  default     = "10.0.4.0/22"
}

variable "admin_username" {
  description = "Admin username for SSH login to the DB VM"
  type        = string
  default     = "azureadmin"
}

variable "ssh_public_key" {
  description = "SSH public key content used to log in to the DB VM"
  type        = string
}

variable "db_app_username" {
  description = "Username for the MongoDB application user created on the DB VM"
  type        = string
  default     = "appuser"
}

variable "db_app_password" {
  description = "Password for the MongoDB application user. Do not hardcode a real value here or in defaults — supply via terraform.tfvars (gitignored) or a TF_VAR_db_app_password environment variable."
  type        = string
  sensitive   = true
}

variable "github_repository" {
  description = "GitHub repo in 'owner/repo' form — scopes the GitHub Actions OIDC federated credential's trust condition to exactly this repo."
  type        = string
  default     = "Adonis08/wiz-technical-exercise"
}
