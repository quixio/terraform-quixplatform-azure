#!/usr/bin/env bash
set -euo pipefail

#
# install.sh - Install Quix Platform on airgap test cluster
#
# Prerequisites:
#   - Terraform apply completed
#   - Azure CLI authenticated
#   - Required environment variables set
#
# Usage:
#   ./scripts/install.sh
#
# Environment variables:
#   RESOURCE_GROUP     - AKS resource group (from terraform output)
#   CLUSTER_NAME       - AKS cluster name (from terraform output)
#   ACR_USERNAME       - quixregistry username (default: quixregistry)
#   ACR_PASSWORD       - quixregistry password (required)
#   BYOC_ZIP_VERSION   - BYOC zip version (required)
#   BYOC_TENANT_ID     - Azure tenant ID for zip storage
#   BYOC_CLIENT_ID     - Service principal client ID
#   BYOC_CLIENT_SECRET - Service principal secret
#   LICENSE_KEY        - Quix license key (optional, test key used if not set)
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# Get terraform outputs if not set via env
get_terraform_output() {
    local name="$1"
    terraform -chdir="$TF_DIR" output -raw "$name" 2>/dev/null || echo ""
}

RESOURCE_GROUP="${RESOURCE_GROUP:-$(get_terraform_output resource_group_name)}"
CLUSTER_NAME="${CLUSTER_NAME:-$(get_terraform_output cluster_name)}"

# Registry config
ACR_SERVER="quixregistry.azurecr.io"
ACR_USERNAME="${ACR_USERNAME:-quixregistry}"
HELM_CHART_VERSION="${HELM_CHART_VERSION:-0.1.20260126622}"
ANSIBLE_BUILDER_TAG="${ANSIBLE_BUILDER_TAG:-1.6.7}"

# Validate required vars
if [[ -z "$RESOURCE_GROUP" || -z "$CLUSTER_NAME" ]]; then
    log_error "RESOURCE_GROUP and CLUSTER_NAME are required"
    log_error "Either set them as env vars or run terraform apply first"
    exit 1
fi

if [[ -z "${ACR_PASSWORD:-}" ]]; then
    log_error "ACR_PASSWORD is required"
    exit 1
fi

if [[ -z "${BYOC_ZIP_VERSION:-}" ]]; then
    log_error "BYOC_ZIP_VERSION is required"
    exit 1
fi

log_info "Installing Quix Platform"
log_info "  Cluster: $CLUSTER_NAME"
log_info "  Resource Group: $RESOURCE_GROUP"
log_info "  Registry: $ACR_SERVER"
log_info "  Chart Version: $HELM_CHART_VERSION"

# Get kubeconfig
log_info "Getting kubeconfig..."
az aks get-credentials --name "$CLUSTER_NAME" --resource-group "$RESOURCE_GROUP" --overwrite-existing

# Verify connection
log_info "Verifying cluster connection..."
kubectl get nodes || { log_error "Cannot connect to cluster"; exit 1; }

# Create namespace
log_info "Creating quix namespace..."
kubectl create namespace quix --dry-run=client -o yaml | kubectl apply -f -

# Create pull secrets
log_info "Creating pull secrets..."
kubectl create secret docker-registry registrypullsecret \
    --docker-server="$ACR_SERVER" \
    --docker-username="$ACR_USERNAME" \
    --docker-password="$ACR_PASSWORD" \
    --namespace quix \
    --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret docker-registry quixregistry-pull-secret \
    --docker-server="$ACR_SERVER" \
    --docker-username="$ACR_USERNAME" \
    --docker-password="$ACR_PASSWORD" \
    --namespace quix \
    --dry-run=client -o yaml | kubectl apply -f -

# Create values file
log_info "Creating helm values..."
VALUES_FILE=$(mktemp)
cat > "$VALUES_FILE" << EOF
licenseKey: "${LICENSE_KEY:-airgap-test-license-70784}"

global:
  customerName: "airgap-test-${CLUSTER_NAME##*-}"
  environment: "test"
  kubeContext: "agent-internal"
  namespace: "quix"
  namespacePrefix: "quix"
  cloudProvider: "azure"
  privateDockerRegistryUrl: "$ACR_SERVER"
  privateDockerRegistryUsername: "$ACR_USERNAME"
  privateDockerRegistryPassword: "$ACR_PASSWORD"
  helmNamespace: "helm"
  imageNamespace: ""
  privateByocStorageAccount:
    enabled: true
    secretName: "zip-secret"
    tenantId: "${BYOC_TENANT_ID:-REDACTED-TENANT-ID-PLACEHOLDER}"
    clientId: "${BYOC_CLIENT_ID:-REDACTED-CLIENT-ID-PLACEHOLDER}"
    clientSecret: "${BYOC_CLIENT_SECRET:-}"
  byocZipVersion: "$BYOC_ZIP_VERSION"
  acrRegistry: "$ACR_SERVER"
  rootDomain: "airgap-test.internal"
  tier: "BringYourOwnCluster"
  externalByocVersionsRepository:
    enabled: false

image:
  containerRegistry: "$ACR_SERVER"
  pullPolicy: "IfNotPresent"
  service: "quixplatform-ansible-builder"
  tag: "$ANSIBLE_BUILDER_TAG"

imagePullSecret:
  enabled: true
  name: "registrypullsecret"
  useIdentityBasedAuth: false

platformVariables:
  tolerations:
    - key: "kubernetes.azure.com/scalesetpriority"
      operator: "Equal"
      value: "spot"
      effect: "NoSchedule"
  infrastructure:
    storage:
      class:
        premiumRwo: "managed-csi"
        standardRwo: "managed-csi"
        standardRwx: "azurefile-csi"
  platform:
    subdomain: "portal"
    customDomain: "airgap-test.internal"
    featureFlags:
      customCertificateAuthoritySupplied: "false"
  ingress:
    serviceType: "LoadBalancer"
    certClusterIssuerCreate: "false"

rolesFlags:
  streamingKafkaEnableStrimziOperator: "true"
  streamingKafkaEnableInternalHosting: "true"
  mongoDbEnabled: "true"
  platformEnabled: "true"
  ingressEnabled: "true"
  giteaEnabled: "true"
  acmeEnabled: "false"
  monitoringEnabled: "false"
  loggingEnabled: "false"
  internalRegistryEnabled: "false"
  installLoadbalancer: "false"

serviceAccount:
  name: "quix-agent-account"
EOF

# Install helm chart
log_info "Installing quixplatform-manager helm chart..."
helm upgrade --install quix-platform \
    "oci://${ACR_SERVER}/helm/quixplatform-manager" \
    --version "$HELM_CHART_VERSION" \
    --namespace quix \
    --values "$VALUES_FILE" \
    --wait --timeout 20m

rm -f "$VALUES_FILE"

log_info "Helm install completed. Waiting for installer job..."

# Wait for installer job
kubectl wait --for=condition=complete job/quixplatform-manager-job -n quix --timeout=30m || {
    log_warn "Installer job did not complete within timeout"
    log_info "Checking job status..."
    kubectl get jobs -n quix
    kubectl logs job/quixplatform-manager-job -n quix --tail=50 || true
}

log_info "Installation script completed"
