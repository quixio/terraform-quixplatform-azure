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
  description = "Storage account name"
  type        = string
}

variable "cluster_name" {
  description = "AKS cluster name (used for federation subject/context)"
  type        = string
}

variable "aks_oidc_issuer_url" {
  description = "AKS OIDC issuer URL (from quix-aks module output)"
  type        = string
}

variable "kubelet_identity_object_id" {
  description = "Kubelet identity object ID (from quix-aks module output)"
  type        = string
}


variable "cluster_identity_resource_id" {
  description = "Resource ID of the Managed Identity to attach federated credentials (module.aks.cluster_identity_resource_id)"
  type        = string
}


variable "federated_bindings" {
  description = "List of federated identity bindings (namespace + service account)"
  type = list(object({
    namespace            = string
    service_account_name = string
    name                 = optional(string)
  }))
  default = []
}

variable "tags" {
  description = "Tags"
  type        = map(string)
  default     = {}
}


