################################################################################
# Airgap Test Cluster - Quix BYOC SOC2 Testing
#
# Ticket: 70784
# Purpose: Automated testing of airgapped Quix deployments
#
# This configuration creates:
# - AKS cluster with spot instances for cost savings
# - NSG rules for egress filtering (only allow quixregistry.azurecr.io + essentials)
# - All resources tagged for easy cleanup
#
# IMPORTANT: This is for ephemeral test clusters only. Resources are designed
# to be created and destroyed automatically by CI/CD pipelines.
#
# Network approach: NSG-based filtering (cheaper than Azure Firewall)
# - Allow specific Azure service tags for ACR, Storage, AKS management
# - Deny all other internet traffic
# - quixregistry.azurecr.io is in francecentral, so we allow that region
################################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.112"
    }
  }

  # Backend configured via -backend-config in CI/CD
  # For local testing: omit -backend-config flags to use local state
  # For CI/CD: pass -backend-config="resource_group_name=..." etc.
  backend "azurerm" {}
}

provider "azurerm" {
  features {}
}

################################################################################
# Local Values
################################################################################

locals {
  # Naming convention: all resources include run_id for isolation
  resource_group_name = "rg-quix-airgap-${var.run_id}"
  cluster_name        = "aks-airgap-${var.run_id}"

  # Network configuration
  vnet_address_space = ["10.240.0.0/16"]
  nodes_subnet_cidr  = "10.240.0.0/22" # /22 = 1024 IPs for AKS nodes

  # Common tags for all resources - enables orphan detection
  # Note: created_at removed to prevent constant tag drift on every apply
  common_tags = {
    run_id      = var.run_id
    purpose     = "airgap-test"
    owner       = "pipeline"
    ticket      = "70784"
    temporary   = "true"
    managed_by  = "terraform"
    environment = "development"
  }
}

################################################################################
# Resource Group
################################################################################

resource "azurerm_resource_group" "this" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

################################################################################
# Virtual Network
################################################################################

resource "azurerm_virtual_network" "this" {
  name                = "vnet-airgap-${var.run_id}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = local.vnet_address_space
  tags                = local.common_tags
}

resource "azurerm_subnet" "nodes" {
  name                 = "snet-aks-nodes"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [local.nodes_subnet_cidr]

  service_endpoints = [
    "Microsoft.ContainerRegistry",
    "Microsoft.Storage",
    "Microsoft.KeyVault",
    "Microsoft.AzureActiveDirectory",
  ]
}

################################################################################
# Network Security Group - Airgap Rules
#
# IMPORTANT: The NSG association is applied AFTER the cluster and node pools
# are created. AKS nodes require unrestricted internet access during bootstrap
# to pull system images and register with the control plane. Once nodes are
# ready, the NSG is applied to enforce airgap restrictions.
#
# Key insight from testing:
# - quixregistry.azurecr.io is in francecentral
# - MCR (mcr.microsoft.com) uses CDN IPs outside Azure ranges
# - Need to allow HTTPS (443) to Internet before DenyInternet rule
################################################################################

