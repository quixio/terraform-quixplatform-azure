################################################################################
# Outputs
################################################################################

output "resource_group_name" {
  description = "Name of the resource group"
  value       = local.rg_name_effective
}

output "resource_group_id" {
  description = "ID of the resource group"
  value       = local.rg_id
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = local.rg_location
}

output "vnet_id" {
  description = "ID of the virtual network"
  value       = azurerm_virtual_network.this.id
}

output "nodes_subnet_id" {
  description = "ID of the nodes subnet"
  value       = azurerm_subnet.nodes.id
}

output "nat_gateway_public_ip" {
  description = "Public IP address of the NAT Gateway"
  value       = azurerm_public_ip.nat_gateway.ip_address
}

output "aks_id" {
  description = "ID of the AKS cluster"
  value       = azurerm_kubernetes_cluster.this.id
}

output "cluster_name" {
  description = "AKS cluster name"
  value       = azurerm_kubernetes_cluster.this.name
}

output "fqdn" {
  description = "Public FQDN of the API server (null if private)"
  value       = try(azurerm_kubernetes_cluster.this.fqdn, null)
}

output "private_fqdn" {
  description = "Private FQDN of the API server (null if public)"
  value       = try(azurerm_kubernetes_cluster.this.private_fqdn, null)
}

output "kubelet_identity_object_id" {
  description = "Kubelet identity object ID"
  value       = azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id
}

output "kubelet_identity_client_id" {
  description = "Kubelet identity client ID"
  value       = azurerm_kubernetes_cluster.this.kubelet_identity[0].client_id
}

output "kubelet_identity_resource_id" {
  description = "Kubelet identity resource ID"
  value       = azurerm_kubernetes_cluster.this.kubelet_identity[0].user_assigned_identity_id
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL (null if disabled)"
  value       = try(azurerm_kubernetes_cluster.this.oidc_issuer_url, null)
}

output "node_resource_group" {
  description = "Node resource group name"
  value       = azurerm_kubernetes_cluster.this.node_resource_group
}

output "cluster_identity_principal_id" {
  description = "Principal ID of the cluster's user-assigned identity"
  value       = azurerm_user_assigned_identity.nat_identity.principal_id
}

output "cluster_identity_client_id" {
  description = "Client ID of the cluster's user-assigned identity"
  value       = azurerm_user_assigned_identity.nat_identity.client_id
}

output "cluster_identity_resource_id" {
  description = "Resource ID of the cluster's user-assigned identity"
  value       = azurerm_user_assigned_identity.nat_identity.id
}

output "nodes_subnet_name" {
  description = "Name of the nodes subnet"
  value       = azurerm_subnet.nodes.name
}


