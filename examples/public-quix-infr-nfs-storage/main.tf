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
# Get current public IP (for Terraform operations)
################################################################################

data "http" "my_public_ip" {
  url = "https://api.ipify.org?format=text"
}

module "aks" {
  source = "../../modules/quix-aks"

  name                    = "quix-aks-nfs"
  location                = "westeurope"
  resource_group_name     = "rg-quix-nfs"
  create_resource_group   = true
  kubernetes_version      = "1.32.4"
  sku_tier                = "Standard"
  private_cluster_enabled = false

  vnet_name          = "vnet-quix-nfs"
  vnet_address_space = ["10.240.0.0/16"]
  nodes_subnet_name  = "Subnet-Nodes"
  nodes_subnet_cidr  = "10.240.0.0/22"

  identity_name     = "quix-nfs-nat-id"
  public_ip_name    = "quix-nfs-nat-ip"
  nat_gateway_name  = "quix-nfs-nat"
  availability_zone = "1"

  enable_credentials_fetch = true

  node_pools = {
    default = {
      name       = "default"
      type       = "system"
      node_count = 1
      vm_size    = "Standard_D4ds_v5"
    },
    quix_controller = {
      name       = "quixcontroller"
      type       = "user"
      node_count = 1
      vm_size    = "Standard_D4ds_v5"
      taints     = ["dedicated=controller:NoSchedule"]
      labels     = { role = "controller" }
    }
    quix_deployments = {
      name       = "quixdeployment"
      type       = "user"
      node_count = 1
      vm_size    = "Standard_D4ds_v5"
      taints     = ["dedicated=controller:NoSchedule"]
      labels     = { role = "controller" }
    }
  }

  network_profile = {
    network_plugin_mode = "vnet"
    service_cidr        = "172.22.0.0/16"
    dns_service_ip      = "172.22.0.10"
  }

  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  tags = {
    environment = "demo"
    project     = "Quix"
  }
}

################################################################################
# Private Endpoint Subnet
################################################################################

resource "azurerm_subnet" "private_endpoints" {
  name                 = "Subnet-PrivateEndpoints"
  resource_group_name  = module.aks.resource_group_name
  virtual_network_name = module.aks.vnet_name
  address_prefixes     = ["10.240.4.0/24"]
}

################################################################################
# NFS Storage Module (with Private Link and Network Security Rules)
################################################################################

module "nfs_storage" {
  source = "../../modules/nfs-storage"

  resource_group_name  = module.aks.resource_group_name
  location             = module.aks.resource_group_location
  storage_account_name = "quixnfsstor01" # must be globally unique

  # Private Endpoint configuration
  private_endpoint_subnet_id = azurerm_subnet.private_endpoints.id

  # VNet ID for automatic Private DNS Zone creation and linking
  # The module will automatically create privatelink.file.core.windows.net
  vnet_id = module.aks.vnet_id

  # Network Security Rules - Default deny policy
  # Allow access from AKS nodes subnet for NFS mounting
  allowed_subnet_ids = [module.aks.nodes_subnet_id]

  # Allow current public IP for Terraform operations (creating shares, destroy)
  # Automatically detected from https://api.ipify.org
  # Note: ip_rules accepts individual IPs without CIDR notation
  allowed_ip_addresses = [trimspace(data.http.my_public_ip.response_body)]

  # Network bypass - Azure services can bypass firewall
  network_bypass = ["AzureServices"]

  # Create NFS shares
  nfs_shares = [
    {
      name     = "sharedpvc"
      quota_gb = 200
      metadata = {
        purpose = "shared-datapvc"
      }
    }
  ]

  tags = {
    environment = "demo"
    project     = "Quix"
    storage     = "nfs"
  }
}
