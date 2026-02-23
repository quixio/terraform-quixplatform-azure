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
INSTALL_TIMEOUT="${INSTALL_TIMEOUT:-3600}" # 60 minutes

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
    for cmd in terraform az kubectl jq curl; do
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
# Registry Pre-check (fail fast before provisioning infrastructure)
################################################################################

# Container images that must exist in the registry.
REQUIRED_IMAGES=(
    "quixplatform-ansible-builder"
    "workspace-service"
    "deployments-service"
    "portal-api"
    "portalui"
    "admin-ui"
    "jetstack/cert-manager-controller"
    "jetstack/cert-manager-webhook"
    "jetstack/cert-manager-cainjector"
    "traefik/traefik"
    "bitnami/mongodb"
    "strimzi/operator"
    "strimzi/quix-kafka"
    "grafana/grafana"
    "prometheus/prometheus"
    "grafana/loki"
    "bitnami/minio"
)

# Infrastructure chart -> version mappings. Each entry:
#   chart_repo|relative_path_to_versions_yaml|grep_pattern_for_version
# The version is extracted from BYOC role files so we check exact tags, not just
# repo existence. This catches version drift (new release not yet mirrored).
CHART_VERSION_SOURCES=(
    "helm/pod-status-watcher-service|roles/pod_status_watcher/tasks/versions.yaml|pod_status_watcher_version"
    "helm/jetstack/cert-manager|roles/cert_manager/tasks/versions.yaml|cert_manager_chart_version"
    "helm/traefik/traefik|roles/ingress/tasks/versions.yaml|traefik_ingress_chart_version"
    "helm/bitnami/mongodb|roles/mongo/tasks/versions.yaml|mongodb_chart_version"
    "helm/strimzi/strimzi-kafka-operator|roles/kafka_operator/tasks/versions.yaml|kafka_operator_chart_version"
    "helm/prometheus-community/kube-prometheus-stack|roles/monitoring/tasks/versions.yaml|prometheus_chart_version"
    "helm/grafana/loki|roles/logging/tasks/versions.yaml|loki_version"
    "helm/bitnami/minio|roles/logging/tasks/versions.yaml|minio_version"
    "helm/gitea/gitea|roles/gitea/tasks/versions.yaml|gitea_chart_version"
    "helm/annotation-transmuter-webhook|roles/annotation_transmuter_webhook/tasks/versions.yaml|annotation_transmuter_webhook_version"
)

# Charts where we only check repo existence (version comes from dynamic config
# or container_versions.yaml and is harder to extract statically).
REQUIRED_CHARTS=(
    "helm/quixplatform-manager"
    "helm/workspace-service"
    "helm/deployments-service"
    "helm/portal-api"
    "helm/portal"
    "helm/admin-ui"
    "helm/streaming-reader"
    "helm/git-api"
    "helm/quix-environment-operator"
    "helm/container-cache"
    "helm/keycloak"
)

# Extract a version string from a BYOC Ansible versions.yaml file.
# Looks for patterns like: variable_name: "1.2.3" or variable_name: 1.2.3
extract_byoc_version() {
    local file="$1"
    local var_name="$2"
    if [[ ! -f "$file" ]]; then
        echo ""
        return
    fi
    # Match: var_name: "version" or var_name: version (no Jinja templates)
    local version
    version=$(grep -E "^\s+${var_name}:\s+" "$file" 2>/dev/null \
        | grep -v '{{' \
        | head -1 \
        | sed -E 's/^[[:space:]]*[^:]+:[[:space:]]*"?([^"[:space:]]+)"?.*/\1/')
    echo "$version"
}

