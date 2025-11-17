# Azure NFS Storage Module

Terraform module to deploy Azure File Storage with NFS 4.1 support, secured with Private Endpoint and network security rules.

## Features

- **Azure Files Premium (NFS 4.1)**: High-performance file storage with native Linux NFS support
- **Private Endpoint**: Secure private connectivity from VNet without public internet exposure
- **Network Security Rules**: Default deny policy with explicit subnet and IP allowlists
- **Auto DNS Zone Creation**: Automatically creates and links Private DNS Zone if not provided
- **Multiple NFS Shares**: Support for creating multiple file shares with different quotas

## Architecture

This module deploys:

1. **Storage Account** (Premium FileStorage, LRS) - Optimized for NFS with low latency
2. **Network Security Rules** - Default deny with explicit allowlist for subnets and IPs
3. **Private Endpoint** - Maps storage to private IP inside VNet
4. **Private DNS Zone** (optional) - Auto-created `privatelink.file.core.windows.net` for easy DNS resolution
5. **NFS File Shares** - One or more NFS 4.1 shares for mounting

## Usage

### Basic Example

```hcl
module "nfs_storage" {
  source = "../../modules/nfs-storage"

  resource_group_name  = "rg-myapp"
  location             = "westeurope"
  storage_account_name = "mystorageaccount01"

  # Private Endpoint configuration
  private_endpoint_subnet_id = azurerm_subnet.private_endpoints.id

  # VNet for auto DNS zone creation
  vnet_id = azurerm_virtual_network.main.id

  # Network Security Rules - Default deny policy
  allowed_subnet_ids   = [azurerm_subnet.aks_nodes.id]
  allowed_ip_addresses = ["1.2.3.4"]  # Your public IP for Terraform operations

  # Create NFS shares
  nfs_shares = [
    {
      name     = "shared-data"
      quota_gb = 100
    }
  ]

  tags = {
    environment = "production"
  }
}
```

### With Automatic Public IP Detection

```hcl
data "http" "my_public_ip" {
  url = "https://api.ipify.org?format=text"
}

module "nfs_storage" {
  source = "../../modules/nfs-storage"

  resource_group_name  = "rg-myapp"
  location             = "westeurope"
  storage_account_name = "mystorageaccount01"

  private_endpoint_subnet_id = azurerm_subnet.private_endpoints.id
  vnet_id                    = azurerm_virtual_network.main.id

  allowed_subnet_ids   = [azurerm_subnet.aks_nodes.id]
  allowed_ip_addresses = [trimspace(data.http.my_public_ip.response_body)]

  nfs_shares = [
    {
      name     = "shared-data"
      quota_gb = 100
      metadata = {
        purpose = "application-data"
      }
    }
  ]
}
```

### Using Existing Private DNS Zone

```hcl
module "nfs_storage" {
  source = "../../modules/nfs-storage"

  resource_group_name  = "rg-myapp"
  location             = "westeurope"
  storage_account_name = "mystorageaccount01"

  private_endpoint_subnet_id = azurerm_subnet.private_endpoints.id

  # Use existing DNS zone instead of auto-creating
  private_dns_zone_ids = [azurerm_private_dns_zone.storage.id]

  allowed_subnet_ids   = [azurerm_subnet.aks_nodes.id]
  allowed_ip_addresses = ["1.2.3.4"]

  nfs_shares = [
    {
      name     = "shared-data"
      quota_gb = 100
    }
  ]
}
```

## Mounting NFS Shares

From a Linux VM inside the allowed subnet:

```bash
# Create mount point
sudo mkdir -p /mnt/shared-data

# Mount the NFS share
sudo mount -t nfs -o vers=4.1,sec=sys \
  mystorageaccount01.privatelink.file.core.windows.net:/mystorageaccount01/shared-data \
  /mnt/shared-data

# Verify mount
df -h | grep shared-data
```

### Persistent Mount (fstab)

Add to `/etc/fstab`:

```
mystorageaccount01.privatelink.file.core.windows.net:/mystorageaccount01/shared-data /mnt/shared-data nfs vers=4.1,sec=sys 0 0
```

## Network Security

The module implements a **default deny policy**:

