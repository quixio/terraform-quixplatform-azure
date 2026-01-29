# Example: Public AKS with Grafana Health Monitor (Public Mode)

This example demonstrates how to deploy an AKS cluster with Grafana and health monitoring using Azure Application Insights Web Test.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ VNet: 10.240.0.0/16                                         │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ Subnet-Nodes: 10.240.0.0/22                          │   │
│  │                                                       │   │
│  │  ┌──────────────────────────────────────────────┐    │   │
│  │  │ AKS Cluster (Public API Server)              │    │   │
│  │  │                                               │    │   │
│  │  │  ┌─────────┐                                  │    │   │
│  │  │  │ Grafana │ ◄── Public LoadBalancer          │    │   │
│  │  │  │ :3000   │     (External IP)                │    │   │
│  │  │  └─────────┘                                  │    │   │
│  │  └──────────────────────────────────────────────┘    │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘

                          │
                          │ Public Internet
                          ▼

┌─────────────────────────────────────────────────────────────┐
│ Azure Application Insights                                   │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ Standard Web Test                                     │   │
│  │  - URL: http://<grafana-ip>/api/health               │   │
│  │  - Frequency: Every 5 minutes                        │   │
│  │  - Locations: West Europe                            │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ Metric Alert                                          │   │
│  │  - Condition: Web Test fails                         │   │
│  │  - Window: Configurable (default 30 min)             │   │
│  │  - Action: OpsGenie / Email                          │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘

                          │
                          │ Alert Notification
                          ▼

         ┌────────────────────────────────┐
         │ OpsGenie / Email               │
         │  - Incident created            │
         │  - Environment: [DEMO]         │
         └────────────────────────────────┘
```

## Features

- **AKS Cluster**: Public Kubernetes cluster with single node pool
- **Grafana**: Deployed via Helm with public LoadBalancer
- **Health Monitoring**: Azure Application Insights Standard Web Test
- **Alerting**: OpsGenie integration with environment context
- **Cost**: ~$1/month for Web Test monitoring

## Components

### 1. AKS Cluster
- Public API server (accessible from internet)
- Node pools: system (D2ds_v5), platform + deployments (E4ds_v5) with `quix.io/node-purpose` labels
- NAT Gateway for egress traffic

### 2. Grafana
- Deployed via Helm chart (v7.3.0)
- Exposed via public LoadBalancer
- Health endpoint: `/api/health`

### 3. Grafana Health Monitor Module (Public Mode)
- **Application Insights**: Collects availability metrics
- **Standard Web Test**: Pings Grafana health endpoint from Azure locations
- **Metric Alert**: Triggers when health check fails for configured duration
- **Action Group**: Sends notifications to OpsGenie/email

## Usage

### Deploy the infrastructure

```bash
cd examples/public-quix-infr-grafana-monitor

# Set OpsGenie API key (optional)
export TF_VAR_opsgenie_api_key="your-api-key"

terraform init
terraform plan
terraform apply
```

### Access Grafana

```bash
# Get the external IP
terraform output grafana_url

# Open in browser (user: admin, password: admin)
```

### Access the cluster

```bash
# Get credentials
az aks get-credentials --resource-group rg-quix-grafana --name quix-aks-grafana

# Verify connectivity
kubectl get nodes
kubectl get svc -n monitoring
```

## Important Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `opsgenie_api_key` | `""` | OpsGenie API key for alert integration |
| `alert_emails` | `[]` | Email addresses to receive alerts |

### Module Variables

| Variable | Value | Description |
|----------|-------|-------------|
| `private_grafana` | `false` | Uses Web Test (public mode) |
| `check_interval_minutes` | `5` | Check frequency (5, 10, or 15 min for Web Test) |
| `alert_window_minutes` | `30` | Alert only if down for this duration |
| `alert_severity` | `0` | Critical severity |
| `environment` | `demo` | Included in alert name: `[DEMO]` |

## Outputs

- `grafana_url`: Public URL to access Grafana
- `grafana_health_url`: Health endpoint being monitored
- `monitoring_mode`: `web_test` (public mode)
- `application_insights_id`: Application Insights resource ID
- `web_test_id`: Web Test resource ID
- `action_group_id`: Action Group for alerts

## How Alerting Works

1. **Web Test** pings `http://<grafana-ip>/api/health` every 5 minutes
2. **Application Insights** records availability results
3. **Metric Alert** evaluates if test failed for `alert_window_minutes`
4. **Action Group** sends notification to OpsGenie with `[DEMO]` prefix

### Alert Example

```
Alert Name: [DEMO] quix-grafana-monitor-grafana-down
Description: [DEMO] Grafana health check failed for 30 minutes.
Severity: Critical (0)
```

## Cleanup

```bash
terraform destroy
```

## Important Notes

1. **Public Grafana**: This example exposes Grafana to the internet. For production, use authentication or Internal LoadBalancer.
2. **Web Test Locations**: By default uses West Europe. Add more locations for redundancy.
3. **OpsGenie Integration**: Uses Azure Monitor webhook format (`/v1/json/azure`).
4. **Smart Detector**: Auto-created by Azure but disabled by the module to avoid duplicate alerts.

## Alternative: Private Grafana

For Grafana accessible only within VNet, see [public-quix-infr-grafana-internal-lb](../public-quix-infr-grafana-internal-lb/) example which uses Function App with VNet Integration.

## References

- [Azure Application Insights Web Tests](https://docs.microsoft.com/azure/azure-monitor/app/availability-overview)
- [Azure Monitor Alerts](https://docs.microsoft.com/azure/azure-monitor/alerts/alerts-overview)
- [Grafana Helm Chart](https://github.com/grafana/helm-charts)
