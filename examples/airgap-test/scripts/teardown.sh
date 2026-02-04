#!/usr/bin/env bash
set -euo pipefail

#
# teardown.sh - Destroy airgap test resources
#
# This script destroys all resources created by terraform.
# Uses --no-wait for faster execution in CI/CD.
#
# Usage:
#   ./scripts/teardown.sh [--wait]
#
# Options:
#   --wait    Wait for resource group deletion to complete
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

WAIT_FOR_DELETE=false
if [[ "${1:-}" == "--wait" ]]; then
    WAIT_FOR_DELETE=true
fi

# Get resource group from terraform
RESOURCE_GROUP=$(terraform -chdir="$TF_DIR" output -raw resource_group_name 2>/dev/null || echo "")

if [[ -z "$RESOURCE_GROUP" ]]; then
    log_warn "Could not get resource group from terraform output"
    log_info "Attempting terraform destroy anyway..."
fi

log_info "=== Teardown Airgap Test ==="
log_info "Resource Group: ${RESOURCE_GROUP:-unknown}"

# Option 1: Use terraform destroy (preferred - cleaner state management)
log_info "Running terraform destroy..."
if terraform -chdir="$TF_DIR" destroy -auto-approve -parallelism=30; then
    log_info "Terraform destroy completed"
else
    log_warn "Terraform destroy had issues, attempting az group delete..."

    # Option 2: Fallback to az group delete
    if [[ -n "$RESOURCE_GROUP" ]]; then
        log_info "Deleting resource group $RESOURCE_GROUP..."
        if [[ "$WAIT_FOR_DELETE" == "true" ]]; then
            az group delete --name "$RESOURCE_GROUP" --yes
        else
            az group delete --name "$RESOURCE_GROUP" --yes --no-wait
            log_info "Resource group deletion initiated (async)"
        fi
    fi
fi

# Clean up terraform state
log_info "Cleaning up local terraform state..."
rm -f "$TF_DIR/terraform.tfstate"
rm -f "$TF_DIR/terraform.tfstate.backup"
rm -f "$TF_DIR/.terraform.lock.hcl"
rm -rf "$TF_DIR/.terraform"

log_info "Teardown complete"

# Verify no orphaned resources
if [[ -n "$RESOURCE_GROUP" ]]; then
    log_info "Checking for orphaned resources..."
    if az group show --name "$RESOURCE_GROUP" &>/dev/null; then
        STATE=$(az group show --name "$RESOURCE_GROUP" --query "properties.provisioningState" -o tsv 2>/dev/null || echo "Unknown")
        log_warn "Resource group still exists (state: $STATE)"
        if [[ "$WAIT_FOR_DELETE" == "true" ]]; then
            log_info "Waiting for deletion..."
            while az group show --name "$RESOURCE_GROUP" &>/dev/null; do
                sleep 10
            done
            log_info "Resource group deleted"
        fi
    else
        log_info "Resource group confirmed deleted"
    fi
fi
