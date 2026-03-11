################################################################################
# Dev Environment Cluster (dev1-dev5)
#
# Persistent named dev clusters for Quix BYOC development.
# No NSG egress lockdown - these are standard internet-connected clusters.
#
# Resources:
# - AKS cluster (public, Standard tier)
# - VNet with NAT Gateway
# - User-assigned identity with Network Contributor
#
# Usage:
#   terraform apply -var env_name=dev1
#   terraform destroy -var env_name=dev1
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
  backend "azurerm" {}
}

provider "azurerm" {
  features {}
}

################################################################################
# AKS Cluster via quix-aks module
################################################################################

module "aks" {
  source = "../../modules/quix-aks"

  name                    = "aks-quix-${var.env_name}"
  location                = var.location
  resource_group_name     = "rg-quix-${var.env_name}"
  create_resource_group   = true
  kubernetes_version      = var.kubernetes_version
  sku_tier                = "Standard"
  private_cluster_enabled = false

  vnet_name          = "vnet-quix-${var.env_name}"
  vnet_address_space = ["10.240.0.0/16"]
  nodes_subnet_name  = "snet-aks-nodes"
  nodes_subnet_cidr  = "10.240.0.0/22"

  identity_name     = "id-aks-quix-${var.env_name}"
  public_ip_name    = "pip-nat-quix-${var.env_name}"
  nat_gateway_name  = "nat-quix-${var.env_name}"
  availability_zone = "1"

  enable_credentials_fetch = false

  node_pools = {
    system = {
      name       = "system"
      type       = "system"
      node_count = 1
      vm_size    = var.system_node_vm_size
    }
    workload = {
      name       = "workload"
      type       = "user"
      node_count = var.workload_node_count
      vm_size    = var.workload_node_vm_size
    }
  }

  network_profile = {
    network_plugin_mode = "overlay"
    service_cidr        = "172.22.0.0/16"
    dns_service_ip      = "172.22.0.10"
    network_policy      = "calico"
    outbound_type       = "userAssignedNATGateway"
  }

  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  tags = {
    environment = var.env_name
    purpose     = "dev-environment"
    persistent  = "true"
    managed_by  = "terraform"
  }
}

################################################################################
# ACR Pull role assignment (kubelet identity -> quixcontainerregistry)
################################################################################

resource "azurerm_role_assignment" "aks_acr" {
  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = module.aks.kubelet_identity_object_id
}
