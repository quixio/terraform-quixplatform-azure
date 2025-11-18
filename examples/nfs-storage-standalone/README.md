# Example: Standalone NFS Storage with Private Link

This example shows how to deploy **only** NFS storage with Private Endpoint, using existing resources (Resource Group, VNet, Subnets).

## Features

- **Without AKS**: Only creates NFS storage, does not include Kubernetes cluster
- **Existing resources**: Uses existing Resource Group, VNet, and Subnets
- **Manual configuration**: You manually input all necessary values
- **Private Link**: Private access from the specified VNet
- **Network Security Rules**: Deny-by-default policy with allowlist

## Prerequisites

You must have already created:

1. **Resource Group** in Azure
2. **VNet** with at least 2 subnets:
   - Subnet for Private Endpoints (e.g., `Subnet-PrivateEndpoints`)
   - Subnet from where you will access NFS (e.g., `Subnet-Nodes`, `Subnet-VMs`)

### Example of pre-existing infrastructure

```bash
# Create Resource Group
az group create --name rg-myapp --location westeurope

# Create VNet
az network vnet create \
  --name vnet-myapp \
  --resource-group rg-myapp \
  --address-prefix 10.240.0.0/16

# Create subnet for Private Endpoints
az network vnet subnet create \
  --name Subnet-PrivateEndpoints \
  --resource-group rg-myapp \
  --vnet-name vnet-myapp \
  --address-prefix 10.240.4.0/24

# Create subnet for your VMs/Nodes (optional)
az network vnet subnet create \
  --name Subnet-Nodes \
  --resource-group rg-myapp \
  --vnet-name vnet-myapp \
  --address-prefix 10.240.0.0/22
```

## Configuration

### 1. Copy the example file

```bash
cp terraform.tfvars.example terraform.tfvars
```

### 2. Edit terraform.tfvars with your values

```hcl
# Existing Resource Group
resource_group_name = "rg-myapp"

# Existing VNet
vnet_name = "vnet-myapp"

# Subnet for Private Endpoints (must exist)
private_endpoint_subnet_name = "Subnet-PrivateEndpoints"

# Allowed subnet to access NFS
allowed_subnet_name = "Subnet-Nodes"

# Storage Account name (must be globally unique)
storage_account_name = "mynfsstorage01"

# Your public IP (get it with: curl https://api.ipify.org)
allowed_ip_addresses = ["79.116.237.25"]

# NFS shares to create
nfs_shares = [
  {
    name     = "shared-data"
    quota_gb = 100
  }
]
```

### 3. Get your public IP

```bash
curl https://api.ipify.org
# Copy the result and put it in allowed_ip_addresses
```

## Usage

### Deploy

```bash
cd examples/nfs-storage-standalone
terraform init
terraform plan
terraform apply
```

### Outputs

After apply, you will see:

```bash
terraform output
```

Example output:

```
storage_account_name = "mynfsstorage01"
private_endpoint_ip = "10.240.4.4"
nfs_shares = {
  "shared-data" = {
    "mount_path" = "mynfsstorage01.privatelink.file.core.windows.net:/mynfsstorage01/shared-data"
  }
}
mount_instructions = {
  "shared-data" = "sudo mount -t nfs -o vers=4.1,sec=sys mynfsstorage01.privatelink.file.core.windows.net:/mynfsstorage01/shared-data /mnt/shared-data"
}
```

## Mounting NFS from a VM in the VNet

### From a Linux VM in the allowed subnet:

```bash
# Install NFS client
sudo apt-get update
sudo apt-get install -y nfs-common

# Create mount point
sudo mkdir -p /mnt/shared-data

# Mount the NFS share
sudo mount -t nfs -o vers=4.1,sec=sys \
  mynfsstorage01.privatelink.file.core.windows.net:/mynfsstorage01/shared-data \
  /mnt/shared-data

# Verify
df -h | grep shared-data
```

