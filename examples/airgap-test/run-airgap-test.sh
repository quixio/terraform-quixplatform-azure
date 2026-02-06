#!/usr/bin/env bash
#
# Airgap Test Pipeline - One-button CI/CD simulation
#
# This script creates an AKS cluster with NSG egress filtering,
# installs Quix BYOC, verifies the deployment, then tears everything down.
#
# Usage:
#   ./run-airgap-test.sh [options]
#
# Options:
#   --run-id ID          Use specific run ID (default: auto-generated)
#   --skip-destroy       Don't destroy infrastructure on exit (for debugging)
#   --byoc-path PATH     Path to Infrastructure.BYOC repo
#   --help               Show this help
#
# Required Environment Variables:
#   QUIX_ACR_USERNAME    - Username for quixregistry.azurecr.io
#   QUIX_ACR_PASSWORD    - Password for quixregistry.azurecr.io
#   QUIX_ZIP_CLIENT_ID   - Azure AD client ID for BYOC zip storage
#   QUIX_ZIP_CLIENT_SECRET - Azure AD client secret
#   QUIX_ZIP_TENANT_ID   - Azure AD tenant ID
#   QUIX_LICENSE_KEY     - License key for Quix platform
#
# Optional Environment Variables:
#   BYOC_PATH            - Path to Infrastructure.BYOC repo (default: ../../../Infrastructure.BYOC)
#   LOCATION             - Azure region (default: westeurope)
#   KUBERNETES_VERSION   - AKS version (default: 1.30)
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Defaults
RUN_ID=""
SKIP_DESTROY=false
BYOC_PATH="${BYOC_PATH:-}"
LOCATION="${LOCATION:-westeurope}"
KUBERNETES_VERSION="${KUBERNETES_VERSION:-1.33.6}"
INSTALL_TIMEOUT="${INSTALL_TIMEOUT:-1800}" # 30 minutes

# Tracking
TERRAFORM_APPLIED=false
CLUSTER_CONTEXT=""
EXIT_CODE=0

################################################################################
# Logging functions
################################################################################

log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS:${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $*"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $*"
}

log_section() {
    echo ""
    echo -e "${BLUE}================================================================================${NC}"
    echo -e "${BLUE} $*${NC}"
    echo -e "${BLUE}================================================================================${NC}"
    echo ""
}

################################################################################
# Usage
################################################################################

usage() {
    head -40 "$0" | tail -35 | sed 's/^#//' | sed 's/^ //'
    exit 0
}

################################################################################
# Argument parsing
################################################################################

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --run-id)
                RUN_ID="$2"
                shift 2
                ;;
            --skip-destroy)
                SKIP_DESTROY=true
                shift
                ;;
            --byoc-path)
                BYOC_PATH="$2"
                shift 2
                ;;
            --help|-h)
                usage
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                ;;
        esac
    done
}

################################################################################
# Validation
################################################################################

validate_prerequisites() {
    log_section "Validating Prerequisites"

    local missing=()

    # Check required tools
    for cmd in terraform az kubectl jq; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing[*]}"
        exit 1
    fi

    # Check Azure login
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Run 'az login' first."
        exit 1
    fi

    # Check required environment variables
    local required_vars=(
        "QUIX_ACR_USERNAME"
        "QUIX_ACR_PASSWORD"
        "QUIX_ZIP_CLIENT_ID"
        "QUIX_ZIP_CLIENT_SECRET"
        "QUIX_ZIP_TENANT_ID"
        "QUIX_LICENSE_KEY"
    )

    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing+=("$var")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required environment variables: ${missing[*]}"
        exit 1
    fi

    # Resolve BYOC path
    if [[ -z "$BYOC_PATH" ]]; then
        # Try common locations
        for path in \
            "${SCRIPT_DIR}/../../../Infrastructure.BYOC" \
            "${HOME}/code/quix/Infrastructure.BYOC" \
            "../Infrastructure.BYOC"; do
            if [[ -d "$path" && -f "$path/dev.sh" ]]; then
                BYOC_PATH="$(cd "$path" && pwd)"
                break
            fi
        done
    fi

    if [[ -z "$BYOC_PATH" || ! -f "$BYOC_PATH/dev.sh" ]]; then
        log_error "Could not find Infrastructure.BYOC repo. Set BYOC_PATH environment variable."
        exit 1
    fi

    log "BYOC Path: $BYOC_PATH"
    log "Azure Subscription: $(az account show --query name -o tsv)"
    log "Location: $LOCATION"
    log_success "All prerequisites validated"
}

################################################################################
# Cleanup (always runs on exit)
################################################################################

