################################################################################
# Outputs
################################################################################

output "storage_account_id" {
  description = "ID of the NFS storage account"
  value       = azurerm_storage_account.this.id
}

output "storage_account_name" {
  description = "Name of the NFS storage account"
  value       = azurerm_storage_account.this.name
}

output "storage_account_primary_location" {
  description = "Primary location of the NFS storage account"
  value       = azurerm_storage_account.this.primary_location
}

output "storage_account_primary_file_endpoint" {
  description = "Primary file endpoint for NFS access"
  value       = azurerm_storage_account.this.primary_file_endpoint
}

output "private_endpoint_id" {
  description = "ID of the Private Endpoint"
  value       = azurerm_private_endpoint.nfs.id
}

output "private_endpoint_ip_address" {
  description = "Private IP address of the Private Endpoint"
  value       = try(azurerm_private_endpoint.nfs.private_service_connection[0].private_ip_address, null)
}

output "private_dns_zone_id" {
  description = "ID of the Private DNS Zone (auto-created or provided)"
  value       = length(var.private_dns_zone_ids) > 0 ? var.private_dns_zone_ids[0] : try(azurerm_private_dns_zone.storage_file[0].id, null)
}

output "private_dns_zone_name" {
  description = "Name of the Private DNS Zone"
  value       = length(var.private_dns_zone_ids) > 0 ? null : try(azurerm_private_dns_zone.storage_file[0].name, null)
}

output "nfs_shares" {
  description = "Map of NFS mount paths for each share"
  value = {
    for k, v in azurerm_storage_share.nfs_shares : k => {
      mount_path = "${azurerm_storage_account.this.name}.privatelink.file.core.windows.net:/${azurerm_storage_account.this.name}/${v.name}"
    }
  }
}
