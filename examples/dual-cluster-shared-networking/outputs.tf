################################################################################
# Outputs
################################################################################

# Shared Infrastructure
output "resource_group_name" {
  description = "Name of the shared resource group"
  value       = azurerm_resource_group.this.name
}

output "vnet_id" {
  description = "ID of the shared virtual network"
  value       = azurerm_virtual_network.shared.id
}

output "nat_gateway_public_ip" {
  description = "Public IP address of the shared NAT gateway"
  value       = azurerm_public_ip.nat.ip_address
}

# Control Plane Cluster
output "ctrl_cluster_name" {
  description = "Name of the control plane AKS cluster"
  value       = module.aks_ctrl.cluster_name
}

output "ctrl_private_fqdn" {
  description = "Private FQDN of the control plane API server"
  value       = module.aks_ctrl.private_fqdn
}

output "ctrl_oidc_issuer_url" {
  description = "OIDC issuer URL for the control plane cluster"
  value       = module.aks_ctrl.oidc_issuer_url
}

# Data Plane Cluster
output "data_cluster_name" {
  description = "Name of the data plane AKS cluster"
  value       = module.aks_data.cluster_name
}

output "data_private_fqdn" {
  description = "Private FQDN of the data plane API server"
  value       = module.aks_data.private_fqdn
}

output "data_oidc_issuer_url" {
  description = "OIDC issuer URL for the data plane cluster"
  value       = module.aks_data.oidc_issuer_url
}
