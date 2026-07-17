# GitHub Actions -> Azure authentication.
#
# ORIGINAL DESIGN (see git history / presentation-notes.md Stage 4a): this
# was meant to be OIDC/workload identity federation — GitHub mints a
# short-lived token per workflow run, Azure AD trusts it via a federated
# credential, no stored secret anywhere. That required creating a new
# Azure AD application registration, which this tenant's authorization
# policy blocks for non-admin identities (`allowedToCreateApps = false`,
# confirmed via Microsoft Graph — see Stage 4a notes for the full
# diagnosis). Escalated through lab support; their guidance (backed by
# the hiring manager) was to use a pre-provisioned service principal's
# client secret instead, explicitly because self-service app-registration
# creation is restricted precisely due to a real, documented Entra ID
# privilege-escalation path (an Application Administrator, or anyone who
# can create app registrations, can add credentials to any app or grant
# it Graph permissions on its behalf).
#
# So: this data source looks up the PROVIDED service principal (already
# created by the lab environment) rather than creating a new one. The
# role assignments below are unchanged from the original design — same
# least-privilege scoping — only the identity's origin and its auth
# mechanism (client secret via GitHub Secrets, not a federated token)
# changed.
data "azuread_service_principal" "github_actions" {
  client_id = "962a538b-135e-4ce4-9a1f-7d41ea130367"
}

# --- Role assignments the pipeline needs ---
#
# Unchanged from the original design: Contributor scoped to just this
# resource group (contrast with Stage 1's subscription-wide grant),
# AcrPush scoped to just the registry, AKS Cluster User scoped to just
# this cluster.

resource "azurerm_role_assignment" "github_actions_contributor" {
  scope                = azurerm_resource_group.main.id
  role_definition_name = "Contributor"
  principal_id         = data.azuread_service_principal.github_actions.object_id
}

resource "azurerm_role_assignment" "github_actions_acr_push" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPush"
  principal_id         = data.azuread_service_principal.github_actions.object_id
}

resource "azurerm_role_assignment" "github_actions_aks_user" {
  scope                = azurerm_kubernetes_cluster.aks.id
  role_definition_name = "Azure Kubernetes Service Cluster User Role"
  principal_id         = data.azuread_service_principal.github_actions.object_id
}
