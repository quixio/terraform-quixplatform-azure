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

  # Core + RG
  name                    = "quix-aks-private"
  location                = "westeurope"
  resource_group_name     = "rg-quix-private"
  create_resource_group   = false
  kubernetes_version      = "1.32.4"
  sku_tier                = "Standard"
  private_cluster_enabled = true
  # Use existing Private DNS Zone for the AKS private API server:
  #   - "System" lets AKS manage it automatically (default)
  #   - "None" disables creation/association (you must manage DNS yourself)
  #   - "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Network/privateDnsZones/privatelink.westeurope.azmk8s.io"
  #     to reuse an existing zone
  private_dns_zone_id = "System"

  # Networking (VNet/Subnet)
  vnet_name          = "vnet-quix-private"
  vnet_address_space = ["10.240.0.0/16"]
  nodes_subnet_name  = "Subnet-Nodes"
  nodes_subnet_cidr  = "10.240.0.0/22"

  # Network profile
  network_profile = {
    network_plugin_mode = "overlay"
    service_cidr        = "172.22.0.0/16"
    dns_service_ip      = "172.22.0.10"
    pod_cidr            = "10.144.0.0/16"
  }

  # NAT (names reserved even if not used with userDefinedRouting)
  identity_name     = "quix-private-nat-id"
  public_ip_name    = "quix-private-nat-ip"
  nat_gateway_name  = "quix-private-nat"
  availability_zone = "2"

  # Bastion
  create_bastion_subnet  = true
  enable_bastion         = true
  bastion_subnet_cidr    = "10.240.5.0/27"
  bastion_name           = "quix-bastion"
  bastion_public_ip_name = "quix-bastion-ip"

  # Jumpbox
  jumpbox_name           = "quix-jumpbox"
  jumpbox_vm_size        = "Standard_B2s"
  jumpbox_admin_username = "azureuser"
  jumpbox_ssh_public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC3Zz+tHUEI7ulzE69GxtLwi9DOvROBG4aI7h3za2FAP6Ya9/GhG2zcBiKOzk3SlKavE3/5NomgGifTC/ica6rTPlpb4U5oky/2phs9AtczVVI2G+yNC43hJzVhWbqKT3qAGGCGEm2+Cpxx7spKEbZAfAcq5GxL3k9kTcpaQEv3hpVvqK3zlCziHyahUv1pxQGuX3b2hqi4idgFX3m0FaqU98DtQu/I9x95jXHrb7Wltp3sbTSKCDxGo3nk4plpzILs/OqTMSPpfxwarCXA1ZtU82hyWO4Szn2U4I+MbuNaO/dso1oNlprqJQgsQ8t+hawCdIHeZ00M/QELdnYldBjo1jM19AT1OwMcB7PP7GRTNv7YsDW10YCvX9XRPab66PIKpe5R4IG/n6TzEwUP2pb4hRJWvnPJzrHK5HEJg7G7baCEyjCtaWkL4M7dBxIGJ3sp9IfjdeztV2Llh+hYmwPefTejprER+Q/qHZTNr1wEW4BV0TQQd+jeqdIL4QkIno3IyM3IBX+uPM/WlSpi2sT+hDqiUcCRu/x21O/bVYz/UbeHIqptRDfGc5rVoAN/zc/kGsGeGuP3auyI6aQxlnU0wMDdyS8rf3SpWagOB2UFNxZSuU2gnYdtz2uWG4vF75Sqr04MFJImHIY4N7gHJrvdarg6YBaDDnmdREcqp3ooAw=="

  # Features
  oidc_issuer_enabled       = true
  workload_identity_enabled = true
  enable_credentials_fetch  = true

  # Node pools
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

  # Tags
  tags = {
    environment = "demo"
    project     = "Quix"
  }

  # Dependencies
  depends_on = [azurerm_resource_group.this]
}


