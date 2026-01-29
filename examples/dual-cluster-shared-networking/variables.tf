################################################################################
# Variables
################################################################################

variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "westeurope"
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "rg-quix-dual-cluster"
}

variable "vnet_name" {
  description = "Name of the shared virtual network"
  type        = string
  default     = "vnet-quix-shared"
}

variable "vnet_address_space" {
  description = "Address space for the shared VNet"
  type        = list(string)
  default     = ["10.240.0.0/16"]
}

variable "ctrl_plane_subnet_cidr" {
  description = "CIDR for the control plane subnet. Default /22 provides 1024 IPs, adequate for control plane workloads."
  type        = string
  default     = "10.240.0.0/22"
}

variable "data_plane_subnet_cidr" {
  description = "CIDR for the data plane subnet. Default /22 provides 1024 IPs. Size according to expected deployment scale."
  type        = string
  default     = "10.240.4.0/22"
}

variable "kubernetes_version" {
  description = "Kubernetes version for both clusters"
  type        = string
  default     = "1.33.5"
}

variable "ctrl_cluster_name" {
  description = "Name of the control plane AKS cluster"
  type        = string
  default     = "quix-aks-ctrl"
}

variable "data_cluster_name" {
  description = "Name of the data plane AKS cluster"
  type        = string
  default     = "quix-aks-data"
}

variable "system_node_vm_size" {
  description = "VM size for system node pools"
  type        = string
  default     = "Standard_D2ds_v5"
}

variable "system_node_count" {
  description = "Number of nodes in system pools"
  type        = number
  default     = 2
}

variable "workload_node_vm_size" {
  description = "VM size for platform and deployment node pools"
  type        = string
  default     = "Standard_E4ds_v5"
}

variable "workload_node_count" {
  description = "Number of nodes in workload pools (platform/deployments)"
  type        = number
  default     = 3
}

variable "availability_zone" {
  description = "Availability zone for NAT gateway public IP. Zone pinning is required to avoid disk attachment issues with AKS."
  type        = string
  default     = "2"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    environment = "demo"
    project     = "Quix"
  }
}
