#!/usr/bin/env bash
#
# Dev Environment Management Script
#
# Manages persistent named dev environments (dev1-dev5) for Quix BYOC.
#
# Usage:
#   ./run-dev-env.sh --action <create|deploy|destroy|status> --env-name <dev1-dev5>
#
# Actions:
#   create   - Provision AKS cluster via Terraform
#   deploy   - Install/update Quix BYOC on the cluster
#   destroy  - Tear down the cluster and all resources
#   status   - Report environment health and version info
#
# Required Environment Variables (create/deploy):
#   QUIX_ACR_USERNAME     - ACR username
#   QUIX_ACR_PASSWORD     - ACR password
#   QUIX_LICENSE_KEY      - Quix license key
#   ACR_ID                - Full Azure resource ID of the ACR
#
# Required Environment Variables (deploy only):
#   AUTH0_CLIENT_ID       - Auth0 client ID
#   AUTH0_CLIENT_SECRET   - Auth0 client secret
#   BYOC_PATH             - Path to Infrastructure.BYOC repo
#   BYOCVERSIONS_DIR      - Path to Infrastructure.BYOCVersions repo
#   AWS_ACCESS_KEY_ID     - AWS access key for Route53 (ACME DNS-01)
#   AWS_SECRET_ACCESS_KEY - AWS secret key for Route53 (ACME DNS-01)
#   AWS_HOSTED_ZONE_ID    - Route53 hosted zone ID for quix.io
#
# Optional Environment Variables:
#   LOCATION              - Azure region (default: westeurope)
#   KUBERNETES_VERSION    - AKS version (default: 1.33.6)
#   ACR_REGISTRY          - Container registry (default: quixcontainerregistry.azurecr.io)
#   INSTALLER_TAG         - Installer image tag (read from BYOC chart values)

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Defaults
ACTION=""
ENV_NAME=""
LOCATION="${LOCATION:-westeurope}"
KUBERNETES_VERSION="${KUBERNETES_VERSION:-1.33.6}"
ACR_REGISTRY="${ACR_REGISTRY:-quixcontainerregistry.azurecr.io}"
ACR_ID="${ACR_ID:-}"
BYOC_PATH="${BYOC_PATH:-}"
BYOCVERSIONS_DIR="${BYOCVERSIONS_DIR:-}"
INSTALLER_TAG="${INSTALLER_TAG:-}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()         { echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $*"; }
log_success() { echo -e "${GREEN}[$(date '+%H:%M:%S')] SUCCESS:${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARNING:${NC} $*"; }
log_error()   { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR:${NC} $*"; }
log_section() {
    echo ""
    echo -e "${BLUE}================================================================================${NC}"
    echo -e "${BLUE} $*${NC}"
    echo -e "${BLUE}================================================================================${NC}"
    echo ""
}

usage() {
    head -35 "$0" | tail -30 | sed 's/^#//' | sed 's/^ //'
    exit 0
}

################################################################################
# Argument parsing
################################################################################

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --action)     ACTION="$2"; shift 2 ;;
            --env-name)   ENV_NAME="$2"; shift 2 ;;
            --help|-h)    usage ;;
            *)            log_error "Unknown option: $1"; usage ;;
        esac
    done

    if [[ -z "$ACTION" ]]; then
        log_error "Missing --action"
        usage
    fi

    if [[ -z "$ENV_NAME" ]]; then
        log_error "Missing --env-name"
        usage
    fi

    if ! [[ "$ENV_NAME" =~ ^(fox|owl|lynx|puma|wolf)$ ]]; then
        log_error "env-name must be one of: fox, owl, lynx, puma, wolf"
        exit 1
    fi

    if ! [[ "$ACTION" =~ ^(create|deploy|reset|destroy|status)$ ]]; then
        log_error "action must be one of: create, deploy, reset, destroy, status"
        exit 1
    fi
}

################################################################################
# Validation
################################################################################

validate_tools() {
    local missing=()
    for cmd in terraform az kubectl helm jq; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing[*]}"
        exit 1
    fi
}

