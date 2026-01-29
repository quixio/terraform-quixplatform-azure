# Dual-Cluster with Shared Networking

This example deploys two private AKS clusters (control plane and data plane) that share a single VNet and NAT gateway. This architecture is ideal for separating platform services from customer workloads while maintaining cost efficiency and simplified networking.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         Azure Resource Group                                 │
│                        (rg-quix-dual-cluster)                               │
│                                                                              │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                    Virtual Network (10.240.0.0/16)                     │  │
│  │                                                                        │  │
│  │  ┌─────────────────────────┐    ┌─────────────────────────┐          │  │
│  │  │   Subnet-CtrlPlane      │    │   Subnet-DataPlane      │          │  │
│  │  │   10.240.0.0/22         │    │   10.240.4.0/22         │          │  │
│  │  │   (1024 IPs)            │    │   (1024 IPs)            │          │  │
│  │  │                         │    │                         │          │  │
│  │  │  ┌───────────────────┐  │    │  ┌───────────────────┐  │          │  │
│  │  │  │  AKS Control Plane│  │    │  │  AKS Data Plane   │  │          │  │
│  │  │  │  (quix-aks-ctrl)  │  │    │  │  (quix-aks-data)  │  │          │  │
│  │  │  │                   │  │    │  │                   │  │          │  │
│  │  │  │  ┌─────────────┐  │  │    │  │  ┌─────────────┐  │  │          │  │
│  │  │  │  │System Pool  │  │  │    │  │  │System Pool  │  │  │          │  │
│  │  │  │  │2x D2ds_v5   │  │  │    │  │  │2x D2ds_v5   │  │  │          │  │
│  │  │  │  └─────────────┘  │  │    │  │  └─────────────┘  │  │          │  │
│  │  │  │  ┌─────────────┐  │  │    │  │  ┌─────────────┐  │  │          │  │
│  │  │  │  │Platform Pool│  │  │    │  │  │Deploy Pool  │  │  │          │  │
│  │  │  │  │3x E4ds_v5   │  │  │    │  │  │3x E4ds_v5   │  │  │          │  │
│  │  │  │  └─────────────┘  │  │    │  │  └─────────────┘  │  │          │  │
│  │  │  └───────────────────┘  │    │  └───────────────────┘  │          │  │
│  │  │                         │    │                         │          │  │
│  │  │  [NSG: nsg-ctrl-plane]  │    │  [NSG: nsg-data-plane]  │          │  │
│  │  └────────────┬────────────┘    └────────────┬────────────┘          │  │
│  │               │                              │                        │  │
│  │               └──────────────┬───────────────┘                        │  │
│  │                              │                                        │  │
│  └──────────────────────────────┼────────────────────────────────────────┘  │
│                                 │                                            │
│                    ┌────────────▼────────────┐                              │
│                    │      NAT Gateway        │                              │
│                    │    (ngw-quix-shared)    │                              │
│                    └────────────┬────────────┘                              │
│                                 │                                            │
│                    ┌────────────▼────────────┐                              │
│                    │       Public IP         │                              │
│                    │  (pip-quix-shared-nat)  │                              │
│                    └────────────┬────────────┘                              │
│                                 │                                            │
└─────────────────────────────────┼────────────────────────────────────────────┘
                                  │
                                  ▼
                              Internet