resource "azurerm_network_security_group" "aks" {
  name                = "nsg-aks-airgap-${var.run_id}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.common_tags

  # Priority ordering:
  # 100-199: Core protocols (DNS, NTP)
  # 200-289: Azure services
  # 290: HTTPS to Internet (needed for MCR CDN)
  # 300: VNet internal
  # 4000: Deny all other Internet

  # DNS - required for name resolution
  security_rule {
    name                       = "AllowDNS"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "53"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # NTP - required for time sync
  security_rule {
    name                       = "AllowNTP"
    priority                   = 110
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Udp"
    source_port_range          = "*"
    destination_port_range     = "123"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Azure Cloud - AKS management, ARM, etc. (global, not regional)
  security_rule {
    name                       = "AllowAzureCloud"
    priority                   = 200
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "AzureCloud"
  }

  # ACR - westeurope (where AKS is)
  security_rule {
    name                       = "AllowACR-WestEurope"
    priority                   = 210
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "AzureContainerRegistry.${var.location}"
  }

  # ACR - francecentral (where quixregistry.azurecr.io is located)
  security_rule {
    name                       = "AllowACR-FranceCentral"
    priority                   = 211
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "AzureContainerRegistry.francecentral"
  }

  # Storage - westeurope
  security_rule {
    name                       = "AllowStorage-WestEurope"
    priority                   = 220
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["443", "445"]
    source_address_prefix      = "*"
    destination_address_prefix = "Storage.${var.location}"
  }

  # Storage - francecentral (for quixregistry blob storage)
  security_rule {
    name                       = "AllowStorage-FranceCentral"
    priority                   = 221
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "Storage.francecentral"
  }

  # Azure AD - authentication
  security_rule {
    name                       = "AllowAAD"
    priority                   = 230
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "AzureActiveDirectory"
  }

  # MCR - Microsoft Container Registry
  security_rule {
    name                       = "AllowMCR"
    priority                   = 240
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "MicrosoftContainerRegistry"
  }

  # AKS tunnel (UDP 1194, TCP 9000)
  security_rule {
    name                       = "AllowAKSTunnel"
    priority                   = 250
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_ranges    = ["1194", "9000"]
    source_address_prefix      = "*"
    destination_address_prefix = "AzureCloud.${var.location}"
  }

  # MCR CDN - Microsoft Container Registry uses Akamai/Azure Front Door CDN
  # IPs are outside Azure service tags (e.g., 150.171.x.x)
  # This is more restrictive than allowing all HTTPS to Internet
  security_rule {
    name                       = "AllowMCR-CDN"
    priority                   = 245
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefixes = [
      "150.171.0.0/16",  # Akamai CDN range used by MCR
      "20.0.0.0/8",      # Azure-owned IP range (Front Door, etc.)
    ]
  }

  # VNet internal traffic
  security_rule {
    name                       = "AllowVNet"
    priority                   = 300
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  # Deny all other Internet traffic
  # Only Azure services, MCR CDN, and VNet traffic are allowed above
  # This blocks external registries (Docker Hub, Quay, GitHub, PyPI, etc.)
  security_rule {
    name                       = "DenyInternet"
    priority                   = 4000
    direction                  = "Outbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "Internet"
  }
}

# NOTE: This association is created AFTER the cluster and node pools are ready.
# AKS nodes need unrestricted internet during bootstrap. The NSG is applied
# afterwards to enforce airgap restrictions for runtime workloads.
resource "azurerm_subnet_network_security_group_association" "aks" {
  subnet_id                 = azurerm_subnet.nodes.id
  network_security_group_id = azurerm_network_security_group.aks.id

  depends_on = [
    azurerm_kubernetes_cluster_node_pool.workload,
  ]
}

################################################################################
# User Assigned Identity for AKS
################################################################################

resource "azurerm_user_assigned_identity" "aks" {
  name                = "id-aks-airgap-${var.run_id}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.common_tags
}

# AKS needs Network Contributor on the VNet
resource "azurerm_role_assignment" "aks_vnet" {
  scope                = azurerm_virtual_network.this.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks.principal_id
}

# AKS needs Network Contributor on the subnet
resource "azurerm_role_assignment" "aks_subnet" {
  scope                = azurerm_subnet.nodes.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks.principal_id
}

# AKS kubelet needs AcrPull on the container registry to pull images
resource "azurerm_role_assignment" "aks_acr" {
  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id

  depends_on = [azurerm_kubernetes_cluster.this]
}

################################################################################
# AKS Cluster
################################################################################

resource "azurerm_kubernetes_cluster" "this" {
  name                = local.cluster_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  dns_prefix          = "airgap-${var.run_id}"
  kubernetes_version  = var.kubernetes_version
  sku_tier            = "Standard"

  default_node_pool {
    name           = "system"
    node_count     = 2  # 2 nodes needed to run full platform (monitoring, kafka, etc.)
    vm_size        = var.system_node_vm_size
    vnet_subnet_id = azurerm_subnet.nodes.id
    max_pods       = 250

    upgrade_settings {
      max_surge                     = "10%"
      drain_timeout_in_minutes      = 0
      node_soak_duration_in_minutes = 0
    }
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aks.id]
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_policy      = "calico"
    service_cidr        = "172.22.0.0/16"
    dns_service_ip      = "172.22.0.10"
    outbound_type       = "loadBalancer" # Use LB for outbound, NSG filters traffic
  }

  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  tags = local.common_tags

  # NOTE: We intentionally do NOT depend on the NSG association here.
  # The NSG is applied AFTER the cluster is ready to avoid blocking bootstrap.
  depends_on = [
    azurerm_role_assignment.aks_vnet,
    azurerm_role_assignment.aks_subnet,
  ]
}

################################################################################
# Spot Instance Node Pool (for workloads - cost savings)
################################################################################

resource "azurerm_kubernetes_cluster_node_pool" "workload" {
  name                  = "workload"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.this.id
  vm_size               = var.workload_node_vm_size
  node_count            = var.workload_node_count
  vnet_subnet_id        = azurerm_subnet.nodes.id
  mode                  = "User"
  max_pods              = 250
  orchestrator_version  = var.kubernetes_version

  # Spot instances for cost savings (~60-80% cheaper)
  # NOTE: No taints applied - pods schedule freely without needing tolerations
  # The spot label is still applied for visibility but doesn't block scheduling
  priority        = "Spot"
  eviction_policy = "Delete"
  spot_max_price  = -1 # Pay up to on-demand price

  node_labels = {
    "kubernetes.azure.com/scalesetpriority" = "spot"
  }

  # Intentionally NOT setting node_taints - this allows all pods to schedule
  # without requiring tolerations in every helm chart and operator

  tags = local.common_tags
}
