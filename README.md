# Terraform Modules (Azure)

![Terraform](https://img.shields.io/badge/Terraform-7B42BC?style=for-the-badge&logo=terraform&logoColor=white)
![Azure](https://img.shields.io/badge/Azure-0078D4?style=for-the-badge&logo=microsoftazure&logoColor=white)
![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white)

Repository of production-ready Terraform modules for installing quix-platform.

## Structure

- `modules/quix-aks/` (AKS module)
  - `main.tf`: resource group wiring and common locals
  - `network.tf`: VNet, nodes subnet, NAT Gateway and identity
  - `aks.tf`: AKS cluster + dynamic node pools
  - `rbac.tf`: role assignments for the managed identity
  - `bastion.tf`: Azure Bastion + jumpbox (optional)
  - `README.md`: terraform-docs generated documentation
- `modules/tiered-storage/` (Tiered Storage module)
  - `main.tf`: Storage Account, federated identity credentials, role assignment for kubelet identity
  - `README.md`: terraform-docs generated documentation
- `modules/nfs-storage/` (NFS Storage module)
  - `main.tf`: Azure Files Premium (NFS 4.1), Private Endpoint, network security rules
  - `README.md`: module documentation
- `examples/` usage examples
  - `public-quix-infr/`: public cluster
  - `private-quix-infr/`: private cluster with Bastion + jumpbox
  - `public-quix-infr-tiered-storage/`: public cluster + tiered-storage module
  - `public-quix-infr-nfs-storage/`: public cluster + nfs-storage module
  - `private-quix-infr-external-vnet/`: private cluster using external VNet/Subnets, external NAT (BYO), and Bastion subnet
- `BASTION_ACCESS.md`: how to access a private AKS via Bastion

## AKS module (quix-aks)

Module documentation (inputs/outputs/resources):

- [modules/quix-aks/README.md](modules/quix-aks/README.md) (generated with terraform-docs)

Regenerate docs (requires `terraform-docs`):

```bash
cd modules/quix-aks
terraform-docs markdown table --output-file README.md --output-mode inject .
```

### Bring Your Own NAT (BYO NAT)

You can use an external NAT Gateway instead of creating one:

```hcl
module "quix_aks" {
  # ...
  create_nat     = false
  nat_gateway_id = azurerm_nat_gateway.external.id
}
```

### Private DNS Zone for Private Clusters

When deploying a private AKS cluster, you can control how the Private DNS Zone is managed using the `private_dns_zone_id` variable:

```hcl
module "quix_aks" {
  # ...
  private_cluster_enabled = true
  
  # Option 1: Let AKS manage the Private DNS Zone automatically (default)
  private_dns_zone_id = "System"
  
  # Option 2: Disable Private DNS Zone management (manual DNS configuration required)
  # private_dns_zone_id = "None"
  
  # Option 3: Use an existing Private DNS Zone (BYO)
  # private_dns_zone_id = "/subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.Network/privateDnsZones/privatelink.<region>.azmk8s.io"
}
```

**Note:** When using an existing Private DNS Zone (Option 3), the module automatically assigns the `Private DNS Zone Contributor` role to the AKS cluster identity.

## Tiered Storage module (tiered-storage)

Azure Blob Storage with workload identity federation for Quix tiered storage.

Module documentation (inputs/outputs/resources):

- [modules/tiered-storage/README.md](modules/tiered-storage/README.md) (generated with terraform-docs)

Regenerate docs (requires `terraform-docs`):

```bash
cd modules/tiered-storage
terraform-docs markdown table --output-file README.md --output-mode inject .
```

## NFS Storage module (nfs-storage)

Azure Files Premium with NFS 4.1 support, secured with Private Endpoint and network security rules.

**Features:**
- Azure Files Premium (NFS 4.1) for high-performance file storage
- Private Endpoint for secure VNet connectivity
- Network security rules with default deny policy
- Auto DNS zone creation for `privatelink.file.core.windows.net`
- Multiple NFS shares support

Module documentation:

- [modules/nfs-storage/README.md](modules/nfs-storage/README.md)

**Quick example:**

```hcl
module "nfs_storage" {
  source = "./modules/nfs-storage"

  resource_group_name  = "rg-myapp"
  location             = "westeurope"
  storage_account_name = "mystorageaccount01"

  # Private Endpoint configuration
  private_endpoint_subnet_id = azurerm_subnet.private_endpoints.id
  vnet_id                    = azurerm_virtual_network.main.id

  # Network Security Rules - Default deny policy
  allowed_subnet_ids   = [azurerm_subnet.aks_nodes.id]
  allowed_ip_addresses = ["1.2.3.4"]  # Your public IP

  nfs_shares = [
    {
      name     = "shared-data"
      quota_gb = 100
    }
  ]
}
```

**Mounting NFS shares:**

```bash
sudo mount -t nfs -o vers=4.1,sec=sys \
  mystorageaccount01.privatelink.file.core.windows.net:/mystorageaccount01/shared-data \
  /mnt/shared-data
```

## Examples

Public cluster:

```bash
cd examples/public-quix-infr
terraform init
terraform apply
```

Private cluster (with Bastion):

```bash
cd examples/private-quix-infr
terraform init
terraform apply
```

Public cluster with Tiered Storage:

```bash
cd examples/public-quix-infr-tiered-storage
terraform init
terraform apply
```

Public cluster with NFS Storage:

```bash
cd examples/public-quix-infr-nfs-storage
terraform init
terraform apply
```

External VNet + external NAT + Bastion subnet:

```bash
cd examples/private-quix-infr-external-vnet
terraform init
terraform apply
```

Access a private AKS: see `BASTION_ACCESS.md`.

## Requirements

- Terraform >= 1.5.0
- AzureRM Provider >= 3.112.0, < 4.0.0
- Azure CLI

## Module versioning

Publish SemVer tags and reference the module with `?ref=vX.Y.Z` when consuming from git.

### Using this module from another repo with a Git tag

HTTPS example:

```hcl
module "quix_aks" {
  source = "git::https://github.com/quixio/terraform-quixplatform-azure.git//modules/quix-aks?ref=0.0.2"

  name                 = "my-aks"
  location             = "westeurope"
  resource_group_name  = "rg-my-aks"
  create_resource_group = true

  vnet_name          = "vnet-my-aks"
  vnet_address_space = ["10.240.0.0/16"]
  nodes_subnet_name  = "Subnet-Nodes"
  nodes_subnet_cidr  = "10.240.0.0/22"

  identity_name = "my-nat-id"
  public_ip_name    = "my-nat-ip"
  nat_gateway_name  = "my-nat"
  availability_zone = "1"

  kubernetes_version = "1.32.4"
  network_profile = {
    network_plugin_mode = "vnet"
    service_cidr        = "172.22.0.0/16"
    dns_service_ip      = "172.22.0.10"
  }

  node_pools = {
    default = {
      name       = "default"
      type       = "system"
      node_count = 1
      vm_size    = "Standard_D4ds_v5"
    }
  }
}
```

SSH example:

```hcl
module "quix_aks" {
  source = "git::ssh://git@github.com/quixio/terraform-quixplatform-azure.git//modules/quix-aks?ref=0.0.2"
  # ...same inputs as above
}
```