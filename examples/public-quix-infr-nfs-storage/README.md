# Example: AKS with NFS Storage via Private Link

This example demonstrates how to deploy an AKS cluster with an NFS v3 storage account accessible privately via Private Link.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ VNet: 10.240.0.0/16                                         │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ Subnet-Nodes: 10.240.0.0/22                          │   │
│  │                                                       │   │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐           │   │
│  │  │ AKS Node │  │ AKS Node │  │ AKS Node │           │   │
│  │  └──────────┘  └──────────┘  └──────────┘           │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ Subnet-PrivateEndpoints: 10.240.4.0/24               │   │
│  │                                                       │   │
│  │  ┌─────────────────────────────────────┐             │   │
│  │  │ Private Endpoint                    │             │   │
│  │  │  ├─ NFS Storage Account             │             │   │
│  │  │  └─ Private IP: 10.240.4.x          │             │   │
│  │  └─────────────────────────────────────┘             │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                              │
│  Private DNS Zone: privatelink.file.core.windows.net        │
│  (Auto-created by NFS Storage Module)                       │
└─────────────────────────────────────────────────────────────┘

                          │
                          │ Private Link
                          ▼
         ┌────────────────────────────────┐
         │ NFS Storage Account (Premium)  │
         │  - Public Access: Disabled     │
         │  - NFS v3 Enabled              │
         │  - HTTPS: Optional             │
         │                                │
         │  Shares:                       │
         │  ├─ data (100GB)               │
         │  └─ shared (200GB)             │
         └────────────────────────────────┘
```

## Features

- **AKS Cluster**: Kubernetes 1.32.4 with 3 node pools
- **NFS Storage**: Premium FileStorage with NFS v3
- **Private Link**: Private access from entire VNet
- **Auto Private DNS**: Automatic DNS zone creation and linking
- **Security**: No public access, all traffic is private

## Components

### 1. AKS Cluster
- 3 node pools: default, controller, deployments
- Dedicated VNet with subnet for nodes
- NAT Gateway for Internet egress

### 2. Private Endpoint Subnet
- Dedicated subnet for Private Endpoints (10.240.4.0/24)
- Created manually in the example
- Isolated from AKS nodes

### 3. NFS Storage Module (All-in-one)
The module automatically creates:
- **Premium Storage Account** with NFS v3
- **Private Endpoint** in the specified subnet
- **Private DNS Zone** `privatelink.file.core.windows.net`
- **VNet Link** for automatic DNS resolution
- **2 NFS shares**: `data` (100GB) and `shared` (200GB)
- Access only from VNet via Private Link

## Usage

### Deploy the infrastructure

```bash
cd examples/public-quix-infr-nfs-storage
terraform init
terraform plan
terraform apply
```

### Access the cluster

```bash
# Get credentials
az aks get-credentials --resource-group rg-quix-nfs --name quix-aks-nfs

# Verify connectivity
kubectl get nodes
```

### Mount NFS in Kubernetes

After deployment, you can mount the NFS shares in your pods:

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: nfs-pv-data
spec:
  capacity:
    storage: 100Gi
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  mountOptions:
    - vers=3
    - nconnect=8
  nfs:
    # Storage account resolves via Private DNS
    server: quixnfsstor01.file.core.windows.net
    path: /quixnfsstor01/data
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nfs-pvc-data
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 100Gi
  volumeName: nfs-pv-data
```

### Verify private DNS resolution

From a pod in the cluster:

```bash
# Create a test pod
kubectl run -it --rm debug --image=busybox --restart=Never -- sh

# Verify DNS resolution
nslookup quixnfsstor01.file.core.windows.net

# Should resolve to a private IP 10.240.4.x
```

## Important Variables

| Variable | Value | Description |
|----------|-------|-------------|
| `storage_account_name` | `quixnfsstor01` | **Must be globally unique** |
| `vnet_id` | `module.aks.vnet_id` | **Required for auto DNS zone creation** |
| `enable_secure_traffic` | `false` | NFS v3 typically doesn't use HTTPS |
| `nfs_shares` | `[data, shared]` | NFS shares to create |

## Key Simplifications

This example uses the **simplified approach** where:
1. You only provide `vnet_id` to the module
2. The module **automatically creates** the Private DNS Zone
3. The module **automatically links** the DNS zone to the VNet
4. No need to manually create or manage DNS zones

**Benefits:**
- Less boilerplate code
- Fewer resources to manage manually
- Automatic DNS configuration
- Consistent naming (`privatelink.file.core.windows.net`)

## Outputs

- `nfs_storage_account_name`: Storage account name
- `nfs_private_endpoint_ip`: Private IP address of the endpoint
- `nfs_shares`: Details of created shares
- `private_dns_zone_name`: Name of auto-created private DNS zone
- `private_dns_zone_id`: ID of auto-created private DNS zone

## Cleanup

```bash
terraform destroy
```

## Important Notes

1. **Storage Account Name**: Must be globally unique (3-24 chars, lowercase alphanumeric only)
2. **Premium Storage**: Required for NFS v3, higher cost than Standard
3. **Private DNS**: Automatically created and linked by the module
4. **Network Access**: Completely private, no public access
5. **NFS v3**: No protocol-level authentication, security via Private Link
6. **VNet ID**: Required when not providing custom `private_dns_zone_ids`

## Alternative: Custom DNS Zone

If you prefer to manage your own Private DNS Zone:

```hcl
module "nfs_storage" {
  source = "../../modules/nfs-storage"

  # ... other config ...

  # Provide your own DNS zone instead of vnet_id
  private_dns_zone_ids = [azurerm_private_dns_zone.custom.id]
  # vnet_id is not needed in this case
}
```

## References

- [Azure Files NFS Documentation](https://docs.microsoft.com/azure/storage/files/storage-files-how-to-mount-nfs-shares)
- [Private Endpoints for Azure Storage](https://docs.microsoft.com/azure/storage/common/storage-private-endpoints)
- [Azure Private DNS Zones](https://docs.microsoft.com/azure/dns/private-dns-overview)