cleanup() {
    local exit_code=$?

    log_section "Cleanup"

    if [[ "$SKIP_DESTROY" == "true" ]]; then
        log_warn "Skipping destroy (--skip-destroy flag set)"
        log "Resources remain in resource group: rg-quix-airgap-${RUN_ID}"
        log "To destroy manually: cd $SCRIPT_DIR && terraform destroy -var run_id=$RUN_ID -auto-approve"
        return
    fi

    if [[ "$TERRAFORM_APPLIED" == "true" ]]; then
        log "Destroying infrastructure..."

        cd "$SCRIPT_DIR"

        # Terraform destroy with retries
        local max_retries=3
        local retry=0

        while [[ $retry -lt $max_retries ]]; do
            if terraform destroy \
                -var "run_id=${RUN_ID}" \
                -var "location=${LOCATION}" \
                -var "kubernetes_version=${KUBERNETES_VERSION}" \
                -auto-approve 2>&1; then
                log_success "Infrastructure destroyed"
                break
            else
                retry=$((retry + 1))
                if [[ $retry -lt $max_retries ]]; then
                    log_warn "Destroy failed, retrying ($retry/$max_retries)..."
                    sleep 30
                else
                    log_error "Failed to destroy infrastructure after $max_retries attempts"
                    log_error "Manual cleanup required: rg-quix-airgap-${RUN_ID}"
                fi
            fi
        done
    else
        log "No infrastructure to destroy"
    fi

    # Remove generated files
    rm -f "$SCRIPT_DIR/byoc-values.yaml" 2>/dev/null || true

    if [[ $exit_code -ne 0 ]]; then
        log_error "Pipeline failed with exit code: $exit_code"
    fi

    exit $exit_code
}

################################################################################
# Generate BYOC values file
################################################################################

generate_byoc_values() {
    log "Generating BYOC values file..."

    local values_file="$SCRIPT_DIR/byoc-values.yaml"
    local template_file="$SCRIPT_DIR/byoc-values.yaml.template"

    if [[ ! -f "$template_file" ]]; then
        log_error "Template file not found: $template_file"
        return 1
    fi

    # Generate values by replacing placeholders
    sed \
        -e "s/CHANGEME_CUSTOMER_NAME/airgap-test-${RUN_ID}/g" \
        -e "s/CHANGEME/${QUIX_ACR_PASSWORD}/g" \
        -e "s/airgap-test-CHANGEME/airgap-test-${RUN_ID}/g" \
        "$template_file" > "$values_file.tmp"

    # Use yq or python to properly set values if available, otherwise sed
    cat "$values_file.tmp" | \
        sed "s|clientId: CHANGEME|clientId: ${QUIX_ZIP_CLIENT_ID}|g" | \
        sed "s|clientSecret: CHANGEME|clientSecret: ${QUIX_ZIP_CLIENT_SECRET}|g" | \
        sed "s|tenantId: CHANGEME|tenantId: ${QUIX_ZIP_TENANT_ID}|g" | \
        sed "s|privateDockerRegistryPassword: CHANGEME|privateDockerRegistryPassword: ${QUIX_ACR_PASSWORD}|g" | \
        sed "s|privateDockerRegistryUsername: CHANGEME|privateDockerRegistryUsername: ${QUIX_ACR_USERNAME}|g" | \
        sed "s|licenseKey: CHANGEME|licenseKey: ${QUIX_LICENSE_KEY}|g" \
        > "$values_file"

    rm -f "$values_file.tmp"

    log_success "Generated: $values_file"
}

################################################################################
# Terraform operations
################################################################################

terraform_init() {
    log "Initializing Terraform..."

    cd "$SCRIPT_DIR"

    terraform init -input=false

    log_success "Terraform initialized"
}

terraform_apply() {
    log_section "Creating Infrastructure"

    cd "$SCRIPT_DIR"

    log "Creating AKS cluster and networking (run_id: $RUN_ID)..."
    log "This typically takes 5-10 minutes..."

    terraform apply \
        -var "run_id=${RUN_ID}" \
        -var "location=${LOCATION}" \
        -var "kubernetes_version=${KUBERNETES_VERSION}" \
        -auto-approve

    TERRAFORM_APPLIED=true

    # Get cluster name
    local cluster_name
    cluster_name=$(terraform output -raw cluster_name 2>/dev/null || echo "aks-airgap-${RUN_ID}")
    local resource_group
    resource_group=$(terraform output -raw resource_group_name 2>/dev/null || echo "rg-quix-airgap-${RUN_ID}")

    log_success "Infrastructure created"
    log "Cluster: $cluster_name"
    log "Resource Group: $resource_group"
}

################################################################################
# Kubernetes operations
################################################################################

get_credentials() {
    log "Getting AKS credentials..."

    local cluster_name="aks-airgap-${RUN_ID}"
    local resource_group="rg-quix-airgap-${RUN_ID}"

    az aks get-credentials \
        --resource-group "$resource_group" \
        --name "$cluster_name" \
        --overwrite-existing

    CLUSTER_CONTEXT="$cluster_name"

    # Verify connectivity
    if ! kubectl --context="$CLUSTER_CONTEXT" get nodes &> /dev/null; then
        log_error "Cannot connect to cluster"
        return 1
    fi

    log_success "Connected to cluster: $CLUSTER_CONTEXT"
    kubectl --context="$CLUSTER_CONTEXT" get nodes
}

