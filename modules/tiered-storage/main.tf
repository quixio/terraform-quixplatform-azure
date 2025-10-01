################################################################################
# Tiered Storage: Storage Account + Workload Identity Federation + Role Assignments
################################################################################

resource "azurerm_storage_account" "this" {
  name                     = var.storage_account_name
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  allow_nested_items_to_be_public = false
  min_tls_version          = "TLS1_2"
  tags                     = var.tags
}

################################################################################
# Role assignment for AKS kubelet identity to access storage (e.g., Storage Blob Data Contributor)
################################################################################

data "azurerm_role_definition" "storage_blob_data_contributor" {
  name = "Storage Blob Data Contributor"
}

resource "azurerm_role_assignment" "kubelet_storage" {
  scope              = azurerm_storage_account.this.id
  role_definition_id = data.azurerm_role_definition.storage_blob_data_contributor.id
  principal_id       = var.kubelet_identity_object_id

  lifecycle {
    ignore_changes = [
      role_definition_id
    ]
  }
}

################################################################################
# Federated identity credential for workload identity
################################################################################

# This assumes you already created an AAD app (workload_client_id/object_id). We link the service account subject
# system:serviceaccount:<namespace>:<service_account_name>

resource "azurerm_federated_identity_credential" "workload" {
  for_each            = { for b in var.federated_bindings : "${b.namespace}:${b.service_account_name}" => b }
  name                = coalesce(try(each.value.name, null), "${var.cluster_name}-${each.value.namespace}-${each.value.service_account_name}")
  resource_group_name = var.resource_group_name
  audience            = ["api://AzureADTokenExchange"]
  issuer              = var.aks_oidc_issuer_url
  subject             = "system:serviceaccount:${each.value.namespace}:${each.value.service_account_name}"
  parent_id           = var.cluster_identity_resource_id
}


