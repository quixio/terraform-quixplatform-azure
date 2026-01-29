################################################################################
# Core
################################################################################

variable "name" {
  description = "Base name for all resources"
  type        = string
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod). Included in alert notifications."
  type        = string
  default     = null
}

variable "resource_group_name" {
  description = "Name of the resource group where resources will be created"
  type        = string
}

variable "location" {
  description = "Azure region for resources"
  type        = string
}

variable "private_grafana" {
  description = "Whether Grafana is only accessible via private network. If true, uses Function App with VNet Integration (~$3-7/mes). If false, uses simpler Application Insights Web Test (~$1/mes)."
  type        = bool
  default     = true
}

################################################################################
# Network (only required when private_grafana = true)
################################################################################

variable "vnet_id" {
  description = "ID of the VNet where the Function App will be integrated (required if private_grafana is true)"
  type        = string
  default     = null
}

variable "vnet_name" {
  description = "Name of the VNet (required if create_function_subnet is true)"
  type        = string
  default     = null
}

variable "vnet_resource_group_name" {
  description = "Resource group of the VNet (defaults to resource_group_name)"
  type        = string
  default     = null
}

variable "create_function_subnet" {
  description = "Whether to create a dedicated subnet for Function App"
  type        = bool
  default     = true
}

variable "function_subnet_id" {
  description = "Existing subnet ID for Function App (required if create_function_subnet is false)"
  type        = string
  default     = null
}

variable "function_subnet_cidr" {
  description = "CIDR for Function App subnet (minimum /26, required if create_function_subnet is true)"
  type        = string
  default     = "10.240.10.0/26"
}

################################################################################
# Grafana Health Check
################################################################################

variable "grafana_health_url" {
  description = "URL for Grafana health endpoint. For private: internal IP (e.g., http://10.240.1.50:3000/api/health). For public: external URL (e.g., https://grafana.example.com/api/health)"
  type        = string
}

variable "check_interval_minutes" {
  description = "Interval between health checks in minutes. For private mode: 1-59. For public mode: 5, 10, or 15 (Azure Web Test limitation)."
  type        = number
  default     = 5

  validation {
    condition     = var.check_interval_minutes >= 1 && var.check_interval_minutes <= 59
    error_message = "check_interval_minutes must be between 1 and 59."
  }
}

variable "health_check_timeout_seconds" {
  description = "Timeout for HTTP health check in seconds"
  type        = number
  default     = 10
}

variable "web_test_locations" {
  description = "Azure locations for Web Test probes (only used when private_grafana = false)"
  type        = list(string)
  default = [
    "emea-nl-ams-azr",  # West Europe
    "emea-gb-db3-azr",  # UK South
    "emea-fr-pra-edge"  # France Central
  ]
}

################################################################################
# Alerting
################################################################################

variable "enable_alerts" {
  description = "Enable metric alerts for Grafana availability"
  type        = bool
  default     = true
}

variable "alert_severity" {
  description = "Severity of the alert (0=Critical, 1=Error, 2=Warning, 3=Informational, 4=Verbose)"
  type        = number
  default     = 0

  validation {
    condition     = var.alert_severity >= 0 && var.alert_severity <= 4
    error_message = "alert_severity must be between 0 and 4."
  }
}

variable "alert_window_minutes" {
  description = "Time window in minutes for evaluating alert conditions. Alert triggers if Grafana is down for this duration."
  type        = number
  default     = 30

  validation {
    condition     = contains([1, 5, 10, 15, 30, 45, 60, 120, 180, 360, 720, 1440], var.alert_window_minutes)
    error_message = "alert_window_minutes must be one of: 1, 5, 10, 15, 30, 45, 60, 120, 180, 360, 720, 1440."
  }
}

variable "alert_email_receivers" {
  description = "List of email addresses for alert notifications"
  type        = list(string)
  default     = []
}

variable "opsgenie_api_key" {
  description = "OpsGenie API key for alert integration"
  type        = string
  default     = null
  sensitive   = true
}

variable "opsgenie_api_url" {
  description = "OpsGenie API URL for Azure Monitor integration (defaults to US region)"
  type        = string
  default     = "https://api.opsgenie.com/v1/json/azure"
}

variable "alert_webhook_receivers" {
  description = "Additional webhook receivers for alerts"
  type = list(object({
    name = string
    uri  = string
  }))
  default = []
}

################################################################################
# Tags
################################################################################

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
