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
- **NFS Storage**: Premium FileStorage with NFS 4.1
- **Private Link**: Private access from entire VNet
- **Auto Private DNS**: Automatic DNS zone creation and linking
- **Network Security Rules**: Default deny policy with subnet and IP allowlists
- **Security**: Public storage with firewall rules, all NFS traffic is private via Private Endpoint

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
- **Premium Storage Account** with NFS 4.1 support
- **Network Security Rules** (default deny + allowlist for AKS nodes subnet and admin IP)
- **Private Endpoint** in the specified subnet
- **Private DNS Zone** `privatelink.file.core.windows.net`
- **VNet Link** for automatic DNS resolution
- **NFS File Share**: `sharedpvc` (200GB)
- Access from allowed subnets via Private Endpoint, plus admin IP for Terraform operations

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

After deployment, create a StorageClass that references the NFS share:

#### 1. Create StorageClass

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: azurefilenfs-csi-nfs
provisioner: nfs.csi.k8s.io
parameters:
  server: "quixnfsstor01.privatelink.file.core.windows.net"  # Storage account with Private Link DNS
  share: "/quixnfsstor01/sharedpvc"                          # NFS file share name
mountOptions:
  - vers=4.1
  - minorversion=1
  - sec=sys
  - hard
  - timeo=600
  - retrans=2
reclaimPolicy: Retain
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
```

#### 2. Create PersistentVolumeClaim

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nfs-pvc-data
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: azurefilenfs-csi-nfs
  resources:
    requests:
      storage: 100Gi
```

#### 3. Use in Pod

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nfs-test-pod
spec:
  containers:
  - name: app
    image: nginx
    volumeMounts:
    - name: nfs-storage
      mountPath: /mnt/nfs
  volumes:
  - name: nfs-storage
    persistentVolumeClaim:
      claimName: nfs-pvc-data
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
| `allowed_subnet_ids` | `[module.aks.nodes_subnet_id]` | Subnets allowed to access storage (AKS nodes) |
| `allowed_ip_addresses` | Auto-detected via `data.http` | Your public IP for Terraform operations (create/destroy shares) |
| `nfs_shares` | `[sharedpvc]` | NFS 4.1 shares to create |

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
2. **Premium Storage**: Required for NFS 4.1, higher cost than Standard
3. **Private DNS**: Automatically created and linked by the module
4. **Network Security**: Public storage with default deny policy + explicit allowlist for subnets and IPs
5. **NFS 4.1**: POSIX-compliant file system with better security than NFS 3.0
6. **HTTPS Traffic**: Always disabled for NFS (NFS protocol doesn't use HTTPS)
7. **VNet ID**: Required when not providing custom `private_dns_zone_ids`
8. **Admin IP**: Auto-detected from https://api.ipify.org for Terraform operations (create/destroy file shares)

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
