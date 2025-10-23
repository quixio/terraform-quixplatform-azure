################################################################################
# AKS Cluster and Node Pools
################################################################################

resource "azurerm_kubernetes_cluster" "this" {
  name                       = var.name
  location                   = local.rg_location
  resource_group_name        = local.rg_name_effective
  dns_prefix                 = var.private_cluster_enabled ? null : "${var.name}-dns"
  dns_prefix_private_cluster = var.private_cluster_enabled ? coalesce(var.private_dns_prefix, "${var.name}-dns") : null
  kubernetes_version         = var.kubernetes_version
  sku_tier                   = var.sku_tier
  private_cluster_enabled    = var.private_cluster_enabled
  private_dns_zone_id        = var.private_cluster_enabled ? var.private_dns_zone_id : null

  oidc_issuer_enabled       = var.oidc_issuer_enabled
  workload_identity_enabled = var.workload_identity_enabled

  default_node_pool {
    name           = local.system_pool_name
    node_count     = local.system_pool.node_count
    vm_size        = local.system_pool.vm_size
    vnet_subnet_id = coalesce(try(azurerm_subnet.nodes[0].id, null), try(data.azurerm_subnet.existing[0].id, null))

    upgrade_settings {
      max_surge                     = "10%"
      drain_timeout_in_minutes      = 0
      node_soak_duration_in_minutes = 0
    }
  }

  identity {
    type         = "UserAssigned"
    identity_ids = concat([azurerm_user_assigned_identity.nat_identity.id], var.attach_identity_ids)
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = local.is_overlay ? "overlay" : null
    network_policy      = try(var.network_profile.network_policy, "calico")
    pod_cidr            = local.is_overlay ? try(var.network_profile.pod_cidr, null) : null
    service_cidr        = var.network_profile.service_cidr
    dns_service_ip      = var.network_profile.dns_service_ip
    outbound_type       = try(var.network_profile.outbound_type, "userAssignedNATGateway")
  }

  tags = var.tags

  depends_on = [
    azurerm_subnet_nat_gateway_association.nodes,
    azurerm_role_assignment.aks_vnet,
    azurerm_role_assignment.aks_nodes_subnet,
    azurerm_role_assignment.aks_rg
  ]
}

resource "azurerm_kubernetes_cluster_node_pool" "additional" {
  for_each = { for k, p in var.node_pools : k => p if k != (length(local.system_pool_keys) > 0 ? local.system_pool_keys[0] : "__none__") }
  # Sanitize name: lowercase, alphanum only, start with letter, max 12
  name = substr(
    (
      can(regex("^[a-z]", (replace(lower(each.value.name), "[^a-z0-9]", "") != "" ? replace(lower(each.value.name), "[^a-z0-9]", "") : "pool")))
      ? (replace(lower(each.value.name), "[^a-z0-9]", "") != "" ? replace(lower(each.value.name), "[^a-z0-9]", "") : "pool")
      : "p${(replace(lower(each.value.name), "[^a-z0-9]", "") != "" ? replace(lower(each.value.name), "[^a-z0-9]", "") : "pool")}"
    ),
    0,
    12
  )
  kubernetes_cluster_id = azurerm_kubernetes_cluster.this.id
  vm_size               = each.value.vm_size
  node_count            = each.value.node_count
  vnet_subnet_id        = coalesce(try(azurerm_subnet.nodes[0].id, null), try(data.azurerm_subnet.existing[0].id, null))
  mode                  = lower(coalesce(each.value.mode, each.value.type)) == "system" ? "System" : "User"
  node_taints           = coalesce(each.value.taints, null)
  orchestrator_version  = var.kubernetes_version

  upgrade_settings {
    max_surge                     = "10%"
    drain_timeout_in_minutes      = 0
    node_soak_duration_in_minutes = 0
  }
  tags = var.tags
}

################################################################################
# Optional: fetch credentials locally
################################################################################

resource "null_resource" "aks_credentials" {
  count = var.enable_credentials_fetch ? 1 : 0
  provisioner "local-exec" {
    command = "az aks get-credentials -n ${var.name} -g ${local.rg_name_effective} --overwrite-existing"
  }
  depends_on = [azurerm_kubernetes_cluster.this]
}


