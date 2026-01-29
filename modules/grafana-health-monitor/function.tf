################################################################################
# App Service Plan (Consumption) - Only for private Grafana
################################################################################

resource "azurerm_service_plan" "function" {
  count = var.private_grafana ? 1 : 0

  name                = "${var.name}-plan"
  resource_group_name = var.resource_group_name
  location            = var.location
  os_type             = "Linux"
  sku_name            = "Y1" # Consumption plan

  tags = local.tags
}

################################################################################
# Linux Function App - Only for private Grafana
################################################################################

resource "azurerm_linux_function_app" "health_monitor" {
  count = var.private_grafana ? 1 : 0

  name                = "${var.name}-func"
  resource_group_name = var.resource_group_name
  location            = var.location

  storage_account_name       = azurerm_storage_account.function[0].name
  storage_account_access_key = azurerm_storage_account.function[0].primary_access_key
  service_plan_id            = azurerm_service_plan.function[0].id

  # VNet Integration
  virtual_network_subnet_id = local.function_subnet_id

  identity {
    type = "SystemAssigned"
  }

  site_config {
    application_stack {
      python_version = "3.11"
    }

    application_insights_connection_string = azurerm_application_insights.this.connection_string
    application_insights_key               = azurerm_application_insights.this.instrumentation_key
  }

  app_settings = {
    "GRAFANA_HEALTH_URL"           = var.grafana_health_url
    "HEALTH_CHECK_TIMEOUT_SECONDS" = tostring(var.health_check_timeout_seconds)
    "SCHEDULE_EXPRESSION"          = local.schedule_expression

    # Required for VNet Integration with Consumption plan
    "WEBSITE_CONTENTOVERVNET" = "1"
    "WEBSITE_VNET_ROUTE_ALL"  = "1"

    # Python specific
    "AzureWebJobsFeatureFlags"       = "EnableWorkerIndexing"
    "BUILD_FLAGS"                    = "UseExpressBuild"
    "ENABLE_ORYX_BUILD"              = "true"
    "SCM_DO_BUILD_DURING_DEPLOYMENT" = "true"
    "XDG_CACHE_HOME"                 = "/tmp/.cache"
  }

  tags = local.tags

  lifecycle {
    ignore_changes = [
      # Ignore changes to app_settings that Azure modifies
      app_settings["WEBSITE_CONTENTSHARE"],
    ]
  }
}