### Permanent mount (fstab)

```bash
echo "mynfsstorage01.privatelink.file.core.windows.net:/mynfsstorage01/shared-data /mnt/shared-data nfs vers=4.1,sec=sys 0 0" | sudo tee -a /etc/fstab
```

## Verify private DNS

From a VM inside the VNet:

```bash
# Verify DNS resolution
nslookup mynfsstorage01.file.core.windows.net
# Should resolve to a private IP (10.240.4.x)

# Verify CNAME redirect
nslookup mynfsstorage01.file.core.windows.net
# You will see: mynfsstorage01.file.core.windows.net -> mynfsstorage01.privatelink.file.core.windows.net
```

## Important variables

| Variable | Description | Example |
|----------|-------------|---------|
| `resource_group_name` | Existing Resource Group | `rg-myapp` |
| `vnet_name` | Existing VNet | `vnet-myapp` |
| `private_endpoint_subnet_name` | Subnet for Private Endpoint | `Subnet-PrivateEndpoints` |
| `allowed_subnet_name` | Allowed subnet for NFS | `Subnet-Nodes` |
| `storage_account_name` | Globally unique name | `mynfsstorage01` |
| `allowed_ip_addresses` | Your public IP | `["79.116.237.25"]` |
| `nfs_shares` | List of shares to create | See example |

## Security

### Network Security Rules (NSG)

The module configures:

- **Default action**: `Deny` (deny all by default)
- **Allowed subnets**: Only the subnet specified in `allowed_subnet_name`
- **Allowed IPs**: Only IPs in `allowed_ip_addresses` (for Terraform operations)
- **Bypass**: Azure Services can bypass the firewall

### Private Endpoint

- The storage account is **public** (accessible from the Internet)
- But with **firewall rules** that block everything except:
  - Allowed subnets (via Private Endpoint)
  - Allowed IPs (for admin/Terraform)
- All NFS traffic goes through Private Endpoint (private IP inside the VNet)

## Cleanup

```bash
terraform destroy
```

## Troubleshooting

### Error: Storage account name not available

The name must be **globally unique**. Change `storage_account_name` to another value.

### Error: Subnet not found

Verify that:
- The Resource Group exists
- The VNet exists
- The subnets exist within that VNet

You can list subnets with:

```bash
az network vnet subnet list \
  --resource-group rg-myapp \
  --vnet-name vnet-myapp \
  --output table
```

### Cannot mount NFS from my VM

Verify:

1. **Your VM is in the allowed subnet** (`allowed_subnet_name`)
2. **DNS resolves to private IP**:
   ```bash
   nslookup mynfsstorage01.file.core.windows.net
   # Should return a 10.240.4.x IP, not public
   ```
3. **NFS client installed**:
   ```bash
   sudo apt-get install -y nfs-common
   ```
4. **No NSG blocking NFS** (port 2049)

### Error 403 when creating shares

Make sure your public IP is in `allowed_ip_addresses`:

```bash
curl https://api.ipify.org
```

## Differences with the public-quix-infr-nfs-storage example

| Aspect | public-quix-infr-nfs-storage | nfs-storage-standalone |
|---------|------------------------------|------------------------|
| AKS | Includes complete AKS cluster | Does not include AKS |
| Infrastructure | Creates everything (RG, VNet, Subnets, NAT) | Uses existing resources |
| IP detection | Auto-detects with `data.http` | Manual via variable |
| Complexity | High (cluster + storage) | Low (storage only) |
| Usage | K8s + NFS integration demo | NFS storage for VMs/services |

## References

- [Azure Files NFS 4.1 Documentation](https://docs.microsoft.com/azure/storage/files/storage-files-how-to-mount-nfs-shares)
- [Private Endpoints for Azure Storage](https://docs.microsoft.com/azure/storage/common/storage-private-endpoints)
- [Module Documentation](../../modules/nfs-storage/README.md)
