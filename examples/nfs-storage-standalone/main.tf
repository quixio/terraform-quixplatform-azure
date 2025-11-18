terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.112"
    }
  }
}

provider "azurerm" {
  features {}
}

################################################################################
# Existing Resource Group
################################################################################

data "azurerm_resource_group" "existing" {
  name = var.resource_group_name
}

################################################################################
# Existing VNet and Subnet
################################################################################

data "azurerm_virtual_network" "existing" {
  name                = var.vnet_name
  resource_group_name = var.resource_group_name
}

data "azurerm_subnet" "private_endpoints" {
  name                 = var.private_endpoint_subnet_name
  virtual_network_name = var.vnet_name
  resource_group_name  = var.resource_group_name
}

data "azurerm_subnet" "allowed_subnet" {
  count                = var.allowed_subnet_name != "" ? 1 : 0
  name                 = var.allowed_subnet_name
  virtual_network_name = var.vnet_name
  resource_group_name  = var.resource_group_name
}

################################################################################
# NFS Storage Module
################################################################################

module "nfs_storage" {
  source = "../../modules/nfs-storage"

  resource_group_name  = data.azurerm_resource_group.existing.name
  location             = data.azurerm_resource_group.existing.location
  storage_account_name = var.storage_account_name

  # Private Endpoint configuration
  private_endpoint_subnet_id = data.azurerm_subnet.private_endpoints.id

  # VNet ID for automatic Private DNS Zone creation and linking
  vnet_id = data.azurerm_virtual_network.existing.id

  # Network Security Rules - Default deny policy
  # Allow access from specified subnet (e.g., AKS nodes, VM subnet, etc.)
  allowed_subnet_ids = var.allowed_subnet_name != "" ? [data.azurerm_subnet.allowed_subnet[0].id] : []

  # Allow your public IP for Terraform operations (creating shares, destroy)
  allowed_ip_addresses = var.allowed_ip_addresses

  # Network bypass - Azure services can bypass firewall
  network_bypass = ["AzureServices"]

  # Create NFS shares
  nfs_shares = var.nfs_shares

  tags = var.tags
}
