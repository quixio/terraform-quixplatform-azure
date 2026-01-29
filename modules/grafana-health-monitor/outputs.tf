################################################################################
# Function App (only when private_grafana = true)
################################################################################

output "function_app_id" {
  description = "ID of the Function App (null when private_grafana = false)"
  value       = var.private_grafana ? azurerm_linux_function_app.health_monitor[0].id : null
}

output "function_app_name" {
  description = "Name of the Function App (null when private_grafana = false)"
  value       = var.private_grafana ? azurerm_linux_function_app.health_monitor[0].name : null
}

output "function_app_hostname" {
  description = "Default hostname of the Function App (null when private_grafana = false)"
  value       = var.private_grafana ? azurerm_linux_function_app.health_monitor[0].default_hostname : null
}

output "function_app_principal_id" {
  description = "Principal ID of the Function App managed identity (null when private_grafana = false)"
  value       = var.private_grafana ? azurerm_linux_function_app.health_monitor[0].identity[0].principal_id : null
}

################################################################################
# Web Test (only when private_grafana = false)
################################################################################

output "web_test_id" {
  description = "ID of the Application Insights Web Test (null when private_grafana = true)"
  value       = var.private_grafana ? null : azurerm_application_insights_standard_web_test.grafana[0].id
}

################################################################################
# Application Insights
################################################################################

output "application_insights_id" {
  description = "ID of Application Insights"
  value       = azurerm_application_insights.this.id
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights"
  value       = azurerm_application_insights.this.connection_string
  sensitive   = true
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights"
  value       = azurerm_application_insights.this.instrumentation_key
  sensitive   = true
}

################################################################################
# Alerting
################################################################################

output "action_group_id" {
  description = "ID of the Action Group for alerts"
  value       = var.enable_alerts ? azurerm_monitor_action_group.alerts[0].id : null
}

################################################################################
# Network (only when private_grafana = true)
################################################################################

output "function_subnet_id" {
  description = "ID of the Function App subnet (null when private_grafana = false)"
  value       = local.function_subnet_id
}

################################################################################
# Storage (only when private_grafana = true)
################################################################################

output "storage_account_name" {
  description = "Name of the Storage Account used by Function App (null when private_grafana = false)"
  value       = var.private_grafana ? azurerm_storage_account.function[0].name : null
}

################################################################################
# Mode
################################################################################

output "monitoring_mode" {
  description = "The monitoring mode being used: 'function_app' for private Grafana, 'web_test' for public Grafana"
  value       = var.private_grafana ? "function_app" : "web_test"
}
