################################################################################
# Networking: VNet, Subnets, NAT Gateway and Identity
################################################################################

locals {
  # When provided, place/read VNet and Subnets from this resource group
  vnet_rg_effective = coalesce(var.vnet_resource_group, local.rg_name_effective)
}

resource "azurerm_virtual_network" "this" {
  count               = var.create_vnet ? 1 : 0
  name                = var.vnet_name
  location            = local.rg_location
  resource_group_name = local.vnet_rg_effective
  address_space       = var.vnet_address_space
  tags                = var.tags
}

data "azurerm_virtual_network" "existing" {
  count               = var.create_vnet ? 0 : 1
  name                = var.vnet_name
  resource_group_name = local.vnet_rg_effective
}

resource "azurerm_subnet" "nodes" {
  count                = var.create_nodes_subnet ? 1 : 0
  name                 = var.nodes_subnet_name
  resource_group_name  = local.vnet_rg_effective
  virtual_network_name = coalesce(try(azurerm_virtual_network.this[0].name, null), try(data.azurerm_virtual_network.existing[0].name, null), var.vnet_name)
  address_prefixes     = [var.nodes_subnet_cidr]
  service_endpoints    = ["Microsoft.Storage"]
}

data "azurerm_subnet" "existing" {
  count                = var.create_nodes_subnet ? 0 : 1
  name                 = var.nodes_subnet_name
  virtual_network_name = var.vnet_name
  resource_group_name  = local.vnet_rg_effective
}

resource "azurerm_user_assigned_identity" "nat_identity" {
  name                = var.identity_name
  location            = local.rg_location
  resource_group_name = local.rg_name_effective
  tags                = var.tags
}

resource "azurerm_public_ip" "nat_gateway" {
  count               = var.create_nat ? 1 : 0
  name                = var.public_ip_name
  location            = local.rg_location
  resource_group_name = local.rg_name_effective
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = [var.availability_zone]
  tags                = var.tags
}

resource "azurerm_nat_gateway" "this" {
  count               = var.create_nat ? 1 : 0
  name                = var.nat_gateway_name
  location            = local.rg_location
  resource_group_name = local.rg_name_effective
  sku_name            = "Standard"
  tags                = var.tags
}

resource "azurerm_nat_gateway_public_ip_association" "this" {
  count                = var.create_nat ? 1 : 0
  nat_gateway_id       = azurerm_nat_gateway.this[0].id
  public_ip_address_id = azurerm_public_ip.nat_gateway[0].id
}

resource "azurerm_subnet_nat_gateway_association" "nodes" {
  count          = (var.create_nodes_subnet || var.create_nat) ? 1 : 0
  subnet_id      = coalesce(try(azurerm_subnet.nodes[0].id, null), try(data.azurerm_subnet.existing[0].id, null))
  nat_gateway_id = coalesce(try(azurerm_nat_gateway.this[0].id, null), var.nat_gateway_id)  
}


