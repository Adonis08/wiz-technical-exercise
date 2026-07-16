# Azure Container Registry — holds the app's container images. Basic SKU
# is the cheapest tier; admin_enabled stays false because nothing should
# authenticate with a shared username/password. AKS's kubelet identity
# gets an AcrPull role assignment below instead, so image pulls go through
# Azure AD identity, not a stored credential.
resource "azurerm_container_registry" "acr" {
  name                = "${var.prefix}acr${random_string.storage_suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Basic"
  admin_enabled       = false
}

# The AKS cluster. kubernetes_version is left unset so Terraform uses
# whatever AKS's current default is at creation time, rather than us
# hardcoding a version that might not exist in this region later.
resource "azurerm_kubernetes_cluster" "aks" {
  name                = "${var.prefix}-aks"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  dns_prefix          = "${var.prefix}-aks"

  # DELIBERATE SIMPLIFICATION: the API server stays publicly reachable so
  # kubectl works directly from a laptop, with no jump box or VPN. A real
  # production deployment would set this to true, at the cost of needing
  # a jump box / VPN inside the VNet to reach the API server at all. This
  # setting only affects the control plane's exposure — the node pool
  # below is still deployed into the private subnet either way, which is
  # what the exercise spec actually requires.
  private_cluster_enabled = false

  default_node_pool {
    name           = "default"
    node_count     = 2
    vm_size        = "Standard_B2s"
    vnet_subnet_id = azurerm_subnet.private.id
  }

  # System-assigned identity for the cluster's control plane — used by
  # AKS to manage its own Azure resources (load balancers, disks, and,
  # because nodes live in our pre-existing subnet rather than one AKS
  # creates for itself, the subnet permission below).
  identity {
    type = "SystemAssigned"
  }

  # Azure CNI: every pod gets a real IP address from the subnet itself,
  # not an overlay network address. This is why Stage 1 sized
  # private-subnet as a generous /22 (1,024 addresses) rather than a
  # /24 — under this model every pod needs its own subnet IP, not just
  # every node. service_cidr/dns_service_ip are internal Kubernetes
  # Service IPs only, and must NOT overlap the VNet's 10.0.0.0/16 range.
  network_profile {
    network_plugin = "azure"
    service_cidr   = "10.100.0.0/16"
    dns_service_ip = "10.100.0.10"
  }
}

# Custom-VNet + system-assigned identity requires the cluster's identity
# to hold Network Contributor on the subnet it deploys nodes into. AKS
# typically self-grants this at creation time (possible because the
# identity running `terraform apply` already has sufficient rights in
# this subscription). This resource can't be what makes the very first
# apply succeed — Terraform can't grant a role to an identity that
# doesn't exist yet — but it makes the permission explicit and durable
# in state afterward, scoped to just this one subnet.
resource "azurerm_role_assignment" "aks_network_contributor" {
  scope                = azurerm_subnet.private.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_kubernetes_cluster.aks.identity[0].principal_id
}

# Lets AKS pull images from the ACR using its own kubelet identity — a
# separate, auto-created identity for node-level operations, distinct
# from the cluster identity above — with no registry password anywhere.
# skip_service_principal_aad_check works around a real race condition:
# the kubelet identity is brand new at this point and may not have
# finished replicating through Azure AD yet, so Terraform's own
# existence pre-check is skipped and left to Azure RBAC, which tolerates
# the delay.
resource "azurerm_role_assignment" "aks_acr_pull" {
  scope                            = azurerm_container_registry.acr.id
  role_definition_name             = "AcrPull"
  principal_id                     = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
  skip_service_principal_aad_check = true
}
