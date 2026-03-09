################################################################################
# Variables for Dev Environment Cluster
################################################################################

variable "env_name" {
  description = "Environment name (e.g., dev1, dev2, dev3, dev4, dev5). Used in all resource names."
  type        = string

  validation {
    condition     = can(regex("^dev[1-5]$", var.env_name))
    error_message = "env_name must be one of: dev1, dev2, dev3, dev4, dev5."
  }
}

variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "westeurope"
}

variable "kubernetes_version" {
  description = "Kubernetes version for AKS cluster"
  type        = string
  default     = "1.33.6"
}

variable "system_node_vm_size" {
  description = "VM size for system node pool"
  type        = string
  default     = "Standard_D4s_v3"
}

variable "workload_node_vm_size" {
  description = "VM size for workload node pool (spot instances)"
  type        = string
  default     = "Standard_D4s_v3"
}

variable "workload_node_count" {
  description = "Number of workload nodes"
  type        = number
  default     = 2
}

variable "acr_id" {
  description = "Resource ID of the Azure Container Registry to grant AcrPull on"
  type        = string
}
