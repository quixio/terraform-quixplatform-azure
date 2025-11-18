output "storage_account_name" {
  description = "Nombre de la Storage Account creada"
  value       = module.nfs_storage.storage_account_name
}

output "storage_account_id" {
  description = "ID de la Storage Account"
  value       = module.nfs_storage.storage_account_id
}

output "private_endpoint_ip" {
  description = "IP privada del Private Endpoint"
  value       = module.nfs_storage.private_endpoint_ip_address
}

output "private_dns_zone_name" {
  description = "Nombre de la Private DNS Zone (auto-creada)"
  value       = module.nfs_storage.private_dns_zone_name
}

output "nfs_shares" {
  description = "Rutas de montaje NFS para cada share"
  value       = module.nfs_storage.nfs_shares
}

output "mount_instructions" {
  description = "Instrucciones para montar los shares NFS"
  value = {
    for k, v in module.nfs_storage.nfs_shares : k => "sudo mount -t nfs -o vers=4.1,sec=sys ${v.mount_path} /mnt/${k}"
  }
}
