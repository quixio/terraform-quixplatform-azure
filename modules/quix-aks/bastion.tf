################################################################################
# Bastion + Jumpbox (Optional)
################################################################################

resource "azurerm_subnet" "bastion" {
  count                = var.enable_bastion && var.create_bastion_subnet ? 1 : 0
  name                 = "AzureBastionSubnet"
  resource_group_name  = local.rg_name_effective
  virtual_network_name = coalesce(try(azurerm_virtual_network.this[0].name, null), try(data.azurerm_virtual_network.existing[0].name, null), var.vnet_name)
  address_prefixes     = [var.bastion_subnet_cidr]
}

data "azurerm_subnet" "bastion" {
  count                = var.enable_bastion && !var.create_bastion_subnet ? 1 : 0
  name                 = "AzureBastionSubnet"
  virtual_network_name = var.vnet_name
  resource_group_name  = local.rg_name_effective
}

resource "azurerm_public_ip" "bastion" {
  count               = var.enable_bastion && (var.bastion_public_ip_id == null) ? 1 : 0
  name                = var.bastion_public_ip_name
  location            = local.rg_location
  resource_group_name = local.rg_name_effective
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_bastion_host" "this" {
  count               = var.enable_bastion ? 1 : 0
  name                = var.bastion_name
  location            = local.rg_location
  resource_group_name = local.rg_name_effective
  sku                 = "Standard"
  tunneling_enabled   = true
  ip_connect_enabled  = true

  ip_configuration {
    name                 = "configuration"
    subnet_id            = coalesce(try(azurerm_subnet.bastion[0].id, null), try(data.azurerm_subnet.bastion[0].id, null), var.bastion_subnet_id)
    public_ip_address_id = coalesce(try(azurerm_public_ip.bastion[0].id, null), var.bastion_public_ip_id)
  }

  tags = var.tags
}

resource "azurerm_network_interface" "jumpbox" {
  count               = var.enable_bastion ? 1 : 0
  name                = "${var.jumpbox_name}-nic"
  location            = local.rg_location
  resource_group_name = local.rg_name_effective

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = coalesce(try(azurerm_subnet.nodes[0].id, null), data.azurerm_subnet.nodes[0].id, var.nodes_subnet_id)
    private_ip_address_allocation = "Dynamic"
  }

  tags = var.tags
}

resource "azurerm_linux_virtual_machine" "jumpbox" {
  count               = var.enable_bastion ? 1 : 0
  name                = var.jumpbox_name
  location            = local.rg_location
  resource_group_name = local.rg_name_effective
  size                = var.jumpbox_vm_size
  admin_username      = var.jumpbox_admin_username

  network_interface_ids = [azurerm_network_interface.jumpbox[0].id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  admin_ssh_key {
    username   = var.jumpbox_admin_username
    public_key = var.jumpbox_ssh_public_key
  }

  custom_data = var.enable_bastion ? base64encode(<<-EOT
    #cloud-config
    package_update: true
    packages:
      - ca-certificates
      - curl
      - apt-transport-https
      - gnupg
    runcmd:
      - curl -sL https://aka.ms/InstallAzureCLIDeb | bash
      - az aks install-cli
  EOT
  ) : null

  tags = var.tags
}