validate_create_vars() {
    local missing=()
    for var in QUIX_ACR_USERNAME QUIX_ACR_PASSWORD QUIX_LICENSE_KEY ACR_ID; do
        if [[ -z "${!var:-}" ]]; then
            missing+=("$var")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required environment variables: ${missing[*]}"
        exit 1
    fi
}

validate_deploy_vars() {
    validate_create_vars
    local missing=()
    for var in AUTH0_CLIENT_ID AUTH0_CLIENT_SECRET BYOC_PATH AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_HOSTED_ZONE_ID; do
        if [[ -z "${!var:-}" ]]; then
            missing+=("$var")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required environment variables: ${missing[*]}"
        exit 1
    fi
    if [[ ! -f "$BYOC_PATH/dev.sh" ]]; then
        log_error "BYOC_PATH does not contain dev.sh: $BYOC_PATH"
        exit 1
    fi
}

################################################################################
# Terraform helpers
################################################################################

tf_init() {
    cd "$TF_DIR"

    if [[ -z "${TF_CLI_ARGS_init:-}" ]] && [[ ! -f backend.tfvars ]]; then
        log "No remote backend configured, using local state"
        cat > backend_override.tf <<'EOF'
terraform {
  backend "local" {}
}
EOF
        terraform init -input=false -reconfigure
    else
        terraform init -input=false
    fi
}

tf_vars_file() {
    cat > /tmp/dev-env.tfvars <<EOF
env_name           = "${ENV_NAME}"
location           = "${LOCATION}"
kubernetes_version = "${KUBERNETES_VERSION}"
acr_id             = "${ACR_ID}"
EOF
    echo "/tmp/dev-env.tfvars"
}

################################################################################
# Actions
################################################################################

action_create() {
    log_section "Creating Dev Environment: $ENV_NAME"
    validate_create_vars

    cd "$TF_DIR"
    tf_init

    local tfvars
    tfvars=$(tf_vars_file)

    log "Creating AKS cluster aks-quix-${ENV_NAME}..."
    log "This typically takes 5-10 minutes..."

    terraform apply \
        -input=false \
        -var-file="$tfvars" \
        -auto-approve

    log_success "Infrastructure created for $ENV_NAME"

    # Get credentials
    get_credentials
}

action_deploy() {
    log_section "Deploying Quix BYOC to: $ENV_NAME"
    validate_deploy_vars

    # Always run terraform apply to ensure cluster is fully provisioned.
    # This handles both fresh creation and partial provisioning (e.g. spot
    # eviction during previous create left the RG but not all node pools).
    action_create

    get_credentials

    local cluster_context="aks-quix-${ENV_NAME}-admin"

    # Ensure quix namespace exists
    kubectl --context="$cluster_context" create ns quix --dry-run=client -o yaml \
        | kubectl --context="$cluster_context" apply -f -

    # Generate values file
    generate_values

    local values_file="$SCRIPT_DIR/byoc-values-${ENV_NAME}.yaml"

    cd "$BYOC_PATH"

    # Pre-authenticate helm to the ACR
    log "Authenticating helm to ${ACR_REGISTRY}..."
    echo "$QUIX_ACR_PASSWORD" | helm registry login "$ACR_REGISTRY" \
        --username "$QUIX_ACR_USERNAME" --password-stdin

    # Set BYOCVERSIONS_DIR if provided
    if [[ -n "$BYOCVERSIONS_DIR" ]]; then
        export BYOCVERSIONS_DIR
    fi

    log "Running BYOC installer via dev.sh..."
    ./dev.sh install \
        -f "$values_file" \
        --context "$cluster_context"

    log_success "BYOC deployment complete for $ENV_NAME"

    # Run healthcheck
    action_status_cluster "$cluster_context"
}

action_reset() {
    log_section "Resetting Dev Environment: $ENV_NAME"
    validate_deploy_vars

    get_credentials

    local context="aks-quix-${ENV_NAME}-admin"

    log "Deleting all quix namespaces..."
    kubectl --context="$context" get ns --no-headers -o custom-columns=":metadata.name" \
        | grep "^quix" \
        | xargs -I{} kubectl --context="$context" delete ns {} --ignore-not-found

    log "Creating fresh quix namespace..."
    kubectl --context="$context" create ns quix

    log_success "Cluster wiped, running fresh deploy..."
    action_deploy
}

