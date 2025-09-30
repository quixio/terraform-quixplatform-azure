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

module "aks" {
  source = "../../modules/quix-aks"

  name                = "quix-aks-private"
  location            = "westeurope"
  resource_group_name = "rg-quix-private"
  create_resource_group = false
  kubernetes_version  = "1.32.4"
  sku_tier            = "Standard"
  private_cluster_enabled = true

  vnet_name          = "vnet-quix-private"
  vnet_address_space = ["10.240.0.0/16"]
  nodes_subnet_name  = "Subnet-Nodes"
  nodes_subnet_cidr  = "10.240.0.0/22"

  nat_identity_name = "quix-private-nat-id"
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
      quix_controller = {
        name       = "quixcontroller"
        type       = "user"
        node_count = 1
        vm_size    = "Standard_D4ds_v5"
        taints     = ["dedicated=controller:NoSchedule"]
        labels     = { role = "controller" }
      }
    }

  network_profile = {
    network_plugin_mode = "overlay"
    service_cidr        = "172.22.0.0/16"
    dns_service_ip      = "172.22.0.10"
    pod_cidr            = "10.144.0.0/16"
  }

  enable_bastion         = true
  bastion_subnet_cidr    = "10.240.5.0/27"
  bastion_name           = "quix-bastion"
  bastion_public_ip_name = "quix-bastion-ip"

  jumpbox_name           = "quix-jumpbox"
  jumpbox_vm_size        = "Standard_B2s"
  jumpbox_admin_username = "azureuser"
  jumpbox_ssh_public_key = "ssh-rsa ......"

  oidc_issuer_enabled       = true
  workload_identity_enabled = true


  tags = {
    environment = "demo"
    project     = "Quix"
  }

  depends_on = [azurerm_resource_group.this]
}


