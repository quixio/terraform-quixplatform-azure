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
  kubernetes_version      = "1.33.5"
  sku_tier                = "Standard"
  private_cluster_enabled = false

  vnet_name          = "vnet-quix-public"
  vnet_address_space = ["10.240.0.0/16"]
  nodes_subnet_name  = "Subnet-Nodes"
  nodes_subnet_cidr  = "10.240.0.0/22"

  identity_name     = "quix-public-nat-id"
  public_ip_name    = "quix-public-nat-ip"
  nat_gateway_name  = "quix-public-nat"
  availability_zone = "1"

  enable_credentials_fetch = true

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
      labels     = { "quix.io/node-purpose" = "platform-services" }
    }
    deployments = {
      name       = "deployments"
      type       = "user"
      node_count = 3
      vm_size    = "Standard_E4ds_v5"
      labels     = { "quix.io/node-purpose" = "customer-deployments" }
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