action_destroy() {
    log_section "Destroying Dev Environment: $ENV_NAME"

    local rg="rg-quix-${ENV_NAME}"

    # Use az group delete instead of terraform destroy.
    # Terraform destroy takes 40+ min for AKS node pools, which exceeds the
    # OIDC token lifetime (~10 min) causing auth failures mid-destroy.
    # az group delete is a single API call that returns quickly with --no-wait.

    if ! az group show --name "$rg" &>/dev/null 2>&1; then
        log "Resource group $rg does not exist, nothing to destroy"
    else
        log "Deleting resource group $rg..."
        az group delete --name "$rg" --yes --no-wait
        log "Waiting for resource group deletion to complete..."
        az group wait --deleted --name "$rg" --timeout 1800 2>/dev/null || true

        if az group show --name "$rg" &>/dev/null 2>&1; then
            log_error "Resource group $rg still exists after waiting"
            exit 1
        fi
        log_success "Resource group $rg deleted"
    fi

    # Clean up terraform state blob
    local tfstate_key="${ENV_NAME}.tfstate"
    local storage_account="quixtfstate"
    local container="dev-environments"

    log "Cleaning up terraform state: ${storage_account}/${container}/${tfstate_key}"
    if az storage blob show --account-name "$storage_account" --container-name "$container" \
        --name "$tfstate_key" &>/dev/null 2>&1; then
        # Break any active lease before deleting
        az storage blob lease break --account-name "$storage_account" --container-name "$container" \
            --blob-name "$tfstate_key" &>/dev/null 2>&1 || true
        az storage blob delete --account-name "$storage_account" --container-name "$container" \
            --name "$tfstate_key"
        log_success "Terraform state deleted"
    else
        log "No terraform state found for $ENV_NAME"
    fi

    log_success "Environment $ENV_NAME destroyed"
}

action_status() {
    log_section "Dev Environment Status"

    # List all dev-environment resource groups
    log "Querying Azure for dev environments..."
    local envs
    envs=$(az group list \
        --query "[?tags.purpose=='dev-environment'].{name:name, location:location, env:tags.environment}" \
        -o json 2>/dev/null || echo "[]")

    local env_count
    env_count=$(echo "$envs" | jq length)

    echo ""
    printf "%-8s %-25s %-15s %-10s\n" "ENV" "RESOURCE GROUP" "LOCATION" "STATUS"
    printf "%-8s %-25s %-15s %-10s\n" "---" "--------------" "--------" "------"

    for slot in fox owl lynx puma wolf; do
        local rg_name="rg-quix-${slot}"
        local match
        match=$(echo "$envs" | jq -r ".[] | select(.name==\"$rg_name\") | .location // empty" 2>/dev/null || echo "")

        if [[ -n "$match" ]]; then
            printf "%-8s %-25s %-15s %-10s\n" "$slot" "$rg_name" "$match" "ACTIVE"
        else
            printf "%-8s %-25s %-15s %-10s\n" "$slot" "-" "-" "EMPTY"
        fi
    done

    echo ""

    # For active environments, try to get pod status
    for slot in fox owl lynx puma wolf; do
        local rg_name="rg-quix-${slot}"
        local cluster_name="aks-quix-${slot}"

        if ! az group show --name "$rg_name" &>/dev/null 2>&1; then
            continue
        fi

        # Try to get credentials and check pods
        if az aks get-credentials --name "$cluster_name" --resource-group "$rg_name" \
            --overwrite-existing --admin &>/dev/null 2>&1; then
            local context="${cluster_name}-admin"
            action_status_cluster "$context"
        fi
    done
}

