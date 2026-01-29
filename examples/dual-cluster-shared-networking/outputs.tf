################################################################################
# Outputs
################################################################################

# Shared Infrastructure
output "resource_group_name" {
  description = "Name of the shared resource group"
  value       = azurerm_resource_group.this.name
}

output "resource_group_id" {
  description = "ID of the shared resource group"
  value       = azurerm_resource_group.this.id
}

output "vnet_id" {
  description = "ID of the shared virtual network"
  value       = azurerm_virtual_network.shared.id
}

output "vnet_name" {
  description = "Name of the shared virtual network"
  value       = azurerm_virtual_network.shared.name
}

output "nat_gateway_public_ip" {
  description = "Public IP address of the shared NAT gateway (egress IP for both clusters)"
  value       = azurerm_public_ip.nat.ip_address
}

# Control Plane Cluster
output "ctrl_cluster_name" {
  description = "Name of the control plane AKS cluster"
  value       = module.aks_ctrl.cluster_name
}

output "ctrl_cluster_id" {
  description = "ID of the control plane AKS cluster"
  value       = module.aks_ctrl.aks_id
}

output "ctrl_private_fqdn" {
  description = "Private FQDN of the control plane API server"
  value       = module.aks_ctrl.private_fqdn
}

output "ctrl_oidc_issuer_url" {
  description = "OIDC issuer URL for the control plane cluster (for workload identity)"
  value       = module.aks_ctrl.oidc_issuer_url
}

output "ctrl_kubelet_identity_object_id" {
  description = "Kubelet identity object ID for the control plane cluster"
  value       = module.aks_ctrl.kubelet_identity_object_id
}

output "ctrl_kubelet_identity_client_id" {
  description = "Kubelet identity client ID for the control plane cluster"
  value       = module.aks_ctrl.kubelet_identity_client_id
}

output "ctrl_node_resource_group" {
  description = "Node resource group for the control plane cluster"
  value       = module.aks_ctrl.node_resource_group
}

# Data Plane Cluster
output "data_cluster_name" {
  description = "Name of the data plane AKS cluster"
  value       = module.aks_data.cluster_name
}

output "data_cluster_id" {
  description = "ID of the data plane AKS cluster"
  value       = module.aks_data.aks_id
}

output "data_private_fqdn" {
  description = "Private FQDN of the data plane API server"
  value       = module.aks_data.private_fqdn
}

output "data_oidc_issuer_url" {
  description = "OIDC issuer URL for the data plane cluster (for workload identity)"
  value       = module.aks_data.oidc_issuer_url
}

output "data_kubelet_identity_object_id" {
  description = "Kubelet identity object ID for the data plane cluster"
  value       = module.aks_data.kubelet_identity_object_id
}

output "data_kubelet_identity_client_id" {
  description = "Kubelet identity client ID for the data plane cluster"
  value       = module.aks_data.kubelet_identity_client_id
}

output "data_node_resource_group" {
  description = "Node resource group for the data plane cluster"
  value       = module.aks_data.node_resource_group
}

# Network CIDRs (useful for firewall rules and cross-cluster routing)
output "network_cidrs" {
  description = "Network CIDR allocations for reference"
  value = {
    vnet_address_space     = var.vnet_address_space
    ctrl_plane_subnet_cidr = var.ctrl_plane_subnet_cidr
    data_plane_subnet_cidr = var.data_plane_subnet_cidr
    ctrl_pod_cidr          = "10.144.0.0/16"
    ctrl_service_cidr      = "172.20.0.0/16"
    data_pod_cidr          = "10.145.0.0/16"
    data_service_cidr      = "172.21.0.0/16"
  }
}
