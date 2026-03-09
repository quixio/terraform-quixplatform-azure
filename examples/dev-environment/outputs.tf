################################################################################
# Outputs
################################################################################

output "resource_group_name" {
  description = "Name of the resource group"
  value       = module.aks.resource_group_name
}

output "cluster_name" {
  description = "Name of the AKS cluster"
  value       = module.aks.cluster_name
}

output "cluster_fqdn" {
  description = "FQDN of the AKS API server"
  value       = module.aks.fqdn
}

output "kubelet_identity_object_id" {
  description = "Object ID of the kubelet managed identity"
  value       = module.aks.kubelet_identity_object_id
}

output "get_credentials_command" {
  description = "Azure CLI command to get kubeconfig"
  value       = "az aks get-credentials --name ${module.aks.cluster_name} --resource-group ${module.aks.resource_group_name} --overwrite-existing"
}
