################################################################################
# Dual-Cluster Example with Shared Networking
#
# This example deploys two private AKS clusters (control plane + data plane)
# sharing a single VNet and NAT gateway. No bastion is deployed; users are
# expected to provide their own connectivity via VPN or ExpressRoute.
################################################################################

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
# Shared Infrastructure
################################################################################

resource "azurerm_resource_group" "this" {
  name     = "rg-quix-dual-cluster"
  location = "westeurope"
}

# Shared Virtual Network
resource "azurerm_virtual_network" "shared" {
  name                = "vnet-quix-shared"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = ["10.240.0.0/16"]
}

# Control Plane subnet (1024 IPs)
resource "azurerm_subnet" "ctrl_plane" {
  name                 = "Subnet-CtrlPlane"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.shared.name
  address_prefixes     = ["10.240.0.0/22"]
}

# Data Plane subnet (1024 IPs)
resource "azurerm_subnet" "data_plane" {
  name                 = "Subnet-DataPlane"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.shared.name
  address_prefixes     = ["10.240.4.0/22"]
}

# Shared NAT Gateway
resource "azurerm_public_ip" "nat" {
  name                = "pip-quix-shared-nat"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["2"]
}

resource "azurerm_nat_gateway" "shared" {
  name                = "ngw-quix-shared"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  sku_name            = "Standard"
}

resource "azurerm_nat_gateway_public_ip_association" "shared" {
  nat_gateway_id       = azurerm_nat_gateway.shared.id
  public_ip_address_id = azurerm_public_ip.nat.id
}

# Associate NAT Gateway with both subnets
resource "azurerm_subnet_nat_gateway_association" "ctrl_plane" {
  subnet_id      = azurerm_subnet.ctrl_plane.id
  nat_gateway_id = azurerm_nat_gateway.shared.id
}

resource "azurerm_subnet_nat_gateway_association" "data_plane" {
  subnet_id      = azurerm_subnet.data_plane.id
  nat_gateway_id = azurerm_nat_gateway.shared.id
}

################################################################################
# Control Plane Cluster
################################################################################

module "aks_ctrl" {
  source = "../../modules/quix-aks"

  name                    = "quix-aks-ctrl"
  location                = azurerm_resource_group.this.location
  resource_group_name     = azurerm_resource_group.this.name
  create_resource_group   = false
  kubernetes_version      = "1.33.5"
  sku_tier                = "Standard"
  private_cluster_enabled = true

  # BYO networking
  create_vnet         = false
  create_nodes_subnet = false
  create_nat          = false
  vnet_name           = azurerm_virtual_network.shared.name
  nodes_subnet_name   = azurerm_subnet.ctrl_plane.name
  nat_gateway_id      = azurerm_nat_gateway.shared.id

  identity_name = "quix-ctrl-id"

  # No bastion
  enable_bastion        = false
  create_bastion_subnet = false

  # Overlay networking
  network_profile = {
    network_plugin_mode = "overlay"
    service_cidr        = "172.20.0.0/16"
    dns_service_ip      = "172.20.0.10"
    pod_cidr            = "10.144.0.0/16"
  }

  node_pools = {
    system = {
      name       = "system"
      type       = "system"
      node_count = 2
      vm_size    = "Standard_D2ds_v5"
    }
    platform = {
      name       = "platform"
      type       = "user"
      node_count = 3
      vm_size    = "Standard_E4ds_v5"
      labels = {
        "quix.io/node-purpose" = "platform-services"
      }
    }
  }

  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  tags = {
    environment = "demo"
    project     = "Quix"
    role        = "control-plane"
  }

  depends_on = [
    azurerm_subnet_nat_gateway_association.ctrl_plane
  ]
}

################################################################################
# Data Plane Cluster
################################################################################

module "aks_data" {
  source = "../../modules/quix-aks"

  name                    = "quix-aks-data"
  location                = azurerm_resource_group.this.location
  resource_group_name     = azurerm_resource_group.this.name
  create_resource_group   = false
  kubernetes_version      = "1.33.5"
  sku_tier                = "Standard"
  private_cluster_enabled = true

  # BYO networking
  create_vnet         = false
  create_nodes_subnet = false
  create_nat          = false
  vnet_name           = azurerm_virtual_network.shared.name
  nodes_subnet_name   = azurerm_subnet.data_plane.name
  nat_gateway_id      = azurerm_nat_gateway.shared.id

  identity_name = "quix-data-id"

  # No bastion
  enable_bastion        = false
  create_bastion_subnet = false

  # Overlay networking (use different service/pod CIDRs to avoid conflicts)
  network_profile = {
    network_plugin_mode = "overlay"
    service_cidr        = "172.21.0.0/16"
    dns_service_ip      = "172.21.0.10"
    pod_cidr            = "10.145.0.0/16"
  }

  node_pools = {
    system = {
      name       = "system"
      type       = "system"
      node_count = 2
      vm_size    = "Standard_D2ds_v5"
    }
    deployments = {
      name       = "deployments"
      type       = "user"
      node_count = 3
      vm_size    = "Standard_E4ds_v5"
      labels = {
        "quix.io/node-purpose" = "customer-deployments"
      }
    }
  }

  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  tags = {
    environment = "demo"
    project     = "Quix"
    role        = "data-plane"
  }

  depends_on = [
    azurerm_subnet_nat_gateway_association.data_plane
  ]
}
