variable "subscription_id" {
  description = "Azure subscription ID to deploy into"
  type        = string
}

variable "prefix" {
  description = "Short prefix used to name resources"
  type        = string
  default     = "wiz"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "eastus"
}

variable "github_actions_app_display_name" {
  description = "Display name of the Azure AD application from the main config's github-oidc.tf. Looked up here (not passed via state) so this config and the main config never need to read each other's state."
  type        = string
  default     = "wiz-github-actions"
}