- All public access is denied by default
- Access is only allowed from:
  - **Allowed subnets** (e.g., AKS nodes subnet)
  - **Allowed IP addresses** (e.g., your public IP for Terraform operations)
  - **Azure Services** (if `network_bypass` includes "AzureServices")

### Why Allow Public IP?

When you run `terraform apply` or `terraform destroy` from outside the VNet, Terraform needs to make data-plane calls to create/delete NFS shares. Adding your public IP to `allowed_ip_addresses` enables these operations.

**Options:**
1. Add your public IP temporarily (manually or via `data "http"`)
2. Run Terraform from inside the VNet (e.g., from a VM or Azure DevOps agent)
3. Use Azure Bastion or VPN to access resources

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `resource_group_name` | Resource group name | `string` | n/a | yes |
| `location` | Azure region | `string` | n/a | yes |
| `storage_account_name` | Storage account name (globally unique, 3-24 lowercase alphanumeric chars) | `string` | n/a | yes |
| `private_endpoint_subnet_id` | Subnet ID for Private Endpoint | `string` | n/a | yes |
| `vnet_id` | VNet ID for auto DNS zone creation (required if `private_dns_zone_ids` not provided) | `string` | `null` | no |
| `private_dns_zone_ids` | List of Private DNS Zone IDs. If not provided, module creates one automatically | `list(string)` | `[]` | no |
| `allowed_subnet_ids` | List of subnet IDs allowed to access storage (e.g., AKS nodes) | `list(string)` | `[]` | no |
| `allowed_ip_addresses` | List of IP addresses allowed to access storage (without CIDR, e.g., "1.2.3.4") | `list(string)` | `[]` | no |
| `network_bypass` | Services that can bypass network rules | `list(string)` | `["AzureServices"]` | no |
| `nfs_shares` | List of NFS file shares to create | `list(object)` | `[]` | no |
| `tags` | Tags to apply to resources | `map(string)` | `{}` | no |

### NFS Shares Object

```hcl
nfs_shares = [
  {
    name        = string           # Share name
    quota_gb    = number           # Quota in GB
    access_tier = string           # Optional: "Hot", "Cool", "TransactionOptimized"
    metadata    = map(string)      # Optional: metadata tags
  }
]
```

## Outputs

| Name | Description |
|------|-------------|
| `storage_account_id` | ID of the NFS storage account |
| `storage_account_name` | Name of the NFS storage account |
| `storage_account_primary_location` | Primary location of the storage account |
| `storage_account_primary_file_endpoint` | Primary file endpoint for NFS access |
| `private_endpoint_id` | ID of the Private Endpoint |
| `private_endpoint_ip_address` | Private IP address of the Private Endpoint |
| `private_dns_zone_id` | ID of the Private DNS Zone (auto-created or provided) |
| `private_dns_zone_name` | Name of the Private DNS Zone |
| `nfs_shares` | Map of created NFS file shares with details |

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.0 |
| azurerm | >= 3.0 |

## Important Notes

### NFS 4.1 vs NFS 3.0

- This module uses **NFS 4.1** via Azure Files Premium
- NFS 4.1 provides better security, performance, and POSIX compliance
- Different from NFS 3.0 available on Blob Storage with HNS enabled

### HTTPS Traffic

- `https_traffic_only_enabled` is always `false`
- NFS protocol does not use HTTPS
- This is a requirement for NFS support

### Storage Account Naming

- Must be globally unique across Azure
- 3-24 characters
- Only lowercase letters and numbers
- No hyphens or special characters

### Network Rules Best Practices

1. Start with restrictive rules (default deny)
2. Add only necessary subnets and IPs
3. Remove admin IPs after deployment if not needed
4. Use Azure Bastion or VPN for admin access instead of public IPs
5. Monitor access logs for unauthorized attempts

## Examples

See the [examples directory](../../examples/public-quix-infr-nfs-storage) for complete working examples.

## References

- [Azure Files NFS 4.1 Documentation](https://learn.microsoft.com/en-us/azure/storage/files/storage-files-how-to-create-nfs-shares)
- [Azure Private Endpoint](https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-overview)
- [FoggyKitchen Blog: Secure Azure File Storage (NFS) with Private Endpoint using Terraform](https://foggykitchen.com/2025/10/02/azure-file-storage-nfs-terraform/)

## License

This module is maintained by Quix.