```

## Network Design

### IP Address Allocation

| Component | CIDR | Purpose |
|-----------|------|---------|
| VNet | 10.240.0.0/16 | Shared virtual network (65,536 IPs) |
| Control Plane Subnet | 10.240.0.0/22 | Node IPs for control plane cluster (1,024 IPs) |
| Data Plane Subnet | 10.240.4.0/22 | Node IPs for data plane cluster (1,024 IPs) |
| Reserved | 10.240.8.0/21+ | Available for future expansion |

### Overlay Networking

Both clusters use Azure CNI Overlay networking, which provides:
- **Pod isolation**: Pods get IPs from a virtual overlay network, not the node subnet
- **Scalability**: Node subnet size doesn't limit pod count
- **Separation**: Each cluster has unique pod/service CIDRs

| Cluster | Pod CIDR | Service CIDR | DNS IP |
|---------|----------|--------------|--------|
| Control Plane | 10.144.0.0/16 | 172.20.0.0/16 | 172.20.0.10 |
| Data Plane | 10.145.0.0/16 | 172.21.0.0/16 | 172.21.0.10 |

## Prerequisites

1. **Azure CLI** authenticated with appropriate permissions
2. **Terraform** >= 1.5.0
3. **Network connectivity** to private clusters via:
   - Azure VPN Gateway
   - ExpressRoute
   - Azure Bastion (not included, add separately if needed)

## Usage

### Basic Deployment

```bash
# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Apply the configuration
terraform apply
```

### Custom Configuration

Create a `terraform.tfvars` file to customize the deployment:

```hcl
# Location
location = "westeurope"

# Naming
resource_group_name = "rg-mycompany-quix"
ctrl_cluster_name   = "aks-ctrl-prod"
data_cluster_name   = "aks-data-prod"

# Kubernetes version
kubernetes_version = "1.33.5"

# Node sizing
system_node_vm_size   = "Standard_D2ds_v5"
system_node_count     = 2
workload_node_vm_size = "Standard_E4ds_v5"
workload_node_count   = 3

# Network customization
vnet_address_space     = ["10.240.0.0/16"]
ctrl_plane_subnet_cidr = "10.240.0.0/22"
data_plane_subnet_cidr = "10.240.4.0/22"
availability_zone      = "2"  # Zone pinning required for disk attachment

# Tags
tags = {
  environment = "production"
  project     = "Quix"
  cost-center = "engineering"
}
```

## Accessing the Clusters

Since both clusters are private, you need network connectivity to access them:

### Option 1: Azure VPN Gateway

Add a VPN Gateway to the shared VNet for point-to-site or site-to-site VPN access.

### Option 2: ExpressRoute

Connect your on-premises network to Azure via ExpressRoute.

### Option 3: Jump Box with Bastion

Deploy an Azure Bastion and jump box VM in the VNet (requires additional Terraform configuration).

### Getting Credentials

Once connected to the VNet:

```bash
# Control Plane cluster
az aks get-credentials \
  --resource-group rg-quix-dual-cluster \
  --name quix-aks-ctrl

# Data Plane cluster
az aks get-credentials \
  --resource-group rg-quix-dual-cluster \
  --name quix-aks-data
```

## Node Labels

The clusters use Quix-standard node labels for workload scheduling:

| Cluster | Node Pool | Label |
|---------|-----------|-------|
| Control Plane | platform | `quix.io/node-purpose=platform-services` |
| Data Plane | deployments | `quix.io/node-purpose=customer-deployments` |

## Security Considerations

1. **Network Security Groups**: Each subnet has an NSG for traffic control
2. **Private API Servers**: Cluster APIs are not exposed to the internet
3. **Shared Egress**: Both clusters share a single NAT gateway public IP
4. **Workload Identity**: OIDC enabled for secure pod-to-Azure-service authentication

## Outputs

After deployment, the following outputs are available:

| Output | Description |
|--------|-------------|
| `nat_gateway_public_ip` | Shared egress IP (whitelist this for external services) |
| `ctrl_private_fqdn` | Private FQDN for control plane API server |
| `data_private_fqdn` | Private FQDN for data plane API server |
| `ctrl_oidc_issuer_url` | OIDC URL for control plane workload identity |
| `data_oidc_issuer_url` | OIDC URL for data plane workload identity |
| `network_cidrs` | All network CIDR allocations for reference |

## Cost Optimization

This architecture optimizes costs by:
- Sharing a single NAT Gateway between clusters
- Using a single public IP for egress
- Sharing the VNet infrastructure
- Using smaller VMs for system pools (D2ds_v5)

## Scaling Considerations

- **Subnet sizing**: /22 subnets support ~1000 nodes each. For larger deployments, use /21 or larger
- **Node pools**: Add additional node pools via the `node_pools` variable
- **Multi-region**: For geo-redundancy, deploy this pattern in multiple regions with VNet peering
