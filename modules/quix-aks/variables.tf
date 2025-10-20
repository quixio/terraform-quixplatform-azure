################################################################################
# Inputs for AKS module
################################################################################

variable "name" {
  description = "Name of the AKS cluster"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group name (existing or to be created)"
  type        = string
}

variable "create_resource_group" {
  description = "Whether to create the resource group"
  type        = bool
  default     = true
}


variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
}

variable "sku_tier" {
  description = "AKS tier (Free or Standard)"
  type        = string
  default     = "Standard"
}

variable "private_cluster_enabled" {
  description = "Enable AKS private cluster"
  type        = bool
  default     = false
}

variable "oidc_issuer_enabled" {
  description = "Enable OIDC issuer"
  type        = bool
  default     = true
}

variable "workload_identity_enabled" {
  description = "Enable workload identity"
  type        = bool
  default     = true
}

################################################################################
# Networking
################################################################################

variable "vnet_name" {
  description = "Name of the Virtual Network"
  type        = string
  default     = null
}

variable "vnet_address_space" {
  description = "Address space for the Virtual Network"
  type        = list(string)
  default     = null
}

variable "nodes_subnet_name" {
  description = "Name of the AKS nodes subnet"
  type        = string
  default     = null
}

variable "nodes_subnet_cidr" {
  description = "CIDR for the AKS nodes subnet"
  type        = string
  default     = null
}

# variable "vnet_id" {
#   description = "Existing VNet ID to reuse (skip VNet creation when set)"
#   type        = string
#   default     = null
# }

# variable "nodes_subnet_id" {
#   description = "Existing nodes subnet ID to reuse (skip subnet creation when set)"
#   type        = string
#   default     = null
# }

variable "create_vnet" {
  description = "Whether to create the VNet (set false when using external vnet_id)"
  type        = bool
  default     = true
}

variable "create_nodes_subnet" {
  description = "Whether to create the nodes subnet (set false when using external nodes_subnet_id)"
  type        = bool
  default     = true
}

variable "node_pools" {
  description = "Map of additional node pools (include a 'system' pool to override default)"
  type = map(object({
    name       = string
    type       = string # system | user
    node_count = number
    vm_size    = string
    max_pods   = optional(number)
    taints     = optional(list(string))
    labels     = optional(map(string))
    mode       = optional(string) # system | user (overrides type)
  }))
  default = {}
  validation {
    condition     = length([for k, p in var.node_pools : k if lower(coalesce(p.mode, p.type)) == "system"]) > 0
    error_message = "node_pools must include at least one pool with mode/type 'system'."
  }
  validation {
    condition     = alltrue([for p in values(var.node_pools) : contains(["system", "user"], lower(coalesce(p.mode, p.type)))])
    error_message = "node_pools[*].type/mode must be either 'system' or 'user'."
  }
}

variable "network_profile" {
  description = "AKS network profile"
  type = object({
    network_plugin_mode = string # "overlay" or "vnet"
    service_cidr        = string
    dns_service_ip      = string
    pod_cidr            = optional(string)
    network_policy      = optional(string, "calico")
    outbound_type       = optional(string, "userAssignedNATGateway")
  })
  validation {
    condition     = contains(["overlay", "vnet"], var.network_profile.network_plugin_mode)
    error_message = "network_profile.network_plugin_mode must be 'overlay' or 'vnet'."
  }
}



################################################################################
# NAT Gateway and Identity
################################################################################

variable "nat_identity_name" {
  description = "Name of the managed identity for NAT"
  type        = string
}

variable "public_ip_name" {
  description = "Name of the public IP for NAT Gateway"
  type        = string
}

variable "nat_gateway_name" {
  description = "Name of the NAT Gateway"
  type        = string
}

variable "create_nat" {
  description = "Whether to create NAT Gateway and its Public IP (set false to bring your own)"
  type        = bool
  default     = true
}

variable "nat_gateway_id" {
  description = "Existing NAT Gateway ID to associate when create_nat is false"
  type        = string
  default     = null
}

variable "availability_zone" {
  description = "Availability zone for public IP"
  type        = string
}

variable "attach_identity_ids" {
  description = "Additional user-assigned identity IDs to attach to the cluster"
  type        = list(string)
  default     = []
}

################################################################################
# Bastion and Jumpbox (optional)
################################################################################

variable "enable_bastion" {
  description = "Deploy Azure Bastion and its required subnet"
  type        = bool
  default     = false
}

variable "bastion_subnet_cidr" {
  description = "CIDR for AzureBastionSubnet"
  type        = string
  default     = "10.0.64.0/27"
}

variable "bastion_name" {
  description = "Name of the Azure Bastion resource"
  type        = string
  default     = "QuixBastion"
}

variable "bastion_public_ip_name" {
  description = "Name of the Public IP for Azure Bastion"
  type        = string
  default     = "QuixBastionIP"
}

variable "bastion_subnet_id" {
  description = "Existing AzureBastionSubnet ID to reuse (skip subnet creation when set)"
  type        = string
  default     = null
}

variable "bastion_public_ip_id" {
  description = "Existing Bastion Public IP ID to reuse (skip public IP creation when set)"
  type        = string
  default     = null
}

variable "create_bastion_subnet" {
  description = "Whether to create AzureBastionSubnet (set false when supplying bastion_subnet_id)"
  type        = bool
  default     = true
}

variable "jumpbox_name" {
  description = "Name of the jumpbox VM"
  type        = string
  default     = "quix-jumpbox"
}

variable "jumpbox_vm_size" {
  description = "VM size for the jumpbox"
  type        = string
  default     = "Standard_B2s"
}

variable "jumpbox_admin_username" {
  description = "Admin username for the jumpbox"
  type        = string
  default     = "azureuser"
}

variable "jumpbox_ssh_public_key" {
  description = "SSH public key for the jumpbox admin user"
  type        = string
  default     = ""
}

################################################################################
# Misc
################################################################################

variable "enable_credentials_fetch" {
  description = "Run az aks get-credentials after creating the cluster"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}


