################################################################################
# Dual-Cluster Example with Shared Networking
#
# This example deploys two private AKS clusters (control plane + data plane)
# sharing a single VNet and NAT gateway.
#
# Architecture:
# - Control Plane Cluster: Runs Quix platform services
# - Data Plane Cluster: Runs customer deployments/workloads
# - Both clusters share egress through a single NAT gateway
# - Private API servers - requires VPN/ExpressRoute for access
#
# Network Design:
# - Overlay networking isolates pod networks from node subnets
# - Each cluster has unique service/pod CIDRs to enable cross-cluster routing
# - NSGs provide network segmentation between cluster subnets
################################################################################

provider "azurerm" {
  features {}
}

################################################################################
# Shared Infrastructure
################################################################################

resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
}

# Shared Virtual Network for both clusters
resource "azurerm_virtual_network" "shared" {
  name                = var.vnet_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = var.vnet_address_space
  tags                = var.tags
}

resource "azurerm_subnet" "ctrl_plane" {
  name                 = "Subnet-CtrlPlane"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.shared.name
  address_prefixes     = [var.ctrl_plane_subnet_cidr]
}

resource "azurerm_subnet" "data_plane" {
  name                 = "Subnet-DataPlane"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.shared.name
  address_prefixes     = [var.data_plane_subnet_cidr]
}

################################################################################
# Network Security Groups
# Provides network segmentation between clusters while allowing necessary traffic
################################################################################

resource "azurerm_network_security_group" "ctrl_plane" {
  name                = "nsg-ctrl-plane"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags
}

resource "azurerm_network_security_group" "data_plane" {
  name                = "nsg-data-plane"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags
}

resource "azurerm_subnet_network_security_group_association" "ctrl_plane" {
  subnet_id                 = azurerm_subnet.ctrl_plane.id
  network_security_group_id = azurerm_network_security_group.ctrl_plane.id
}

resource "azurerm_subnet_network_security_group_association" "data_plane" {
  subnet_id                 = azurerm_subnet.data_plane.id
  network_security_group_id = azurerm_network_security_group.data_plane.id
}

################################################################################
# Shared NAT Gateway
# Single egress point for both clusters - cost effective, single public IP
################################################################################

resource "azurerm_public_ip" "nat" {
  name                = "pip-quix-shared-nat"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = [var.availability_zone]
  tags                = var.tags
}

resource "azurerm_nat_gateway" "shared" {
  name                = "ngw-quix-shared"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  sku_name            = "Standard"
  tags                = var.tags
}

resource "azurerm_nat_gateway_public_ip_association" "shared" {
  nat_gateway_id       = azurerm_nat_gateway.shared.id
  public_ip_address_id = azurerm_public_ip.nat.id
}

# Associate NAT Gateway with both subnets for outbound connectivity
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
# Runs Quix platform services (API, management, monitoring)
################################################################################

module "aks_ctrl" {
  source = "../../modules/quix-aks"

  name                    = var.ctrl_cluster_name
  location                = azurerm_resource_group.this.location
  resource_group_name     = azurerm_resource_group.this.name
  create_resource_group   = false
  kubernetes_version      = var.kubernetes_version
  sku_tier                = "Standard"
  private_cluster_enabled = true

  # BYO networking - use shared infrastructure
  create_vnet         = false
  create_nodes_subnet = false
  create_nat          = false
  vnet_name           = azurerm_virtual_network.shared.name
  vnet_resource_group = azurerm_resource_group.this.name
  nodes_subnet_name   = azurerm_subnet.ctrl_plane.name
  nat_gateway_id      = azurerm_nat_gateway.shared.id

  identity_name = "${var.ctrl_cluster_name}-id"

  # No bastion - use VPN/ExpressRoute for cluster access
  enable_bastion        = false
  create_bastion_subnet = false

  # Overlay networking - pods get IPs from virtual pod_cidr, not node subnet
  # This allows dense pod packing without exhausting node subnet IPs
  network_profile = {
    network_plugin_mode = "overlay"
    service_cidr        = "172.20.0.0/16" # Cluster-internal service IPs
    dns_service_ip      = "172.20.0.10"   # CoreDNS service IP
    pod_cidr            = "10.144.0.0/16" # Virtual pod network (overlay)
  }

  node_pools = {
    system = {
      name       = "system"
      type       = "system"
      node_count = var.system_node_count
      vm_size    = var.system_node_vm_size
    }
    platform = {
      name       = "platform"
      type       = "user"
      node_count = var.workload_node_count
      vm_size    = var.workload_node_vm_size
      labels = {
        "quix.io/node-purpose" = "platform-services"
      }
    }
  }

  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  tags = merge(var.tags, {
    role = "control-plane"
  })

  depends_on = [
    azurerm_subnet_nat_gateway_association.ctrl_plane,
    azurerm_subnet_network_security_group_association.ctrl_plane
  ]
}

################################################################################
# Data Plane Cluster
# Runs customer workloads and deployments
################################################################################

module "aks_data" {
  source = "../../modules/quix-aks"

  name                    = var.data_cluster_name
  location                = azurerm_resource_group.this.location
  resource_group_name     = azurerm_resource_group.this.name
  create_resource_group   = false
  kubernetes_version      = var.kubernetes_version
  sku_tier                = "Standard"
  private_cluster_enabled = true

  # BYO networking - use shared infrastructure
  create_vnet         = false
  create_nodes_subnet = false
  create_nat          = false
  vnet_name           = azurerm_virtual_network.shared.name
  vnet_resource_group = azurerm_resource_group.this.name
  nodes_subnet_name   = azurerm_subnet.data_plane.name
  nat_gateway_id      = azurerm_nat_gateway.shared.id

  identity_name = "${var.data_cluster_name}-id"

  # No bastion - use VPN/ExpressRoute for cluster access
  enable_bastion        = false
  create_bastion_subnet = false

  # Overlay networking with DIFFERENT CIDRs than control plane
  # This enables potential cross-cluster communication without IP conflicts
  network_profile = {
    network_plugin_mode = "overlay"
    service_cidr        = "172.21.0.0/16" # Different from ctrl (172.20.x)
    dns_service_ip      = "172.21.0.10"
    pod_cidr            = "10.145.0.0/16" # Different from ctrl (10.144.x)
  }

  node_pools = {
    system = {
      name       = "system"
      type       = "system"
      node_count = var.system_node_count
      vm_size    = var.system_node_vm_size
    }
    deployments = {
      name       = "deployments"
      type       = "user"
      node_count = var.workload_node_count
      vm_size    = var.workload_node_vm_size
      labels = {
        "quix.io/node-purpose" = "customer-deployments"
      }
    }
  }

  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  tags = merge(var.tags, {
    role = "data-plane"
  })

  depends_on = [
    azurerm_subnet_nat_gateway_association.data_plane,
    azurerm_subnet_network_security_group_association.data_plane
  ]
}
