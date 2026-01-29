################################################################################
# Application Insights
################################################################################

resource "azurerm_application_insights" "this" {
  name                = "${var.name}-insights"
  resource_group_name = var.resource_group_name
  location            = var.location
  application_type    = "web"

  tags = local.tags
}

################################################################################
# Disable Smart Detector (Failure Anomalies) - auto-created by Azure
################################################################################

resource "azurerm_monitor_smart_detector_alert_rule" "failure_anomalies" {
  name                = "Failure Anomalies - ${azurerm_application_insights.this.name}"
  resource_group_name = var.resource_group_name
  detector_type       = "FailureAnomaliesDetector"
  scope_resource_ids  = [azurerm_application_insights.this.id]
  severity            = "Sev3"
  frequency           = "PT1M"
  enabled             = false

  action_group {
    ids = var.enable_alerts ? [azurerm_monitor_action_group.alerts[0].id] : []
  }

  tags = local.tags
}

################################################################################
# Action Group
################################################################################

resource "azurerm_monitor_action_group" "alerts" {
  count = var.enable_alerts ? 1 : 0

  name                = "${var.name}-action-group"
  resource_group_name = var.resource_group_name
  short_name          = substr(var.name, 0, 12)

  # Email receivers
  dynamic "email_receiver" {
    for_each = var.alert_email_receivers
    content {
      name          = "email-${email_receiver.key}"
      email_address = email_receiver.value
    }
  }

  # OpsGenie integration
  dynamic "webhook_receiver" {
    for_each = var.opsgenie_api_key != null ? [1] : []
    content {
      name                    = "opsgenie"
      service_uri             = "${var.opsgenie_api_url}?apiKey=${var.opsgenie_api_key}"
      use_common_alert_schema = true
    }
  }

  # Additional webhook receivers
  dynamic "webhook_receiver" {
    for_each = var.alert_webhook_receivers
    content {
      name                    = webhook_receiver.value.name
      service_uri             = webhook_receiver.value.uri
      use_common_alert_schema = true
    }
  }

  tags = local.tags
}

################################################################################
# Standard Web Test (for public Grafana - simpler and cheaper)
################################################################################

resource "azurerm_application_insights_standard_web_test" "grafana" {
  count = var.private_grafana ? 0 : 1

  name                    = "${var.name}-webtest"
  resource_group_name     = var.resource_group_name
  location                = var.location
  application_insights_id = azurerm_application_insights.this.id
  geo_locations           = var.web_test_locations
  frequency               = var.check_interval_minutes >= 5 ? var.check_interval_minutes * 60 : 300 # Minimum 300 seconds (5 min)
  timeout                 = var.health_check_timeout_seconds
  enabled                 = true

  request {
    url = var.grafana_health_url
  }

  validation_rules {
    expected_status_code = 200
  }

  tags = local.tags
}

################################################################################
# Alert - Web Test Failed (public Grafana)
################################################################################

resource "azurerm_monitor_metric_alert" "webtest_failed" {
  count = var.enable_alerts && !var.private_grafana ? 1 : 0

  name                = "${local.alert_prefix}${var.name}-grafana-down"
  resource_group_name = var.resource_group_name
  scopes = [
    azurerm_application_insights.this.id,
    azurerm_application_insights_standard_web_test.grafana[0].id
  ]
  description = "${local.alert_prefix}Grafana health check failed for ${var.alert_window_minutes} minutes."
  severity    = var.alert_severity
  frequency   = "PT1M"
  window_size = "PT${var.alert_window_minutes}M"

  application_insights_web_test_location_availability_criteria {
    web_test_id           = azurerm_application_insights_standard_web_test.grafana[0].id
    component_id          = azurerm_application_insights.this.id
    failed_location_count = 1
  }

  action {
    action_group_id = azurerm_monitor_action_group.alerts[0].id
  }

  tags = local.tags
}

################################################################################
# Metric Alert - Grafana Availability (private Grafana via Function App)
################################################################################

resource "azurerm_monitor_metric_alert" "grafana_down" {
  count = var.enable_alerts && var.private_grafana ? 1 : 0

  name                = "${local.alert_prefix}${var.name}-grafana-down"
  resource_group_name = var.resource_group_name
  scopes              = [azurerm_application_insights.this.id]
  description         = "${local.alert_prefix}Grafana health check failed for ${var.alert_window_minutes} minutes. Grafana may be unreachable or returning errors."
  severity            = var.alert_severity
  frequency           = "PT1M"
  window_size         = "PT${var.alert_window_minutes}M"

  criteria {
    metric_namespace = "azure.applicationinsights"
    metric_name      = "customMetrics/GrafanaAvailability"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = 1
  }

  action {
    action_group_id = azurerm_monitor_action_group.alerts[0].id
  }

  tags = local.tags
}

################################################################################
# Metric Alert - Function Execution Failures (private Grafana)
################################################################################

resource "azurerm_monitor_metric_alert" "function_failures" {
  count = var.enable_alerts && var.private_grafana ? 1 : 0

  name                = "${var.name}-function-failures"
  resource_group_name = var.resource_group_name
  scopes              = [azurerm_linux_function_app.health_monitor[0].id]
  description         = "Alert when the health check function itself fails to execute. The watchdog may be broken."
  severity            = var.alert_severity
  frequency           = "PT1M"
  window_size         = "PT5M"

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "FunctionExecutionCount"
    aggregation      = "Total"
    operator         = "LessThan"
    threshold        = 1
  }

  action {
    action_group_id = azurerm_monitor_action_group.alerts[0].id
  }

  tags = local.tags
}
