################################################################################
# Example: Public AKS with Grafana and Health Monitor
#
# This example demonstrates:
# - Public AKS cluster
# - Grafana installed via Helm with public LoadBalancer
# - Grafana health monitor module (public mode - Web Test)
# - OpsGenie integration for alerts
################################################################################

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.112"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
    }
  }
}

provider "azurerm" {
  features {}
}

################################################################################
# Variables
################################################################################

variable "opsgenie_api_key" {
  description = "OpsGenie API key for alert integration"
  type        = string
  sensitive   = true
  default     = ""
}

variable "alert_emails" {
  description = "Email addresses to receive alerts"
  type        = list(string)
  default     = ["quique@quix.io"]
}

################################################################################
# Resource Group
################################################################################

resource "azurerm_resource_group" "this" {
  name     = "rg-quix-grafana"
  location = "westeurope"

  tags = {
    environment = "demo"
    project     = "Quix"
  }
}

################################################################################
# AKS Cluster
################################################################################

module "aks" {
  source = "../../modules/quix-aks"

  name                    = "quix-aks-grafana"
  location                = azurerm_resource_group.this.location
  resource_group_name     = azurerm_resource_group.this.name
  create_resource_group   = false
  kubernetes_version      = "1.33.5"
  sku_tier                = "Standard"
  private_cluster_enabled = false

  vnet_name          = "vnet-quix-grafana"
  vnet_address_space = ["10.240.0.0/16"]
  nodes_subnet_name  = "Subnet-Nodes"
  nodes_subnet_cidr  = "10.240.0.0/22"

  identity_name     = "quix-grafana-nat-id"
  public_ip_name    = "quix-grafana-nat-ip"
  nat_gateway_name  = "quix-grafana-nat"
  availability_zone = "1"

  enable_credentials_fetch = true

  # Separate node pools for workload isolation (optional in single-cluster setups)
  # Use quix.io/node-purpose labels to schedule workloads on specific pools
  node_pools = {
    system = {
      name       = "system"
      type       = "system"
      node_count = 2
      vm_size    = "Standard_D2ds_v5"
    }
    platform = {
      name       = "platform"
      type       = "user"
      node_count = 3
      vm_size    = "Standard_E4ds_v5"
      labels     = { "quix.io/node-purpose" = "platform-services" }
    }
    deployments = {
      name       = "deployments"
      type       = "user"
      node_count = 3
      vm_size    = "Standard_E4ds_v5"
      labels     = { "quix.io/node-purpose" = "customer-deployments" }
    }
  }

  network_profile = {
    network_plugin_mode = "vnet"
    service_cidr        = "172.22.0.0/16"
    dns_service_ip      = "172.22.0.10"
  }

  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  tags = {
    environment = "demo"
    project     = "Quix"
  }

  depends_on = [azurerm_resource_group.this]
}

################################################################################
# Get AKS Credentials
################################################################################

data "azurerm_kubernetes_cluster" "this" {
  name                = module.aks.cluster_name
  resource_group_name = module.aks.resource_group_name

  depends_on = [module.aks]
}

provider "kubernetes" {
  host                   = data.azurerm_kubernetes_cluster.this.kube_config[0].host
  client_certificate     = base64decode(data.azurerm_kubernetes_cluster.this.kube_config[0].client_certificate)
  client_key             = base64decode(data.azurerm_kubernetes_cluster.this.kube_config[0].client_key)
  cluster_ca_certificate = base64decode(data.azurerm_kubernetes_cluster.this.kube_config[0].cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = data.azurerm_kubernetes_cluster.this.kube_config[0].host
    client_certificate     = base64decode(data.azurerm_kubernetes_cluster.this.kube_config[0].client_certificate)
    client_key             = base64decode(data.azurerm_kubernetes_cluster.this.kube_config[0].client_key)
    cluster_ca_certificate = base64decode(data.azurerm_kubernetes_cluster.this.kube_config[0].cluster_ca_certificate)
  }
}

################################################################################
# Grafana Namespace
################################################################################

resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
  }

  depends_on = [module.aks]
}

################################################################################
# Grafana via Helm
################################################################################

resource "helm_release" "grafana" {
  name       = "grafana"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "grafana"
  version    = "7.3.0"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name

  values = [<<-EOF
    adminPassword: "admin"

    service:
      type: LoadBalancer
      annotations:
        service.beta.kubernetes.io/azure-load-balancer-health-probe-request-path: /api/health

    persistence:
      enabled: false

    resources:
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        cpu: 500m
        memory: 512Mi

    # Health check endpoint
    readinessProbe:
      httpGet:
        path: /api/health
        port: 3000

    livenessProbe:
      httpGet:
        path: /api/health
        port: 3000
  EOF
  ]

  depends_on = [kubernetes_namespace.monitoring]
}

################################################################################
# Get Grafana External IP
################################################################################

data "kubernetes_service" "grafana" {
  metadata {
    name      = "grafana"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }

  depends_on = [helm_release.grafana]
}

################################################################################
# Grafana Health Monitor (Public Mode - Web Test)
################################################################################

module "grafana_watchdog" {
  source = "../../modules/grafana-health-monitor"

  name        = "quix-grafana-monitor"
  environment = "demo"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location

  # Public mode - uses simple Web Test (cheaper, ~$1/month)
  private_grafana    = false
  grafana_health_url = "http://${data.kubernetes_service.grafana.status[0].load_balancer[0].ingress[0].ip}:80/api/health"

  # Check every 5 minutes from 3 European locations
  check_interval_minutes = 5
  web_test_locations = [
    "emea-nl-ams-azr",  # West Europe
  ]

  # Alerting
  enable_alerts        = true
  alert_severity       = 0  # Critical
  alert_window_minutes = 1 # Alert only if down for 30 minutes
  alert_email_receivers = []
  opsgenie_api_key      = var.opsgenie_api_key

  tags = {
    environment = "demo"
    project     = "Quix"
  }

  depends_on = [helm_release.grafana]
}

################################################################################
# Outputs
################################################################################

output "grafana_url" {
  description = "URL to access Grafana (user: admin, password: admin)"
  value       = "http://${data.kubernetes_service.grafana.status[0].load_balancer[0].ingress[0].ip}"
}

output "grafana_health_url" {
  description = "Grafana health endpoint being monitored"
  value       = "http://${data.kubernetes_service.grafana.status[0].load_balancer[0].ingress[0].ip}/api/health"
}

output "monitoring_mode" {
  description = "Monitoring mode being used"
  value       = module.grafana_watchdog.monitoring_mode
}

output "application_insights_id" {
  description = "Application Insights ID for viewing metrics"
  value       = module.grafana_watchdog.application_insights_id
}

output "web_test_id" {
  description = "Web Test ID"
  value       = module.grafana_watchdog.web_test_id
}

output "action_group_id" {
  description = "Action Group ID for alerts"
  value       = module.grafana_watchdog.action_group_id
}
