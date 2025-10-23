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

# Resource group Created externally
resource "azurerm_resource_group" "this" {
  name     = "rg-quix-private"
  location = "westeurope"
}

# External VNet and subnets (managed outside the module)
resource "azurerm_virtual_network" "ext" {
  name                = "vnet-quix-private"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = ["10.240.0.0/16"]
}

resource "azurerm_subnet" "nodes_ext" {
  name                 = "Subnet-Nodes"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.ext.name
  address_prefixes     = ["10.240.0.0/22"]
}

resource "azurerm_subnet" "bastion_ext" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.ext.name
  address_prefixes     = ["10.240.5.0/27"]
}


# External NAT (bring your own)
resource "azurerm_public_ip" "nat_ext" {
  name                = "pip-quix-private-nat-ext"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["2"]
}

resource "azurerm_nat_gateway" "ext" {
  name                = "ngw-quix-private-ext"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  sku_name            = "Standard"
}

resource "azurerm_nat_gateway_public_ip_association" "ext" {
  nat_gateway_id       = azurerm_nat_gateway.ext.id
  public_ip_address_id = azurerm_public_ip.nat_ext.id
}

resource "azurerm_subnet_nat_gateway_association" "nodes_ext" {
  subnet_id      = azurerm_subnet.nodes_ext.id
  nat_gateway_id = azurerm_nat_gateway.ext.id
}


module "aks" {
  source = "../../modules/quix-aks"

  name                    = "quix-aks-private"
  location                = "westeurope"
  resource_group_name     = azurerm_resource_group.this.name
  create_resource_group   = false
  kubernetes_version      = "1.32.4"
  sku_tier                = "Standard"
  private_cluster_enabled = true

  vnet_name         = azurerm_virtual_network.ext.name
  nodes_subnet_name = azurerm_subnet.nodes_ext.name

  identity_name     = "quix-private-nat-id"
  public_ip_name    = "quix-private-nat-ip"
  nat_gateway_name  = "quix-private-nat"
  availability_zone = "2"

  enable_credentials_fetch = true
  node_pools = {
    default = {
      name       = "default"
      type       = "system"
      node_count = 2
      vm_size    = "Standard_D4ds_v5"
    }
  }

  network_profile = {
    network_plugin_mode = "overlay"
    service_cidr        = "172.22.0.0/16"
    dns_service_ip      = "172.22.0.10"
    pod_cidr            = "10.144.0.0/16"
  }
  # Bring your own NAT
  create_nat            = false
  nat_gateway_id        = azurerm_nat_gateway.ext.id
  create_nodes_subnet   = false
  create_vnet           = false
  create_bastion_subnet = false
  enable_bastion        = true
  bastion_name          = "quix-bastion"

  jumpbox_name           = "quix-jumpbox"
  jumpbox_vm_size        = "Standard_B2s"
  jumpbox_admin_username = "azureuser"
  jumpbox_ssh_public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC3Zz+tHUEI7ulzE69GxtLwi9DOvROBG4aI7h3za2FAP6Ya9/GhG2zcBiKOzk3SlKavE3/5NomgGifTC/ica6rTPlpb4U5oky/2phs9AtczVVI2G+yNC43hJzVhWbqKT3qAGGCGEm2+Cpxx7spKEbZAfAcq5GxL3k9kTcpaQEv3hpVvqK3zlCziHyahUv1pxQGuX3b2hqi4idgFX3m0FaqU98DtQu/I9x95jXHrb7Wltp3sbTSKCDxGo3nk4plpzILs/OqTMSPpfxwarCXA1ZtU82hyWO4Szn2U4I+MbuNaO/dso1oNlprqJQgsQ8t+hawCdIHeZ00M/QELdnYldBjo1jM19AT1OwMcB7PP7GRTNv7YsDW10YCvX9XRPab66PIKpe5R4IG/n6TzEwUP2pb4hRJWvnPJzrHK5HEJg7G7baCEyjCtaWkL4M7dBxIGJ3sp9IfjdeztV2Llh+hYmwPefTejprER+Q/qHZTNr1wEW4BV0TQQd+jeqdIL4QkIno3IyM3IBX+uPM/WlSpi2sT+hDqiUcCRu/x21O/bVYz/UbeHIqptRDfGc5rVoAN/zc/kGsGeGuP3auyI6aQxlnU0wMDdyS8rf3SpWagOB2UFNxZSuU2gnYdtz2uWG4vF75Sqr04MFJImHIY4N7gHJrvdarg6YBaDDnmdREcqp3ooAw== "

  oidc_issuer_enabled       = true
  workload_identity_enabled = true


  tags = {
    environment = "demo"
    project     = "Quix"
  }

  depends_on = [
    azurerm_resource_group.this,
    azurerm_subnet.bastion_ext,
    azurerm_subnet_nat_gateway_association.nodes_ext
  ]
}


