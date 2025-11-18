################################################################################
# AKS Outputs
################################################################################

output "aks_cluster_name" {
  description = "Name of the AKS cluster"
  value       = module.aks.cluster_name
}

output "aks_vnet_name" {
  description = "Name of the VNet"
  value       = module.aks.vnet_name
}

output "aks_vnet_id" {
  description = "ID of the VNet"
  value       = module.aks.vnet_id
}

################################################################################
# NFS Storage Outputs
################################################################################

output "nfs_storage_account_name" {
  description = "Name of the NFS storage account"
  value       = module.nfs_storage.storage_account_name
}

output "nfs_storage_account_id" {
  description = "ID of the NFS storage account"
  value       = module.nfs_storage.storage_account_id
}

output "nfs_private_endpoint_id" {
  description = "ID of the NFS Private Endpoint"
  value       = module.nfs_storage.private_endpoint_id
}

output "nfs_private_endpoint_ip" {
  description = "Private IP address of the NFS Private Endpoint"
  value       = module.nfs_storage.private_endpoint_ip_address
}

output "nfs_shares" {
  description = "Created NFS shares"
  value       = module.nfs_storage.nfs_shares
}

################################################################################
# Private DNS Zone Outputs (auto-created by module)
################################################################################

output "private_dns_zone_name" {
  description = "Name of the Private DNS Zone for file storage (auto-created)"
  value       = module.nfs_storage.private_dns_zone_name
}

output "private_dns_zone_id" {
  description = "ID of the Private DNS Zone for file storage (auto-created)"
  value       = module.nfs_storage.private_dns_zone_id
}
