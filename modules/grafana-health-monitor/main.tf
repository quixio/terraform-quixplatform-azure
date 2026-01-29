################################################################################
# Locals
################################################################################

locals {
  vnet_rg_name = coalesce(var.vnet_resource_group_name, var.resource_group_name)

  # Sanitize storage account name (lowercase, alphanumeric, 3-24 chars)
  storage_account_name = lower(replace(substr("${var.name}funcsa", 0, 24), "/[^a-z0-9]/", ""))

  # Function App schedule (NCRONTAB format)
  schedule_expression = "0 */${var.check_interval_minutes} * * * *"

  # Alert name prefix (includes environment if provided)
  alert_prefix = var.environment != null ? "[${upper(var.environment)}] " : ""

  default_tags = {
    ManagedBy = "Terraform"
    Module    = "grafana-health-monitor"
  }

  tags = merge(local.default_tags, var.tags)
}

################################################################################
# Data Sources
################################################################################

data "azurerm_resource_group" "this" {
  name = var.resource_group_name
}

data "azurerm_virtual_network" "this" {
  count = var.private_grafana && var.create_function_subnet ? 1 : 0

  name                = var.vnet_name
  resource_group_name = local.vnet_rg_name
}

################################################################################
# Storage Account (required for Function App - only when private_grafana = true)
################################################################################

resource "azurerm_storage_account" "function" {
  count = var.private_grafana ? 1 : 0

  name                     = local.storage_account_name
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"

  tags = local.tags
}
