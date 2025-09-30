################################################################################
# Full AKS Stack Module: RG, Network, NAT, Identity, RBAC, Bastion, AKS
################################################################################

locals {
  is_overlay = var.network_profile.network_plugin_mode == "overlay"
  system_pool_keys = [for k, p in var.node_pools : k if lower(coalesce(p.mode, p.type)) == "system"]
  system_pool      = length(local.system_pool_keys) > 0 ? var.node_pools[local.system_pool_keys[0]] : null
  # Sanitize system pool name: lowercase, alphanum only, start with letter, max 12
  system_pool_name_base      = replace(lower(local.system_pool.name), "[^a-z0-9]", "")
  system_pool_name_nonempty  = local.system_pool_name_base != "" ? local.system_pool_name_base : "system"
  system_pool_name_prefixed  = can(regex("^[a-z]", local.system_pool_name_nonempty)) ? local.system_pool_name_nonempty : "p${local.system_pool_name_nonempty}"
  system_pool_name           = substr(local.system_pool_name_prefixed, 0, 12)
  rg_id            = var.create_resource_group ? azurerm_resource_group.this[0].id : data.azurerm_resource_group.existing[0].id
  rg_name_effective = var.resource_group_name
  rg_location      = var.create_resource_group ? azurerm_resource_group.this[0].location : data.azurerm_resource_group.existing[0].location
}

################################################################################
# Resource Group
################################################################################

resource "azurerm_resource_group" "this" {
  count    = var.create_resource_group ? 1 : 0
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

data "azurerm_resource_group" "existing" {
  count = var.create_resource_group ? 0 : 1
  name  = var.resource_group_name
}

