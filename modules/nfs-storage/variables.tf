################################################################################
# Inputs
################################################################################

variable "resource_group_name" {
  description = "Resource group name (same RG as AKS)"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "storage_account_name" {
  description = "Storage account name (must be globally unique, 3-24 chars, lowercase alphanumeric)"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "Storage account name must be 3-24 characters long and contain only lowercase letters and numbers."
  }
}

variable "private_endpoint_subnet_id" {
  description = "Subnet ID where the Private Endpoint will be created (typically a dedicated subnet for private endpoints)"
  type        = string
}

variable "vnet_id" {
  description = "VNet ID to link the Private DNS Zone to (required if private_dns_zone_ids is not provided)"
  type        = string
  default     = null
}

variable "private_dns_zone_ids" {
  description = "List of Private DNS Zone IDs for privatelink.file.core.windows.net. If not provided, a new Private DNS Zone will be created automatically."
  type        = list(string)
  default     = []
}

variable "allowed_subnet_ids" {
  description = "List of subnet IDs that are allowed to access the storage account (e.g., AKS nodes subnet for NFS access)"
  type        = list(string)
  default     = []
}

variable "allowed_ip_addresses" {
  description = "List of IP addresses or CIDR ranges that are allowed to access the storage account (e.g., admin IP for Terraform operations to create file shares)"
  type        = list(string)
  default     = []
}

variable "network_bypass" {
  description = "List of services that can bypass network rules (AzureServices, Logging, Metrics, None)"
  type        = list(string)
  default     = ["AzureServices"]
}

variable "nfs_shares" {
  description = "List of NFS file shares to create"
  type = list(object({
    name        = string
    quota_gb    = number
    access_tier = optional(string)
    metadata    = optional(map(string))
  }))
  default = []
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