action_status_cluster() {
    local context="$1"
    log "Cluster: $context"

    # Check nodes
    local node_count
    node_count=$(kubectl --context="$context" get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
    log "  Nodes: ${node_count}"

    # Check pod health across quix namespaces
    local total_pods ready_pods
    total_pods=$(kubectl --context="$context" get pods -A --no-headers 2>/dev/null | grep "^quix" | grep -v Completed | wc -l | tr -d ' ')
    ready_pods=$(kubectl --context="$context" get pods -A --no-headers 2>/dev/null | grep "^quix" | grep -v Completed | grep -c "Running" || true)
    ready_pods=$(echo "$ready_pods" | tr -d ' ')

    if [[ "$total_pods" -gt 0 ]]; then
        local pct=$((ready_pods * 100 / total_pods))
        log "  Pods: ${ready_pods}/${total_pods} running (${pct}%)"
    else
        log "  Pods: none found"
    fi

    # Check for image pull errors
    local pull_errors
    pull_errors=$(kubectl --context="$context" get pods -A --no-headers 2>/dev/null | grep -c "ImagePullBackOff\|ErrImagePull" || true)
    pull_errors=$(echo "$pull_errors" | tr -d ' ')
    if [[ "$pull_errors" -gt 0 ]]; then
        log_warn "  ImagePullBackOff: ${pull_errors} pods"
    fi

    # Helm releases
    local releases
    releases=$(helm list -n quix --kube-context "$context" -q 2>/dev/null || echo "")
    if [[ -n "$releases" ]]; then
        log "  Helm releases: $releases"
    fi
    echo ""
}

################################################################################
# Helpers
################################################################################

get_credentials() {
    log "Getting AKS credentials for $ENV_NAME..."

    local cluster_name="aks-quix-${ENV_NAME}"
    local rg="rg-quix-${ENV_NAME}"

    az aks get-credentials \
        --resource-group "$rg" \
        --name "$cluster_name" \
        --overwrite-existing \
        --admin

    local context="${cluster_name}-admin"
    if ! kubectl --context="$context" get nodes &>/dev/null; then
        log_error "Cannot connect to cluster"
        return 1
    fi

    log_success "Connected to cluster: $context"
    kubectl --context="$context" get nodes
}

generate_values() {
    log "Generating BYOC values file for $ENV_NAME..."

    local values_file="$SCRIPT_DIR/byoc-values-${ENV_NAME}.yaml"
    local template_file="$TF_DIR/values-template.yaml"

    if [[ ! -f "$template_file" ]]; then
        log_error "Template file not found: $template_file"
        return 1
    fi

    # Resolve installer tag from BYOC chart values if not set
    if [[ -z "$INSTALLER_TAG" ]]; then
        local chart_values="$BYOC_PATH/charts/quixplatform-manager/values.yaml"
        if [[ -f "$chart_values" ]] && command -v yq &>/dev/null; then
            INSTALLER_TAG=$(yq eval '.image.tag' "$chart_values")
            log "Resolved installer tag from chart: $INSTALLER_TAG"
        else
            log_error "INSTALLER_TAG not set and cannot read from chart values"
            return 1
        fi
    fi

    sed \
        -e "s|ENV_NAME|${ENV_NAME}|g" \
        -e "s|ACR_REGISTRY|${ACR_REGISTRY}|g" \
        -e "s|QUIX_ACR_USERNAME|${QUIX_ACR_USERNAME}|g" \
        -e "s|QUIX_ACR_PASSWORD|${QUIX_ACR_PASSWORD}|g" \
        -e "s|QUIX_LICENSE_KEY|${QUIX_LICENSE_KEY}|g" \
        -e "s|AUTH0_CLIENT_ID|${AUTH0_CLIENT_ID}|g" \
        -e "s|AUTH0_CLIENT_SECRET|${AUTH0_CLIENT_SECRET}|g" \
        -e "s|AWS_ACCESS_KEY_ID|${AWS_ACCESS_KEY_ID}|g" \
        -e "s|AWS_SECRET_ACCESS_KEY|${AWS_SECRET_ACCESS_KEY}|g" \
        -e "s|AWS_HOSTED_ZONE_ID|${AWS_HOSTED_ZONE_ID}|g" \
        -e "s|INSTALLER_TAG|${INSTALLER_TAG}|g" \
        "$template_file" > "$values_file"

    log_success "Generated: $values_file"
}

################################################################################
# Main
################################################################################

parse_args "$@"
validate_tools

case "$ACTION" in
    create)  action_create ;;
    deploy)  action_deploy ;;
    reset)   action_reset ;;
    destroy) action_destroy ;;
    status)  action_status ;;
esac
