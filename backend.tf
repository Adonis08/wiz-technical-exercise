# Remote state — Azure Storage, authenticated via Entra ID rather than a
# storage account access key. Values (resource group/storage
# account/container names) are supplied at `terraform init` time via
# -backend-config flags rather than hardcoded here — Terraform backend
# blocks can't use variables or interpolation, and this way the exact
# same init command works for you locally and for CI, just pointed at
# different var sources.
#
# use_azuread_auth = true is the whole point: without it, this backend
# would need a storage account access key sitting somewhere — a
# long-lived shared secret, exactly what Stage 4a's OIDC setup exists to
# avoid for the Azure resource deployments themselves. With it,
# Terraform authenticates as whatever identity is already active (your
# `az login` session locally; the OIDC-derived identity in CI) and Azure
# checks that identity's RBAC role — no password-equivalent anywhere.
terraform {
  backend "azurerm" {
    use_azuread_auth = true
  }
}
