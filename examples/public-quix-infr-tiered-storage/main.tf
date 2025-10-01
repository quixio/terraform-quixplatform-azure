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

module "aks" {
  source = "../../modules/quix-aks"

  name                    = "quix-aks-public"
  location                = "westeurope"
  resource_group_name     = "rg-quix-public"
  create_resource_group   = true
  kubernetes_version      = "1.32.4"
  sku_tier                = "Standard"
  private_cluster_enabled = false

  vnet_name          = "vnet-quix-public"
  vnet_address_space = ["10.240.0.0/16"]
  nodes_subnet_name  = "Subnet-Nodes"
  nodes_subnet_cidr  = "10.240.0.0/22"

  nat_identity_name = "quix-public-nat-id"
  public_ip_name    = "quix-public-nat-ip"
  nat_gateway_name  = "quix-public-nat"
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

module "tiered_storage" {
  source = "../../modules/tiered-storage"

  resource_group_name        = module.aks.resource_group_name
  location                   = module.aks.resource_group_location
  storage_account_name       = "quixstorpublic01" # must be globally unique
  cluster_name               = module.aks.cluster_name
  aks_oidc_issuer_url        = module.aks.oidc_issuer_url
  kubelet_identity_object_id = module.aks.kubelet_identity_object_id

  # Use the cluster managed identity client/resource from AKS module
  cluster_identity_resource_id = module.aks.cluster_identity_resource_id

  federated_bindings = [
    { namespace = "default",   service_account_name = "tiered-storage-sa" },
    { namespace = "analytics", service_account_name = "tiered-storage-sa" }
  ]

  tags = {
    environment = "demo"
    project     = "Quix"
  }
}


