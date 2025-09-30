################################################################################
# Networking: VNet, Subnets, NAT Gateway and Identity
################################################################################

resource "azurerm_virtual_network" "this" {
  name                = var.vnet_name
  location            = local.rg_location
  resource_group_name = local.rg_name_effective
  address_space       = var.vnet_address_space
  tags                = var.tags
}

resource "azurerm_subnet" "nodes" {
  name                 = var.nodes_subnet_name
  resource_group_name  = local.rg_name_effective
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.nodes_subnet_cidr]
  service_endpoints    = ["Microsoft.Storage"]
}

resource "azurerm_user_assigned_identity" "nat_identity" {
  name                = var.nat_identity_name
  location            = local.rg_location
  resource_group_name = local.rg_name_effective
  tags                = var.tags
}

resource "azurerm_public_ip" "nat_gateway" {
  name                = var.public_ip_name
  location            = local.rg_location
  resource_group_name = local.rg_name_effective
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = [var.availability_zone]
  tags                = var.tags
}

resource "azurerm_nat_gateway" "this" {
  name                = var.nat_gateway_name
  location            = local.rg_location
  resource_group_name = local.rg_name_effective
  sku_name            = "Standard"
  tags                = var.tags
}

resource "azurerm_nat_gateway_public_ip_association" "this" {
  nat_gateway_id       = azurerm_nat_gateway.this.id
  public_ip_address_id = azurerm_public_ip.nat_gateway.id
}

resource "azurerm_subnet_nat_gateway_association" "nodes" {
  subnet_id      = azurerm_subnet.nodes.id
  nat_gateway_id = azurerm_nat_gateway.this.id
}


