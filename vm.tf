resource "azurerm_public_ip" "db" {
  name                = "${var.prefix}-db-pip"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "db" {
  name                = "${var.prefix}-db-nic"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.public.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.db.id
  }
}

data "azurerm_subscription" "current" {}

# INTENTIONAL MISCONFIG: Ubuntu 20.04 LTS — deliberately outdated (current
# LTS is 24.04) so this VM is carrying 1+ year of unpatched OS-level CVEs,
# on top of the exposed SSH port.
resource "azurerm_linux_virtual_machine" "db" {
  name                = "${var.prefix}-db-vm"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  size                = "Standard_B2s"
  admin_username      = var.admin_username

  network_interface_ids = [azurerm_network_interface.db.id]

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts"
    version   = "latest"
  }

  # INTENTIONAL MISCONFIG: system-assigned identity, over-permissioned via
  # the role assignment below.
  identity {
    type = "SystemAssigned"
  }

  custom_data = base64encode(templatefile("${path.module}/cloud-init.yaml", {
    db_app_username = var.db_app_username
    db_app_password = var.db_app_password
  }))
}

# INTENTIONAL MISCONFIG: Contributor at subscription scope on an
# internet-facing VM. If this VM is compromised, the attacker inherits
# near-total control of the subscription (classic CIEM/lateral-movement
# finding).
resource "azurerm_role_assignment" "db_vm_contributor" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_linux_virtual_machine.db.identity[0].principal_id
}