precheck_registry() {
    log_section "Pre-check: Validating Registry"

    local acr_registry="quixregistry.azurecr.io"
    local passed=0
    local failed=0
    local missing_items=()

    # Verify Azure CLI can access the registry
    log "Verifying access to ${acr_registry}..."
    if ! az acr repository list --name "${acr_registry%%.*}" --output tsv &>/dev/null; then
        log_error "Cannot access ${acr_registry} - check Azure CLI login and permissions"
        return 1
    fi
    log "Registry access verified"

    local acr_name="${acr_registry%%.*}"

    # Check helper: verify a repository has at least one tag
    check_repo_exists() {
        local repo="$1"
        local tag_count
        tag_count=$(az acr repository show-tags --name "$acr_name" --repository "$repo" --output tsv 2>/dev/null | wc -l)

        if [[ "$tag_count" -gt 0 ]]; then
            log "  ${GREEN}[OK]${NC} $repo ($tag_count tags)"
            passed=$((passed + 1))
            return 0
        else
            log "  ${RED}[MISSING]${NC} $repo"
            failed=$((failed + 1))
            missing_items+=("$repo")
            return 1
        fi
    }

    # Check helper: verify a specific tag exists in a repository
    check_chart_version() {
        local repo="$1"
        local version="$2"
        local tags
        tags=$(az acr repository show-tags --name "$acr_name" --repository "$repo" --output tsv 2>/dev/null)

        if echo "$tags" | grep -qx "$version"; then
            log "  ${GREEN}[OK]${NC} $repo:$version"
            passed=$((passed + 1))
            return 0
        elif [[ -z "$tags" ]]; then
            log "  ${RED}[MISSING]${NC} $repo (repo not found)"
            failed=$((failed + 1))
            missing_items+=("$repo (repo missing)")
            return 1
        else
            local latest
            latest=$(echo "$tags" | sort -V | tail -1)
            log "  ${RED}[MISSING]${NC} $repo:$version (latest: $latest)"
            failed=$((failed + 1))
            missing_items+=("$repo:$version (latest in registry: $latest)")
            return 1
        fi
    }

    # --- Version-specific checks (infrastructure charts) ---
    log "Checking infrastructure chart versions (from BYOC role files)..."
    for entry in "${CHART_VERSION_SOURCES[@]}"; do
        IFS='|' read -r chart_repo version_file var_name <<< "$entry"
        local full_path="${BYOC_PATH}/${version_file}"
        local version
        version=$(extract_byoc_version "$full_path" "$var_name")

        if [[ -z "$version" ]]; then
            log "  ${YELLOW}[SKIP]${NC} $chart_repo (could not extract version from $version_file)"
            continue
        fi

        check_chart_version "$chart_repo" "$version" || true
    done

    # --- Repo existence checks (platform charts) ---
    echo ""
    log "Checking platform charts (repo existence)..."
    for chart in "${REQUIRED_CHARTS[@]}"; do
        check_repo_exists "$chart" || true
    done

    # --- Container images ---
    echo ""
    log "Checking container images..."
    for image in "${REQUIRED_IMAGES[@]}"; do
        check_repo_exists "$image" || true
    done

    # Summary
    echo ""
    log "Registry check: ${passed} passed, ${failed} failed"

    if [[ ${#missing_items[@]} -gt 0 ]]; then
        log_error "Missing artifacts in ${acr_registry}:"
        for item in "${missing_items[@]}"; do
            echo "  - $item"
        done
        log_error "These must be mirrored to the registry before deployment."
        return 1
    fi

    log_success "All required artifacts present in registry"
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

    # Generate values by replacing placeholders.
    # Each CHANGEME must be replaced with the correct value for its field.
    # Order matters: specific patterns first to avoid blanket replacement.
    sed \
        -e "s|customerName: airgap-test-CHANGEME|customerName: airgap-test-${RUN_ID}|g" \
        -e "s|clientId: CHANGEME|clientId: ${QUIX_ZIP_CLIENT_ID}|g" \
        -e "s|clientSecret: CHANGEME|clientSecret: ${QUIX_ZIP_CLIENT_SECRET}|g" \
        -e "s|tenantId: CHANGEME|tenantId: ${QUIX_ZIP_TENANT_ID}|g" \
        -e "s|privateDockerRegistryUsername: CHANGEME|privateDockerRegistryUsername: ${QUIX_ACR_USERNAME}|g" \
        -e "s|privateDockerRegistryPassword: CHANGEME|privateDockerRegistryPassword: ${QUIX_ACR_PASSWORD}|g" \
        -e "s|licenseKey: CHANGEME|licenseKey: ${QUIX_LICENSE_KEY}|g" \
        "$template_file" > "$values_file"

    log_success "Generated: $values_file"
}

################################################################################
# Terraform operations
################################################################################

terraform_init() {
    log "Initializing Terraform..."

    cd "$SCRIPT_DIR"

    # In CI/CD, backend config is passed via TF_CLI_ARGS_init or -backend-config.
    # For local runs, override the azurerm backend with local state.
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
        # Note: grep -c returns exit code 1 when count is 0, so we suppress with || true
        not_ready=$(kubectl --context="$CLUSTER_CONTEXT" get nodes --no-headers 2>/dev/null | grep -cv " Ready " || true)
        not_ready=$(echo "$not_ready" | tr -d '[:space:]')
        not_ready=${not_ready:-0}

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

    # Clean up any stale helm releases (e.g., from a previous --skip-destroy run)
    # pending-install/pending-upgrade states block new installs
    local stale_releases
    stale_releases=$(helm list -n quix --kube-context "$CLUSTER_CONTEXT" -a --filter 'quixplatform' -q 2>/dev/null || true)
    if [[ -n "$stale_releases" ]]; then
        log "Cleaning up stale helm releases..."
        for release in $stale_releases; do
            log "  Uninstalling stale release: $release"
            helm uninstall "$release" -n quix --kube-context "$CLUSTER_CONTEXT" --wait 2>/dev/null || true
        done
        log_success "Stale releases cleaned up"
    fi

    # Pre-authenticate helm to the ACR. dev.sh tries az acr login which
    # doesn't work with service principals (no docker daemon). Use helm
    # registry login with the credentials from the variable group instead.
    log "Authenticating helm to quixregistry.azurecr.io..."
    echo "$QUIX_ACR_PASSWORD" | helm registry login quixregistry.azurecr.io \
        --username "$QUIX_ACR_USERNAME" --password-stdin
    log_success "Helm authenticated to ACR"

    log "Running BYOC installer..."
    log "This typically takes 10-15 minutes..."

    # Override chart registry: dev.sh defaults to quixcontainerregistry but
    # airgap charts are mirrored to quixregistry
    export QUIX_CHART_REGISTRY="quixregistry.azurecr.io"

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

    local healthcheck="$SCRIPT_DIR/scripts/healthcheck.sh"

    if [[ ! -x "$healthcheck" ]]; then
        log_error "healthcheck.sh not found at: $healthcheck"
        return 1
    fi

    # Run the comprehensive health checker
    local exit_code=0
    "$healthcheck" --verbose || exit_code=$?

    # Exit code mapping:
    #   0 = all checks passed
    #   1 = critical failure (registry/infra)
    #   2 = platform issues (services unhealthy)
    #   3 = warnings only (non-critical)
    case $exit_code in
        0)
            log_success "All health checks passed"
            ;;
        3)
            log_warn "Health checks passed with warnings (non-critical)"
            ;;
        *)
            log_error "Health checks failed (exit code: $exit_code)"
            return 1
            ;;
    esac

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
    precheck_registry
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