create_namespace() {
    log "Creating quix namespace..."

    kubectl --context="$CLUSTER_CONTEXT" create namespace quix --dry-run=client -o yaml | \
        kubectl --context="$CLUSTER_CONTEXT" apply -f -

    log_success "Namespace created"
}

wait_for_nodes() {
    log "Waiting for all nodes to be Ready..."

    local timeout=300
    local start_time=$(date +%s)

    while true; do
        local not_ready
        not_ready=$(kubectl --context="$CLUSTER_CONTEXT" get nodes --no-headers 2>/dev/null | grep -cv " Ready " || echo "0")

        if [[ "$not_ready" -eq 0 ]]; then
            log_success "All nodes are Ready"
            kubectl --context="$CLUSTER_CONTEXT" get nodes
            return 0
        fi

        local elapsed=$(($(date +%s) - start_time))
        if [[ $elapsed -gt $timeout ]]; then
            log_error "Timeout waiting for nodes to be Ready"
            kubectl --context="$CLUSTER_CONTEXT" get nodes
            return 1
        fi

        log "Waiting for $not_ready node(s) to be Ready... (${elapsed}s/${timeout}s)"
        sleep 10
    done
}

################################################################################
# BYOC Installation
################################################################################

install_byoc() {
    log_section "Installing Quix BYOC"

    cd "$BYOC_PATH"

    local values_file="$SCRIPT_DIR/byoc-values.yaml"

    log "Running BYOC installer..."
    log "This typically takes 10-15 minutes..."

    # Run install with timeout
    if timeout "$INSTALL_TIMEOUT" ./dev.sh install \
        -f "$values_file" \
        --context "$CLUSTER_CONTEXT" 2>&1; then
        log_success "BYOC installation completed"
    else
        log_error "BYOC installation failed or timed out"
        return 1
    fi
}

################################################################################
# Verification
################################################################################

verify_deployment() {
    log_section "Verifying Deployment"

    local timeout=300
    local start_time=$(date +%s)

    log "Waiting for pods to be Running..."

    while true; do
        # Count non-running pods (excluding Completed jobs)
        local not_running
        not_running=$(kubectl --context="$CLUSTER_CONTEXT" get pods -n quix --no-headers 2>/dev/null | \
            grep -v Running | grep -v Completed | wc -l || echo "999")

        if [[ "$not_running" -eq 0 ]]; then
            log_success "All pods are Running"
            break
        fi

        local elapsed=$(($(date +%s) - start_time))
        if [[ $elapsed -gt $timeout ]]; then
            log_warn "Timeout waiting for all pods. Checking status..."
            break
        fi

        log "Waiting for $not_running pod(s) to be Running... (${elapsed}s/${timeout}s)"
        sleep 15
    done

    # Show final pod status
    echo ""
    log "Pod Status:"
    kubectl --context="$CLUSTER_CONTEXT" get pods -n quix

    # Check for critical failures
    local failed_pods
    failed_pods=$(kubectl --context="$CLUSTER_CONTEXT" get pods -n quix --no-headers 2>/dev/null | \
        grep -E "(CrashLoopBackOff|ImagePullBackOff|Error)" | wc -l || echo "0")

    if [[ "$failed_pods" -gt 0 ]]; then
        log_error "Found $failed_pods pod(s) in failed state"
        kubectl --context="$CLUSTER_CONTEXT" get pods -n quix | grep -E "(CrashLoopBackOff|ImagePullBackOff|Error)"
        return 1
    fi

    # Check workspace-service specifically (critical for airgap validation)
    local ws_running
    ws_running=$(kubectl --context="$CLUSTER_CONTEXT" get pods -n quix -l app=workspace-service --no-headers 2>/dev/null | \
        grep Running | wc -l || echo "0")

    if [[ "$ws_running" -lt 1 ]]; then
        log_error "workspace-service is not running - airgap validation failed"
        kubectl --context="$CLUSTER_CONTEXT" logs -l app=workspace-service -n quix --tail=50 2>/dev/null || true
        return 1
    fi

    log_success "Airgap deployment verified successfully"

    # Summary
    echo ""
    log "Deployment Summary:"
    kubectl --context="$CLUSTER_CONTEXT" get pods -n quix --no-headers | \
        awk '{print $3}' | sort | uniq -c | while read count status; do
            echo "  $status: $count"
        done

    return 0
}

################################################################################
# Main
################################################################################

main() {
    parse_args "$@"

    # Generate run ID if not provided
    if [[ -z "$RUN_ID" ]]; then
        RUN_ID="$(date +%m%d%H%M)"
    fi

    log_section "Airgap Test Pipeline"
    log "Run ID: $RUN_ID"
    log "Start Time: $(date)"

    # Set up cleanup trap
    trap cleanup EXIT

    # Run pipeline stages
    validate_prerequisites
    terraform_init
    terraform_apply
    get_credentials
    wait_for_nodes
    create_namespace
    generate_byoc_values
    install_byoc
    verify_deployment

    log_section "Pipeline Complete"
    log_success "Airgap test passed successfully"
    log "Total Time: $SECONDS seconds"

    EXIT_CODE=0
}

main "$@"
