################################################################################
# NFS Storage: Storage Account + Private Link
################################################################################

################################################################################
# Private DNS Zone (created if not provided)
################################################################################

resource "azurerm_private_dns_zone" "storage_file" {
  count               = length(var.private_dns_zone_ids) == 0 ? 1 : 0
  name                = "privatelink.file.core.windows.net"
  resource_group_name = var.resource_group_name

  tags = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "storage_file" {
  count                 = length(var.private_dns_zone_ids) == 0 ? 1 : 0
  name                  = "${var.storage_account_name}-vnet-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.storage_file[0].name
  virtual_network_id    = var.vnet_id

  tags = var.tags
}

################################################################################
# Storage Account
################################################################################

resource "azurerm_storage_account" "this" {
  name                     = var.storage_account_name
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Premium"
  account_replication_type = "LRS"
  account_kind             = "FileStorage"
  access_tier              = "Hot"
  # Azure Files Premium configuration for NFS 4.1
  # NFS 4.1 is enabled at the share level with enabled_protocol = "NFS"
  # NFS does not use HTTPS, so this must always be false
  https_traffic_only_enabled      = false
  allow_nested_items_to_be_public = false

  tags = var.tags
}

################################################################################
# Network Security Rules (separate resource)
################################################################################

resource "azurerm_storage_account_network_rules" "this" {
  storage_account_id         = azurerm_storage_account.this.id
  default_action             = "Deny"
  virtual_network_subnet_ids = var.allowed_subnet_ids
  ip_rules                   = var.allowed_ip_addresses
  bypass                     = var.network_bypass

  depends_on = [
    azurerm_storage_account.this
  ]
}

################################################################################
# Private Endpoint for NFS access from VNet
################################################################################

resource "azurerm_private_endpoint" "nfs" {
  name                = "${var.storage_account_name}-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id

  private_service_connection {
    name                           = "${var.storage_account_name}-psc"
    private_connection_resource_id = azurerm_storage_account.this.id
    is_manual_connection           = false
    subresource_names              = ["file"]
  }

  private_dns_zone_group {
    name = "default"
    # Use provided DNS zone IDs or the auto-created one
    private_dns_zone_ids = length(var.private_dns_zone_ids) > 0 ? var.private_dns_zone_ids : [azurerm_private_dns_zone.storage_file[0].id]
  }

  tags = var.tags

  depends_on = [
    azurerm_private_dns_zone_virtual_network_link.storage_file,
    azurerm_storage_account_network_rules.this
  ]
}

################################################################################
# Optional: NFS File Shares
################################################################################

resource "azurerm_storage_share" "nfs_shares" {
  for_each             = { for share in var.nfs_shares : share.name => share }
  name                 = each.value.name
  storage_account_name = azurerm_storage_account.this.name
  enabled_protocol     = "NFS"
  quota                = each.value.quota_gb

  metadata = try(each.value.metadata, {})

  # Ensure storage account and private endpoint are created first
  depends_on = [
    azurerm_storage_account.this,
    azurerm_private_endpoint.nfs
  ]
}
