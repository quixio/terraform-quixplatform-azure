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
#   QUIX_ACR_USERNAME    - Username for the container registry
#   QUIX_ACR_PASSWORD    - Password for the container registry
#   QUIX_LICENSE_KEY     - License key for Quix platform
#   ACR_REGISTRY         - Container registry hostname (e.g., myregistry.azurecr.io)
#   ACR_ID               - Full Azure resource ID of the ACR (for Terraform AcrPull role assignment)
#
# Optional Environment Variables:
#   INSTALLER_TAG        - Airgap installer image tag (default: 1.6.7-0.1.20260217631-airgap)
#   BYOC_PATH            - Path to Infrastructure.BYOC repo (default: ../../../Infrastructure.BYOC)
#   LOCATION             - Azure region (default: westeurope)
#   KUBERNETES_VERSION   - AKS version (default: 1.33.6)
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
INSTALLER_TAG="${INSTALLER_TAG:-1.6.7-airgap-20260227.1}"
BYOCVERSIONS_DIR="${BYOCVERSIONS_DIR:-}"
ACR_REGISTRY="${ACR_REGISTRY:-}"
ACR_ID="${ACR_ID:-}"

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
    # ACR creds and license are always required.
    # ZIP creds are NOT needed - the airgap installer has everything baked in.
    local required_vars=(
        "QUIX_ACR_USERNAME"
        "QUIX_ACR_PASSWORD"
        "QUIX_LICENSE_KEY"
        "ACR_REGISTRY"
        "ACR_ID"
        "AUTH0_CLIENT_ID"
        "AUTH0_CLIENT_SECRET"
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

# Infrastructure images (repo existence only - versions come from BYOC roles).
# Platform images (workspace-service, portal-api, etc.) are checked with exact
# tags via PLATFORM_IMAGE_VERSIONS above.
REQUIRED_IMAGES=(
    "quixplatform-ansible-builder"
    "jetstack/cert-manager-controller"
    "jetstack/cert-manager-webhook"
    "jetstack/cert-manager-cainjector"
    "jetstack/trust-manager"
    "jetstack/cert-manager-package-debian"
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
    "helm/jetstack/trust-manager|roles/custom_certificate_authority/tasks/versions.yaml|trust_manager_chart_version"
)

# Platform image -> version mappings. Each entry:
#   component_key_in_container_versions|image_name_in_registry
# Tags are extracted from container_versions.yaml (sourced from BYOCVersions).
# The image names come from the "service" field in platform_values.yaml.j2.
PLATFORM_IMAGE_VERSIONS=(
    "users|authapi"
    "users|userservice"
    "build|buildservice"
    "deployments|deployments-ide-api"
    "deployments|deployments-logs-api"
    "deployments|deployments-service"
    "deployments|deployments-metrics-signalr"
    "deployments|deployments-monitoring-service"
    "git|git-api"
    "git|git-tester-api"
    "notifications|notifications-api"
    "portal_frontend|portalui"
    "portal_backend|portal-api"
    "portal_backend|portal-api-notifications"
    "portal_backend|portal-library-api"
    "admin_ui|admin-ui"
    "datalake_api|datalake-tester-api"
    "workspace|workspace-service"
    "telemetry_client|telemetry-client"
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

################################################################################
# Extract container_versions.yaml from the fat installer image
#
# The file is gitignored in Infrastructure.BYOC (synced at runtime from
# BYOCVersions). But the fat installer has it baked in. We thin-pull it
# using crane so precheck_registry can verify platform image tags match
# what's actually in the registry.
################################################################################

extract_container_versions() {
    log "Extracting container_versions.yaml from installer image..."

    local image="${ACR_REGISTRY}/quixplatform-ansible-builder:${INSTALLER_TAG}"
    local versions_dir
    versions_dir=$(mktemp -d)

    # Authenticate crane to ACR (non-fatal - extraction is best-effort)
    if ! echo "$QUIX_ACR_PASSWORD" | crane auth login "$ACR_REGISTRY" \
        --username "$QUIX_ACR_USERNAME" --password-stdin 2>/dev/null; then
        log_warn "Could not authenticate crane to registry"
        log_warn "Platform image version checks will be skipped"
        return 0
    fi

    # Extract just container_versions.yaml from the flattened image filesystem.
    # crane export streams the image as a tar; we pass the exact path as a
    # positional argument to tar (GNU tar on Mariner - no --include flag).
    local target_path="app/ansible/assets/versions/container_versions.yaml"
    log "  Image: $image"
    log "  Target: $target_path"

    local crane_err
    crane_err=$(mktemp)
    if crane export "$image" - 2>"$crane_err" \
        | tar xf - -C "$versions_dir" "$target_path" 2>/dev/null; then

        local extracted="$versions_dir/$target_path"
        if [[ -f "$extracted" ]]; then
            BYOCVERSIONS_DIR="$versions_dir/app/ansible/assets/versions"
            export BYOCVERSIONS_DIR
            log_success "Extracted container_versions.yaml"
            rm -f "$crane_err"
            return 0
        fi
    fi

    # Log why it failed
    if [[ -s "$crane_err" ]]; then
        log_warn "crane export error: $(head -3 "$crane_err")"
    fi
    rm -f "$crane_err"

    log_warn "Could not extract container_versions.yaml from installer image"
    log_warn "Platform image version checks will be skipped"
}

precheck_registry() {
    log_section "Pre-check: Validating Registry"

    local acr_registry="$ACR_REGISTRY"
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

    # --- Platform image version checks (from container_versions.yaml) ---
    # These are non-fatal: the fat installer has versions baked in that may
    # differ from what container_versions.yaml reports. Missing platform
    # images are logged as warnings, not errors.
    local cv_file=""
    if [[ -n "$BYOCVERSIONS_DIR" && -f "$BYOCVERSIONS_DIR/container_versions.yaml" ]]; then
        cv_file="$BYOCVERSIONS_DIR/container_versions.yaml"
    elif [[ -f "$BYOC_PATH/assets/versions/container_versions.yaml" ]]; then
        cv_file="$BYOC_PATH/assets/versions/container_versions.yaml"
    fi

    if [[ -n "$cv_file" ]]; then
        echo ""
        log "Checking platform image versions (from container_versions.yaml)..."
        local prev_component="" prev_tag=""
        local platform_warnings=()

        for entry in "${PLATFORM_IMAGE_VERSIONS[@]}"; do
            IFS='|' read -r component image_name <<< "$entry"

            # Cache tag extraction per component (many images share one tag)
            if [[ "$component" != "$prev_component" ]]; then
                prev_component="$component"
                prev_tag=$(yq ".platform_container_versions.${component}.imagetag" "$cv_file" 2>/dev/null || echo "")
            fi

            if [[ -z "$prev_tag" || "$prev_tag" == "null" ]]; then
                log "  ${YELLOW}[SKIP]${NC} $image_name (no tag for component '$component')"
                continue
            fi

            # Check version but track separately (non-fatal)
            local tags
            tags=$(az acr repository show-tags --name "$acr_name" --repository "$image_name" --output tsv 2>/dev/null)
            if echo "$tags" | grep -qx "$prev_tag"; then
                log "  ${GREEN}[OK]${NC} $image_name:$prev_tag"
                passed=$((passed + 1))
            elif [[ -z "$tags" ]]; then
                log "  ${YELLOW}[WARN]${NC} $image_name (repo not found)"
                platform_warnings+=("$image_name (repo missing)")
            else
                local latest
                latest=$(echo "$tags" | sort -V | tail -1)
                log "  ${YELLOW}[WARN]${NC} $image_name:$prev_tag (latest: $latest)"
                platform_warnings+=("$image_name:$prev_tag (latest in registry: $latest)")
            fi
        done

        if [[ ${#platform_warnings[@]} -gt 0 ]]; then
            log_warn "Platform image version mismatches (non-fatal):"
            for item in "${platform_warnings[@]}"; do
                echo "  - $item"
            done
            log_warn "The fat installer may use different versions - install can still succeed."
        fi
    else
        log_warn "container_versions.yaml not found - skipping platform image version checks"
    fi

    # --- Repo existence checks (platform charts) ---
    echo ""
    log "Checking platform charts (repo existence)..."
    for chart in "${REQUIRED_CHARTS[@]}"; do
        check_repo_exists "$chart" || true
    done

    # --- Container images (infrastructure - repo existence only) ---
    echo ""
    log "Checking infrastructure images..."
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
        log "To destroy manually: cd $SCRIPT_DIR && terraform destroy -var run_id=$RUN_ID -var acr_id=\$ACR_ID -auto-approve"
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
                -input=false \
                -var "run_id=${RUN_ID}" \
                -var "location=${LOCATION}" \
                -var "kubernetes_version=${KUBERNETES_VERSION}" \
                -var "acr_id=${ACR_ID}" \
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
    [[ -n "${BYOCVERSIONS_DIR:-}" ]] && rm -rf "${BYOCVERSIONS_DIR%/app/ansible/assets/versions}" 2>/dev/null || true

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

    # Generate a self-signed wildcard TLS certificate for the test domain.
    # These are injected as base64-encoded Helm values (fullchainPemBase64,
    # privkeyPemBase64) which flow through the cert_secrets.yaml pre-install
    # hook -> agent-certificates secret -> mounted into installer pod ->
    # ingress role reads files and creates the wildcard TLS secret.
    local cert_dir
    cert_dir=$(mktemp -d)
    local domain="airgap-test.internal"

    log "Generating self-signed TLS certificate for *.${domain}..."
    openssl req -x509 -newkey rsa:2048 -nodes \
        -keyout "$cert_dir/privkey.pem" \
        -out "$cert_dir/fullchain.pem" \
        -days 30 \
        -subj "/CN=*.${domain}/O=Quix Airgap Test" \
        -addext "subjectAltName=DNS:*.${domain},DNS:${domain}" 2>/dev/null

    local fullchain_b64 privkey_b64 customca_b64
    fullchain_b64=$(base64 < "$cert_dir/fullchain.pem" | tr -d '\n')
    privkey_b64=$(base64 < "$cert_dir/privkey.pem" | tr -d '\n')
    # Self-signed cert is its own CA - the custom_certificate_authority role
    # needs a valid customca.crt to install trust-manager and distribute the CA.
    customca_b64="$fullchain_b64"
    rm -rf "$cert_dir"

    # Generate values by replacing placeholders.
    # The airgap installer has BYOC files baked in, so no zip credentials needed.
    sed \
        -e "s|customerName: airgap-test-CHANGEME|customerName: airgap-test-${RUN_ID}|g" \
        -e "s|tag: INSTALLER_TAG|tag: ${INSTALLER_TAG}|g" \
        -e "s|privateDockerRegistryUsername: CHANGEME|privateDockerRegistryUsername: ${QUIX_ACR_USERNAME}|g" \
        -e "s|privateDockerRegistryPassword: CHANGEME|privateDockerRegistryPassword: ${QUIX_ACR_PASSWORD}|g" \
        -e "s|licenseKey: CHANGEME|licenseKey: ${QUIX_LICENSE_KEY}|g" \
        -e "s|ACR_REGISTRY|${ACR_REGISTRY}|g" \
        -e "s|clientId: CHANGEME_AUTH0_CLIENT_ID|clientId: ${AUTH0_CLIENT_ID}|g" \
        -e "s|clientSecret: CHANGEME_AUTH0_CLIENT_SECRET|clientSecret: ${AUTH0_CLIENT_SECRET}|g" \
        -e "s|fullchainPemBase64: GENERATE_AT_RUNTIME|fullchainPemBase64: ${fullchain_b64}|g" \
        -e "s|privkeyPemBase64: GENERATE_AT_RUNTIME|privkeyPemBase64: ${privkey_b64}|g" \
        -e "s|customCaPemBase64: GENERATE_AT_RUNTIME|customCaPemBase64: ${customca_b64}|g" \
        "$template_file" > "$values_file"

    log "Installer image: ${ACR_REGISTRY}/quixplatform-ansible-builder:${INSTALLER_TAG}"
    log_success "TLS certificate for *.${domain} injected into values"

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
        -input=false \
        -var "run_id=${RUN_ID}" \
        -var "location=${LOCATION}" \
        -var "kubernetes_version=${KUBERNETES_VERSION}" \
        -var "acr_id=${ACR_ID}" \
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

    # Use --admin to get kubeconfig with client certificates (long-lived).
    # Without --admin, az CLI may embed a short-lived bearer token that
    # expires mid-install, killing helm's connection to the API server.
    az aks get-credentials \
        --resource-group "$resource_group" \
        --name "$cluster_name" \
        --overwrite-existing \
        --admin

    # --admin appends "-admin" to the context name
    CLUSTER_CONTEXT="${cluster_name}-admin"

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
    log "Authenticating helm to ${ACR_REGISTRY}..."
    echo "$QUIX_ACR_PASSWORD" | helm registry login "$ACR_REGISTRY" \
        --username "$QUIX_ACR_USERNAME" --password-stdin
    log_success "Helm authenticated to ACR"

    log "Running BYOC installer..."
    log "This typically takes 10-15 minutes..."

    # Override chart registry: dev.sh defaults to quixcontainerregistry but
    # airgap charts are mirrored to the release registry
    export QUIX_CHART_REGISTRY="$ACR_REGISTRY"

    # Compute effective timeout: the lesser of INSTALL_TIMEOUT and remaining
    # budget before job deadline (minus 5 min buffer for post-install steps).
    local remaining_budget=$(( JOB_DEADLINE_EPOCH - $(date +%s) - 300 ))
    local effective_timeout=$INSTALL_TIMEOUT
    if [[ $remaining_budget -lt $effective_timeout ]]; then
        effective_timeout=$remaining_budget
    fi
    if [[ $effective_timeout -le 0 ]]; then
        log_error "No time budget remaining for install (deadline exceeded)"
        return 1
    fi
    log "Install timeout: ${effective_timeout}s (budget: ${remaining_budget}s, configured: ${INSTALL_TIMEOUT}s)"

    # Run install. dev.sh backgrounds helm and streams pod logs, but the log
    # stream can disconnect in long-running installs (e.g. monitoring takes 12+
    # minutes). If dev.sh exits non-zero, fall back to polling the installer
    # Job directly - the pod inside the cluster keeps running regardless.
    local dev_exit=0
    # --no-local-files: skip the dev convenience of pre-downloading charts
    # to a PVC. Instead, the installer pod pulls charts directly from the
    # registry using registrypullsecret - same path as a real customer.
    # --no-sync-versions: the fat installer has all BYOCVersions baked in,
    # don't try to sync from an external BYOCVersions directory.
    timeout "$effective_timeout" ./dev.sh install \
        -f "$values_file" \
        --context "$CLUSTER_CONTEXT" \
        --no-local-files \
        --no-sync-versions 2>&1 || dev_exit=$?

    if [[ $dev_exit -eq 0 ]]; then
        log_success "BYOC installation completed"
        return 0
    fi

    log_warn "dev.sh exited with code $dev_exit - checking installer job status..."
    wait_for_installer_job
}

################################################################################
# Wait for installer job (fallback when dev.sh log stream breaks)
################################################################################

wait_for_installer_job() {
    local job_name="quixplatform-manager-job"
    local namespace="quix"
    # Use deadline with 5 min buffer for post-install steps
    local deadline=$(( JOB_DEADLINE_EPOCH - 300 ))

    # Check if the job even exists
    if ! kubectl --context="$CLUSTER_CONTEXT" get job "$job_name" -n "$namespace" &>/dev/null; then
        log_error "Installer job not found - install likely failed before job creation"
        return 1
    fi

    # Find the pod for this job
    local pod_name
    pod_name=$(kubectl --context="$CLUSTER_CONTEXT" get pods -n "$namespace" \
        -l job-name="$job_name" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    log "Following installer job logs (dev.sh lost connection, reconnecting directly)..."

    # Stream pod logs in background so we can also check job status
    if [[ -n "$pod_name" ]]; then
        # Get logs from where dev.sh left off (--since covers the gap)
        kubectl --context="$CLUSTER_CONTEXT" logs "$pod_name" -n "$namespace" \
            --follow --since=20m 2>/dev/null &
        local logs_pid=$!
    fi

    # Poll for job completion while logs stream (deadline-based)
    while [[ $(date +%s) -lt $deadline ]]; do
        local status
        status=$(kubectl --context="$CLUSTER_CONTEXT" get job "$job_name" -n "$namespace" \
            -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null || echo "")
        local failed
        failed=$(kubectl --context="$CLUSTER_CONTEXT" get job "$job_name" -n "$namespace" \
            -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}' 2>/dev/null || echo "")

        if [[ "$status" == "True" ]]; then
            kill "$logs_pid" 2>/dev/null || true; wait "$logs_pid" 2>/dev/null || true
            log_success "Installer job completed successfully"
            return 0
        fi

        if [[ "$failed" == "True" ]]; then
            kill "$logs_pid" 2>/dev/null || true; wait "$logs_pid" 2>/dev/null || true
            log_error "Installer job failed"
            kubectl --context="$CLUSTER_CONTEXT" logs "job/$job_name" -n "$namespace" --tail=50 2>/dev/null || true
            return 1
        fi

        sleep 15
    done

    kill "$logs_pid" 2>/dev/null || true; wait "$logs_pid" 2>/dev/null || true
    log_error "Installer job did not complete before deadline ($(date -d @$JOB_DEADLINE_EPOCH 2>/dev/null || date -r $JOB_DEADLINE_EPOCH))"
    return 1
}

################################################################################
# Post-install network lockdown
#
# During bootstrap and install, the NSG allows broad Azure service access
# (MCR, AzureCloud global, etc.). After install completes, tighten the
# rules to only what the running platform actually needs:
#   - ACR francecentral (release registry)
#   - Storage francecentral (ACR blob backend)
#   - AKS control plane (regional)
#   - DNS, NTP, AAD, VNet internal
#
# Auth0 is the one accepted external dependency - customers who choose
# Auth0 over Keycloak are informed about this outbound requirement.
#
# This proves the platform operates in a genuine airgap - no hidden
# dependencies on MCR, Docker Hub, or broad Azure IP ranges.
################################################################################

lockdown_network() {
    log_section "Post-Install Network Lockdown"

    local nsg_name="nsg-aks-airgap-${RUN_ID}"
    local rg_name="rg-quix-airgap-${RUN_ID}"

    log "Tightening NSG rules to minimum post-install set..."

    # Rules to remove: broad access only needed during bootstrap/install
    local rules_to_remove=(
        "AllowAzureCloud"          # Global Azure Cloud - replace with regional
        "AllowMCR"                 # MCR service tag - system images already cached
        "AllowMCR-CDN"             # 20.0.0.0/8 + Akamai - the biggest hole
        "AllowACR-WestEurope"      # Release ACR is in francecentral, not here
        "AllowStorage-WestEurope"  # Only needed during bootstrap
    )

    for rule in "${rules_to_remove[@]}"; do
        log "  Removing: $rule"
        az network nsg rule delete \
            --resource-group "$rg_name" \
            --nsg-name "$nsg_name" \
            --name "$rule" \
            --output none 2>/dev/null || log_warn "  Rule $rule not found (already removed?)"
    done

    # Brief pause for ARM to process the deletions before creating new rules
    sleep 5

    # Add regional AzureCloud rule to replace the global one.
    # AKS control plane needs HTTPS to the regional Azure management plane.
    # Uses priority 201 to avoid ARM race with the just-deleted priority 200.
    log "  Adding: AllowAzureCloud-Regional (${LOCATION} only)"
    if ! az network nsg rule create \
        --resource-group "$rg_name" \
        --nsg-name "$nsg_name" \
        --name "AllowAzureCloud-Regional" \
        --priority 201 \
        --direction Outbound \
        --access Allow \
        --protocol Tcp \
        --source-address-prefixes '*' \
        --source-port-ranges '*' \
        --destination-address-prefixes "AzureCloud.${LOCATION}" \
        --destination-port-ranges 443 \
        --output none 2>&1; then
        log_error "Failed to create regional AzureCloud rule"
        return 1
    fi

    # Allow outbound HTTPS to Auth0 tenant. Auth0 uses dynamic IPs behind
    # CDN, so resolve at runtime. Customers using Auth0 accept this outbound
    # dependency as a known requirement.
    local auth0_host="quix-byoc.eu.auth0.com"
    local auth0_ips
    # Use getent (glibc, always available) instead of dig (bind-utils, not in container)
    auth0_ips=$(getent ahosts "$auth0_host" 2>/dev/null | awk '{print $1}' | grep -E '^[0-9]+\.' | sort -u | tr '\n' ' ' || true)

    if [[ -n "$auth0_ips" ]]; then
        log "  Adding: AllowAuth0 (${auth0_host} -> ${auth0_ips})"
        az network nsg rule create \
            --resource-group "$rg_name" \
            --nsg-name "$nsg_name" \
            --name "AllowAuth0" \
            --priority 202 \
            --direction Outbound \
            --access Allow \
            --protocol Tcp \
            --source-address-prefixes '*' \
            --source-port-ranges '*' \
            --destination-address-prefixes $auth0_ips \
            --destination-port-ranges 443 \
            --output none 2>&1 || log_warn "Failed to create Auth0 NSG rule"
    else
        log_warn "Could not resolve ${auth0_host} - Auth0 outbound rule not created"
    fi

    # Log the final rule set
    log "Final NSG rules:"
    az network nsg rule list \
        --resource-group "$rg_name" \
        --nsg-name "$nsg_name" \
        --query "[?direction=='Outbound'].{priority:priority, name:name, access:access, dest:destinationAddressPrefix}" \
        --output table

    log_success "Network locked down to minimum airgap rules"

    # --- Negative test: prove external registries are blocked ---
    log "Running negative airgap test (docker.io pull must fail)..."

    # Create a pod that tries to pull from Docker Hub
    kubectl --context="$CLUSTER_CONTEXT" run airgap-negative-test \
        --image=docker.io/library/nginx:latest \
        --namespace=quix \
        --restart=Never \
        --overrides='{"spec":{"terminationGracePeriodSeconds":0}}' \
        2>/dev/null || true

    # Wait briefly for the pull attempt to fail
    local attempts=0
    local max_attempts=12  # 60 seconds
    local pull_failed=false

    while [[ $attempts -lt $max_attempts ]]; do
        local status
        status=$(kubectl --context="$CLUSTER_CONTEXT" get pod airgap-negative-test \
            -n quix -o jsonpath='{.status.containerStatuses[0].state.waiting.reason}' 2>/dev/null || echo "")

        if [[ "$status" == "ImagePullBackOff" || "$status" == "ErrImagePull" ]]; then
            pull_failed=true
            break
        fi

        # Also check if it somehow succeeded (bad - means airgap is leaky)
        local phase
        phase=$(kubectl --context="$CLUSTER_CONTEXT" get pod airgap-negative-test \
            -n quix -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
        if [[ "$phase" == "Running" ]]; then
            break
        fi

        sleep 5
        attempts=$((attempts + 1))
    done

    # Clean up the test pod
    kubectl --context="$CLUSTER_CONTEXT" delete pod airgap-negative-test \
        -n quix --grace-period=0 --force 2>/dev/null || true

    if [[ "$pull_failed" == "true" ]]; then
        log_success "Negative test PASSED: docker.io pull correctly blocked by NSG"
    else
        log_error "Negative test FAILED: docker.io/library/nginx was NOT blocked - airgap is leaky!"
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

    # Reserve 10 minutes for post-install steps (lockdown, verify, cleanup).
    # The job timeout is 90 min; we cap install at 80 min from start.
    JOB_DEADLINE_EPOCH=$(( $(date +%s) + 80 * 60 ))

    log_section "Airgap Test Pipeline"
    log "Run ID: $RUN_ID"
    log "Installer Tag: $INSTALLER_TAG"
    log "Start Time: $(date)"
    log "Job Deadline: $(date -d @$JOB_DEADLINE_EPOCH 2>/dev/null || date -r $JOB_DEADLINE_EPOCH)"

    # Set up cleanup trap
    trap cleanup EXIT

    # Run pipeline stages
    validate_prerequisites
    extract_container_versions
    precheck_registry
    terraform_init
    terraform_apply
    get_credentials
    wait_for_nodes
    create_namespace
    generate_byoc_values
    install_byoc
    lockdown_network
    verify_deployment

    log_section "Pipeline Complete"
    log_success "Airgap test passed successfully"
    log "Total Time: $SECONDS seconds"

    EXIT_CODE=0
}

main "$@"
