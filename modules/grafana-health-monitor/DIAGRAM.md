# Grafana Health Monitor - Architecture Diagram

## Overview

This module monitors Grafana availability and sends alerts when it becomes unreachable. It supports two modes depending on whether Grafana is publicly accessible or only available within a private network.

---

## Public Mode (`private_grafana = false`) - ~$1/month

Use this mode when Grafana has a public IP or is accessible via a public URL.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              AZURE                                          │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    Application Insights                              │   │
│  │  ┌─────────────────────┐     ┌─────────────────────┐               │   │
│  │  │   Standard Web Test │     │    Metric Alert     │               │   │
│  │  │   (every 5 min)     │────▶│  (failed_locations  │               │   │
│  │  │                     │     │      >= 2)          │               │   │
│  │  └──────────┬──────────┘     └──────────┬──────────┘               │   │
│  └─────────────│────────────────────────────│──────────────────────────┘   │
│                │                            │                               │
│                │ HTTP GET                   │                               │
│                │ /api/health                │                               │
│                ▼                            ▼                               │
│  ┌─────────────────────┐        ┌─────────────────────┐                    │
│  │  Grafana (public)   │        │    Action Group     │                    │
│  │  LoadBalancer IP    │        │  ┌───────────────┐  │                    │
│  │  52.xxx.xxx.xxx     │        │  │ Email         │  │                    │
│  └─────────────────────┘        │  │ OpsGenie      │  │                    │
│                                 │  │ Webhooks      │  │                    │
│  Probes from:                   │  └───────┬───────┘  │                    │
│  • West Europe                  └──────────│──────────┘                    │
│  • UK South                                │                               │
│  • France Central                          ▼                               │
│                                 ┌─────────────────────┐                    │
│                                 │  Alert!             │                    │
│                                 │  "Grafana is down"  │                    │
│                                 └─────────────────────┘                    │
└─────────────────────────────────────────────────────────────────────────────┘
```

### How it works (Public Mode)

1. **Azure Web Test** sends HTTP GET requests to Grafana's `/api/health` endpoint every 5 minutes
2. Requests originate from multiple Azure datacenters (configurable locations)
3. If 2+ locations fail to reach Grafana, the **Metric Alert** triggers
4. **Action Group** sends notifications via Email, OpsGenie, or custom webhooks

---

## Private Mode (`private_grafana = true`) - ~$3-7/month

Use this mode when Grafana is only accessible within a VNet (private cluster).

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              AZURE                                          │
│                                                                             │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │                         VNet (10.240.0.0/16)                          │  │
│  │                                                                        │  │
│  │  ┌────────────────────────┐      ┌────────────────────────────────┐  │  │
│  │  │  Function App Subnet   │      │      AKS Cluster               │  │  │
│  │  │  (10.240.10.0/26)      │      │      (10.240.0.0/22)           │  │  │
│  │  │                        │      │                                │  │  │
│  │  │  ┌──────────────────┐  │      │  ┌──────────────────────────┐ │  │  │
│  │  │  │  Azure Function  │  │ HTTP │  │  Grafana (Internal LB)   │ │  │  │
│  │  │  │  (Timer: 1 min)  │──┼──────┼─▶│  10.240.1.50:3000        │ │  │  │
│  │  │  │                  │  │ GET  │  │                          │ │  │  │
│  │  │  └────────┬─────────┘  │      │  └──────────────────────────┘ │  │  │
│  │  └───────────│────────────┘      └────────────────────────────────┘  │  │
│  └──────────────│───────────────────────────────────────────────────────┘  │
│                 │                                                           │
│                 │ Custom Metric                                             │
│                 │ "GrafanaAvailability"                                     │
│                 ▼                                                           │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    Application Insights                              │   │
│  │                                                                      │   │
│  │  ┌─────────────────────┐     ┌─────────────────────┐               │   │
│  │  │  Custom Metrics     │     │    Metric Alert     │               │   │
│  │  │  • Availability     │────▶│  (Availability < 1) │               │   │
│  │  │  • Response Time    │     │                     │               │   │
│  │  └─────────────────────┘     └──────────┬──────────┘               │   │
│  └──────────────────────────────────────────│──────────────────────────┘   │
│                                             │                               │
│                                             ▼                               │
│                                 ┌─────────────────────┐                    │
│                                 │    Action Group     │                    │
│                                 │  ┌───────────────┐  │                    │
│                                 │  │ Email         │  │                    │
│                                 │  │ OpsGenie      │──┼──▶ Alert!         │
│                                 │  │ Webhooks      │  │                    │
│                                 │  └───────────────┘  │                    │
│                                 └─────────────────────┘                    │
└─────────────────────────────────────────────────────────────────────────────┘
```

### How it works (Private Mode)

1. **Azure Function** runs on a timer (configurable, default 1 minute)
2. Function is deployed with **VNet Integration** in a dedicated subnet
3. Function sends HTTP GET to Grafana's internal IP within the VNet
4. Function emits custom metrics (`GrafanaAvailability`, `GrafanaResponseTime`) to Application Insights
5. **Metric Alert** monitors the custom metric and triggers when availability drops
6. **Action Group** sends notifications via Email, OpsGenie, or custom webhooks

---

## Resources Created by Mode

| Resource | Public | Private |
|----------|:------:|:-------:|
| Application Insights | ✅ | ✅ |
| Action Group | ✅ | ✅ |
| Metric Alert | ✅ | ✅ |
| Standard Web Test | ✅ | ❌ |
| Function App | ❌ | ✅ |
| Service Plan (Consumption) | ❌ | ✅ |
| Storage Account | ❌ | ✅ |
| Subnet (delegated) | ❌ | ✅ |

---

## Cost Comparison

| Mode | Monthly Cost | Best For |
|------|-------------|----------|
| Public | ~$1/month | Grafana with public endpoint |
| Private | ~$3-7/month | Grafana in private VNet |

---

## Alert Flow

```
Grafana Unreachable
        │
        ▼
┌───────────────────┐
│  Health Check     │
│  Fails            │
└─────────┬─────────┘
          │
          ▼
┌───────────────────┐
│  Metric Alert     │
│  Triggers         │
└─────────┬─────────┘
          │
          ▼
┌───────────────────┐
│  Action Group     │
│  Notifies         │
└─────────┬─────────┘
          │
          ├──────────────┬──────────────┐
          ▼              ▼              ▼
    ┌──────────┐  ┌──────────┐  ┌──────────┐
    │  Email   │  │ OpsGenie │  │ Webhook  │
    └──────────┘  └──────────┘  └──────────┘
```
