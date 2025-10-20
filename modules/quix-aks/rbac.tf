################################################################################
# RBAC for AKS Managed Identity
################################################################################

data "azurerm_role_definition" "network_contributor" {
  name = "Network Contributor"
}

data "azurerm_role_definition" "contributor" {
  name = "Contributor"
}

resource "azurerm_role_assignment" "aks_vnet" {
  scope              = coalesce(try(azurerm_virtual_network.this[0].id, null), try(data.azurerm_subnet.existing[0].id, null))
  role_definition_id = data.azurerm_role_definition.network_contributor.id
  principal_id       = azurerm_user_assigned_identity.nat_identity.principal_id

  lifecycle {
    ignore_changes = [
      role_definition_id
    ]
  }
}

resource "azurerm_role_assignment" "aks_nodes_subnet" {
  scope              = coalesce(try(azurerm_subnet.nodes[0].id, null), try(data.azurerm_subnet.existing[0].id, null))
  role_definition_id = data.azurerm_role_definition.network_contributor.id
  principal_id       = azurerm_user_assigned_identity.nat_identity.principal_id

  lifecycle {
    ignore_changes = [
      role_definition_id
    ]
  }
}

resource "azurerm_role_assignment" "aks_rg" {
  scope              = local.rg_id
  role_definition_id = data.azurerm_role_definition.contributor.id
  principal_id       = azurerm_user_assigned_identity.nat_identity.principal_id

  lifecycle {
    ignore_changes = [
      role_definition_id
    ]
  }
}


