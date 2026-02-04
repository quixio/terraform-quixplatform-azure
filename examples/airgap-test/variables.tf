################################################################################
# Variables for Airgap Test Cluster
################################################################################

variable "run_id" {
  description = "Unique identifier for this test run (e.g., Azure DevOps Build.BuildId). Used in all resource names for isolation."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.run_id))
    error_message = "run_id must contain only alphanumeric characters and hyphens."
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
  default     = "1.33.6"  # Latest stable in 1.33 line
}

variable "system_node_vm_size" {
  description = "VM size for system node pool (must have sufficient resources for AKS system pods)"
  type        = string
  default     = "Standard_D4s_v3" # 4 vCPU, 16 GB RAM
}

variable "workload_node_vm_size" {
  description = "VM size for workload node pool"
  type        = string
  default     = "Standard_D4s_v3" # 4 vCPU, 16 GB RAM
}

variable "workload_node_count" {
  description = "Number of workload nodes (minimum 2 for Quix platform)"
  type        = number
  default     = 2

  validation {
    condition     = var.workload_node_count >= 2 && var.workload_node_count <= 10
    error_message = "workload_node_count must be between 2 and 10."
  }
}
