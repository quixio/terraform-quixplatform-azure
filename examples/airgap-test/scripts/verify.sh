#!/usr/bin/env bash
set -euo pipefail

#
# verify.sh - Verify Quix Platform installation
#
# Checks:
#   - All expected namespaces exist
#   - No pods in ImagePullBackOff state
#   - Core services are running
#
# Usage:
#   ./scripts/verify.sh
#
# Exit codes:
#   0 - All checks passed
#   1 - Verification failed
#

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; }

ERRORS=0

check() {
    local name="$1"
    local result="$2"
    if [[ "$result" == "0" ]]; then
        log_pass "$name"
    else
        log_fail "$name"
        ((ERRORS++))
    fi
}

log_info "=== Quix Platform Verification ==="
echo ""

# Check namespaces
log_info "Checking namespaces..."
EXPECTED_NS=("quix" "quix-ingress-traefik" "quix-mongo" "quix-gitea")
for ns in "${EXPECTED_NS[@]}"; do
    if kubectl get ns "$ns" &>/dev/null; then
        check "Namespace $ns exists" 0
    else
        check "Namespace $ns exists" 1
    fi
done
echo ""

# Check for ImagePullBackOff
log_info "Checking for ImagePullBackOff pods..."
PULL_ERRORS=$(kubectl get pods -A -o wide 2>/dev/null | grep -c "ImagePullBackOff\|ErrImagePull" || true)
if [[ "$PULL_ERRORS" -eq 0 ]]; then
    check "No ImagePullBackOff pods" 0
else
    check "No ImagePullBackOff pods ($PULL_ERRORS found)" 1
    log_warn "Pods with image pull errors:"
    kubectl get pods -A | grep -E "ImagePullBackOff|ErrImagePull" || true
fi
echo ""

# Check core services
log_info "Checking core services in quix namespace..."
CORE_SERVICES=("admin-ui" "portal-frontend" "portal-api" "auth-api" "workspace-service")
for svc in "${CORE_SERVICES[@]}"; do
    RUNNING=$(kubectl get pods -n quix -l "app.kubernetes.io/name=$svc" -o jsonpath='{.items[*].status.phase}' 2>/dev/null | grep -c "Running" || true)
    if [[ "$RUNNING" -gt 0 ]]; then
        check "Service $svc running" 0
    else
        # Try alternative label
        RUNNING=$(kubectl get pods -n quix 2>/dev/null | grep -c "^$svc.*Running" || true)
        if [[ "$RUNNING" -gt 0 ]]; then
            check "Service $svc running" 0
        else
            check "Service $svc running" 1
        fi
    fi
done
echo ""

# Check CrashLoopBackOff
log_info "Checking for CrashLoopBackOff pods..."
CRASH_ERRORS=$(kubectl get pods -A 2>/dev/null | grep -c "CrashLoopBackOff" || true)
if [[ "$CRASH_ERRORS" -eq 0 ]]; then
    check "No CrashLoopBackOff pods" 0
else
    check "No CrashLoopBackOff pods ($CRASH_ERRORS found)" 1
    log_warn "Pods in CrashLoopBackOff:"
    kubectl get pods -A | grep "CrashLoopBackOff" | head -10 || true
fi
echo ""

# Check traefik
log_info "Checking ingress..."
TRAEFIK_RUNNING=$(kubectl get pods -n quix-ingress-traefik 2>/dev/null | grep -c "Running" || true)
if [[ "$TRAEFIK_RUNNING" -gt 0 ]]; then
    check "Traefik ingress running" 0
else
    check "Traefik ingress running" 1
fi
echo ""

# Check MongoDB
log_info "Checking MongoDB..."
MONGO_RUNNING=$(kubectl get pods -n quix-mongo 2>/dev/null | grep -c "Running" || true)
if [[ "$MONGO_RUNNING" -gt 0 ]]; then
    check "MongoDB running" 0
else
    check "MongoDB running" 1
fi
echo ""

# Summary
echo ""
log_info "=== Summary ==="
if [[ "$ERRORS" -eq 0 ]]; then
    log_pass "All checks passed!"
    exit 0
else
    log_fail "$ERRORS check(s) failed"
    echo ""
    log_info "Pod status summary:"
    kubectl get pods -A | head -30
    exit 1
fi
