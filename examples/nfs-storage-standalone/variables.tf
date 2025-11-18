variable "resource_group_name" {
  description = "Nombre del Resource Group existente"
  type        = string
  default     = "rg-myapp"
}

variable "vnet_name" {
  description = "Nombre de la VNet existente"
  type        = string
  default     = "vnet-myapp"
}

variable "private_endpoint_subnet_name" {
  description = "Nombre de la subnet para Private Endpoints"
  type        = string
  default     = "Subnet-PrivateEndpoints"
}

variable "allowed_subnet_name" {
  description = "Nombre de la subnet permitida para acceder al NFS (e.g., subnet de AKS nodes, VMs, etc.). Dejar vacío para no permitir ninguna subnet."
  type        = string
  default     = "Subnet-Nodes"
}

variable "storage_account_name" {
  description = "Nombre de la Storage Account (debe ser único globalmente, 3-24 caracteres, solo letras minúsculas y números)"
  type        = string
  default     = "mynfsstorage01"
}

variable "allowed_ip_addresses" {
  description = "Lista de IPs públicas permitidas para operaciones de Terraform (sin notación CIDR, solo la IP)"
  type        = list(string)
  default     = ["1.2.3.4"] # Cambia esto por tu IP pública
}

variable "nfs_shares" {
  description = "Lista de shares NFS a crear"
  type = list(object({
    name        = string
    quota_gb    = number
    access_tier = optional(string)
    metadata    = optional(map(string))
  }))
  default = [
    {
      name     = "shared-data"
      quota_gb = 100
    }
  ]
}

variable "tags" {
  description = "Tags a aplicar a los recursos"
  type        = map(string)
  default = {
    environment = "demo"
    project     = "NFS-Storage"
  }
}
