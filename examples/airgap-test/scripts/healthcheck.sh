#!/usr/bin/env bash
#
# healthcheck.sh - Comprehensive Quix platform health checker
#
# Checks (in dependency order):
#   1. Registry connectivity & credentials
#   2. Infrastructure (cert-manager, traefik, mongo, kafka)
#   3. Platform core services
#   4. Full platform health
#
# Exit codes:
#   0 - All checks passed
#   1 - Critical failure (registry/infra)
#   2 - Platform issues (services unhealthy)
#   3 - Warnings only (non-critical issues)
#
# Usage:
#   ./healthcheck.sh [--verbose] [--json]
#

set -euo pipefail

VERBOSE=${VERBOSE:-false}
JSON_OUTPUT=${JSON_OUTPUT:-false}
NAMESPACE_PREFIX="quix"

# Parse args
for arg in "$@"; do
    case $arg in
        --verbose|-v) VERBOSE=true ;;
        --json|-j) JSON_OUTPUT=true ;;
    esac
done

# Colors (disabled for JSON output)
if [[ "$JSON_OUTPUT" == "true" ]]; then
    RED="" GREEN="" YELLOW="" BLUE="" NC=""
else
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
fi

# Result tracking
declare -A RESULTS
CRITICAL_FAIL=false
PLATFORM_FAIL=false
WARNINGS=false

log_check() {
    local name="$1"
    local status="$2"
    local details="${3:-}"

    RESULTS["$name"]="$status"

    if [[ "$JSON_OUTPUT" == "true" ]]; then
        return
    fi

    case "$status" in
        PASS) echo -e "${GREEN}[PASS]${NC} $name" ;;
        FAIL) echo -e "${RED}[FAIL]${NC} $name${details:+ - $details}" ;;
        WARN) echo -e "${YELLOW}[WARN]${NC} $name${details:+ - $details}" ;;
        SKIP) echo -e "${BLUE}[SKIP]${NC} $name${details:+ - $details}" ;;
    esac
}

log_section() {
    [[ "$JSON_OUTPUT" == "true" ]] && return
    echo ""
    echo -e "${BLUE}=== $1 ===${NC}"
}

verbose() {
    [[ "$VERBOSE" == "true" ]] && echo "  $1"
}

#############################################################################
# SECTION 1: Registry & Image Checks
#############################################################################

check_registry() {
    log_section "Registry & Image Availability"

    # Check pull secret exists
    local pull_secret
    pull_secret=$(kubectl get secret registrypullsecret -n quix -o name 2>/dev/null || echo "")
    if [[ -z "$pull_secret" ]]; then
        log_check "Pull secret exists" "FAIL" "registrypullsecret not found in quix namespace"
        CRITICAL_FAIL=true
        return 1
    fi
    log_check "Pull secret exists" "PASS"

    # Check for ImagePullBackOff pods
    local pull_errors
    pull_errors=$(kubectl get pods -A -o wide 2>/dev/null | grep -c "ImagePullBackOff\|ErrImagePull" || true)
    pull_errors=${pull_errors:-0}
    if [[ "$pull_errors" -gt 0 ]]; then
        log_check "No ImagePullBackOff" "FAIL" "$pull_errors pods with image pull errors"
        verbose "$(kubectl get pods -A | grep -E 'ImagePullBackOff|ErrImagePull' | head -5)"
        CRITICAL_FAIL=true
    else
        log_check "No ImagePullBackOff" "PASS"
    fi

    # Check registry connectivity (if we have a running pod)
    local test_pod
    test_pod=$(kubectl get pods -n quix -o name 2>/dev/null | head -1)
    if [[ -n "$test_pod" ]]; then
        log_check "Registry reachable" "PASS" "pods running means registry worked"
    fi
}

#############################################################################
# SECTION 2: Infrastructure Checks
#############################################################################

check_infra_component() {
    local name="$1"
    local namespace="$2"
    local min_ready="${3:-1}"

    local ready_count
    ready_count=$(kubectl get pods -n "$namespace" -o jsonpath='{.items[*].status.containerStatuses[*].ready}' 2>/dev/null | tr ' ' '\n' | grep -c "true" || true)
    ready_count=$(echo "$ready_count" | tr -d '[:space:]')
    ready_count=${ready_count:-0}

    local total_count
    total_count=$(kubectl get pods -n "$namespace" --no-headers 2>/dev/null | wc -l)
    total_count=$(echo "$total_count" | tr -d '[:space:]')
    total_count=${total_count:-0}

    if [[ "$total_count" -eq 0 ]]; then
        log_check "$name" "FAIL" "no pods in $namespace"
        return 1
    elif [[ "$ready_count" -lt "$min_ready" ]]; then
        log_check "$name" "WARN" "$ready_count/$total_count ready (need $min_ready)"
        WARNINGS=true
        return 0
    else
        log_check "$name" "PASS" "$ready_count/$total_count ready"
        return 0
    fi
}

check_kafka() {
    local namespace="$1"
    local name="$2"

    local ready
    ready=$(kubectl get kafka "$name" -n "$namespace" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")

    if [[ "$ready" == "True" ]]; then
        log_check "Kafka $name" "PASS" "Ready"
        return 0
    else
        local message
        message=$(kubectl get kafka "$name" -n "$namespace" -o jsonpath='{.status.conditions[?(@.type=="NotReady")].message}' 2>/dev/null || echo "unknown")
        log_check "Kafka $name" "FAIL" "$message"
        return 1
    fi
}

check_infrastructure() {
    log_section "Infrastructure Components"

    local infra_ok=true

    # Cert-manager
    check_infra_component "cert-manager" "${NAMESPACE_PREFIX}-cert-manager" 3 || infra_ok=false

    # Traefik
    check_infra_component "traefik" "${NAMESPACE_PREFIX}-ingress-traefik" 1 || infra_ok=false

    # MongoDB
    check_infra_component "mongodb" "${NAMESPACE_PREFIX}-mongo" 1 || infra_ok=false

    # Verify mongo is actually responding
    local mongo_ready
    mongo_ready=$(kubectl exec -n "${NAMESPACE_PREFIX}-mongo" mongo-mongodb-0 -- mongosh --quiet --eval "db.adminCommand('ping')" 2>/dev/null | grep -c "ok" || echo "0")
    if [[ "$mongo_ready" -gt 0 ]]; then
        log_check "mongodb responsive" "PASS"
    else
        log_check "mongodb responsive" "WARN" "ping failed"
        WARNINGS=true
    fi

    # Gitea
    check_infra_component "gitea" "${NAMESPACE_PREFIX}-gitea" 1 || infra_ok=false

    # Kafka Operator
    check_infra_component "kafka-operator" "${NAMESPACE_PREFIX}-kafka-operator" 1 || infra_ok=false

    # Kafka clusters
    for ns in $(kubectl get ns -o name 2>/dev/null | grep "${NAMESPACE_PREFIX}-kafka-" | grep -v operator | cut -d/ -f2); do
        local kafka_name
        kafka_name=$(kubectl get kafka -n "$ns" -o name 2>/dev/null | head -1 | cut -d/ -f2)
        if [[ -n "$kafka_name" ]]; then
            check_kafka "$ns" "$kafka_name" || infra_ok=false
        fi
    done

    if [[ "$infra_ok" == "false" ]]; then
        CRITICAL_FAIL=true
    fi
}

#############################################################################
# SECTION 3: Platform Core Checks
#############################################################################

check_platform_service() {
    local name="$1"
    local min_ready="${2:-1}"

    local ready_count
    ready_count=$(kubectl get pods -n quix -l "app.kubernetes.io/name=$name" -o jsonpath='{.items[*].status.containerStatuses[*].ready}' 2>/dev/null | tr ' ' '\n' | grep -c "true" || true)
    ready_count=$(echo "$ready_count" | tr -d '[:space:]')
    ready_count=${ready_count:-0}

    # Fallback to name prefix match
    if [[ "$ready_count" -eq 0 ]]; then
        ready_count=$(kubectl get pods -n quix --no-headers 2>/dev/null | grep "^${name}" | grep -c "Running" || true)
        ready_count=$(echo "$ready_count" | tr -d '[:space:]')
        ready_count=${ready_count:-0}
    fi

    if [[ "$ready_count" -ge "$min_ready" ]]; then
        log_check "$name" "PASS" "$ready_count running"
        return 0
    else
        log_check "$name" "FAIL" "$ready_count running (need $min_ready)"
        return 1
    fi
}

check_platform_core() {
    log_section "Platform Core Services"

    local core_ok=true

    # Critical services that must be running
    check_platform_service "auth-api" 1 || core_ok=false
    check_platform_service "portal-api" 1 || core_ok=false
    check_platform_service "portal-frontend" 1 || core_ok=false
    check_platform_service "workspace-service" 1 || core_ok=false
    check_platform_service "user-service" 1 || core_ok=false

    if [[ "$core_ok" == "false" ]]; then
        PLATFORM_FAIL=true
    fi
}

#############################################################################
# SECTION 4: Full Platform Health
#############################################################################

check_platform_full() {
    log_section "Platform Full Health"

    # Check for CrashLoopBackOff
    local crash_count
    crash_count=$(kubectl get pods -n quix --no-headers 2>/dev/null | grep -c "CrashLoopBackOff" || true)
    crash_count=$(echo "$crash_count" | tr -d '[:space:]')
    crash_count=${crash_count:-0}
    if [[ "$crash_count" -gt 0 ]]; then
        log_check "No CrashLoopBackOff" "WARN" "$crash_count pods crashing"
        verbose "$(kubectl get pods -n quix | grep CrashLoopBackOff | head -5)"
        WARNINGS=true
    else
        log_check "No CrashLoopBackOff" "PASS"
    fi

    # Check for pending pods
    local pending_count
    pending_count=$(kubectl get pods -n quix --no-headers 2>/dev/null | grep -c "Pending" || true)
    pending_count=$(echo "$pending_count" | tr -d '[:space:]')
    pending_count=${pending_count:-0}
    if [[ "$pending_count" -gt 0 ]]; then
        log_check "No Pending pods" "WARN" "$pending_count pods pending"
        WARNINGS=true
    else
        log_check "No Pending pods" "PASS"
    fi

    # Overall pod health ratio
    local total_pods ready_pods
    total_pods=$(kubectl get pods -n quix --no-headers 2>/dev/null | grep -v Completed | wc -l)
    total_pods=$(echo "$total_pods" | tr -d '[:space:]')
    total_pods=${total_pods:-0}
    ready_pods=$(kubectl get pods -n quix --no-headers 2>/dev/null | grep -v Completed | grep -c "Running" || true)
    ready_pods=$(echo "$ready_pods" | tr -d '[:space:]')
    ready_pods=${ready_pods:-0}

    local health_pct=0
    if [[ "$total_pods" -gt 0 ]]; then
        health_pct=$((ready_pods * 100 / total_pods))
    fi

    if [[ "$health_pct" -ge 90 ]]; then
        log_check "Platform health" "PASS" "${health_pct}% ($ready_pods/$total_pods pods running)"
    elif [[ "$health_pct" -ge 70 ]]; then
        log_check "Platform health" "WARN" "${health_pct}% ($ready_pods/$total_pods pods running)"
        WARNINGS=true
    else
        log_check "Platform health" "FAIL" "${health_pct}% ($ready_pods/$total_pods pods running)"
        PLATFORM_FAIL=true
    fi

    # LoadBalancer check
    local lb_ip
    lb_ip=$(kubectl get svc -n "${NAMESPACE_PREFIX}-ingress-traefik" quix-traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    if [[ -n "$lb_ip" ]]; then
        log_check "LoadBalancer IP" "PASS" "$lb_ip"
    else
        log_check "LoadBalancer IP" "WARN" "no external IP assigned"
        WARNINGS=true
    fi
}

#############################################################################
# SECTION 5: Diagnostic helpers
#############################################################################

diagnose_failures() {
    [[ "$JSON_OUTPUT" == "true" ]] && return

    echo ""
    echo -e "${BLUE}=== Diagnostics ===${NC}"

    # Show recent events with issues
    local problem_events
    problem_events=$(kubectl get events -A --sort-by='.lastTimestamp' 2>/dev/null | grep -iE "failed|error|backoff|pull|timeout" | tail -5)
    if [[ -n "$problem_events" ]]; then
        echo -e "${YELLOW}Recent problem events:${NC}"
        echo "$problem_events"
    fi

    # Show unhealthy pods
    local unhealthy
    unhealthy=$(kubectl get pods -A --no-headers 2>/dev/null | grep -v "Running\|Completed" | grep quix | head -5)
    if [[ -n "$unhealthy" ]]; then
        echo ""
        echo -e "${YELLOW}Unhealthy pods:${NC}"
        echo "$unhealthy"
    fi
}

output_json() {
    echo "{"
    echo "  \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
    echo "  \"critical_failure\": $CRITICAL_FAIL,"
    echo "  \"platform_failure\": $PLATFORM_FAIL,"
    echo "  \"warnings\": $WARNINGS,"
    echo "  \"checks\": {"
    local first=true
    for key in "${!RESULTS[@]}"; do
        [[ "$first" == "true" ]] && first=false || echo ","
        echo -n "    \"$key\": \"${RESULTS[$key]}\""
    done
    echo ""
    echo "  }"
    echo "}"
}

#############################################################################
# Main
#############################################################################

main() {
    [[ "$JSON_OUTPUT" != "true" ]] && echo "Quix Platform Health Check"
    [[ "$JSON_OUTPUT" != "true" ]] && echo "=========================="

    # Run all checks (don't exit early on failures due to set -e)
    check_registry || true
    check_infrastructure || true
    check_platform_core || true
    check_platform_full || true

    if [[ "$JSON_OUTPUT" == "true" ]]; then
        output_json
    else
        diagnose_failures

        echo ""
        echo "=========================="
        if [[ "$CRITICAL_FAIL" == "true" ]]; then
            echo -e "${RED}RESULT: CRITICAL FAILURE${NC}"
            exit 1
        elif [[ "$PLATFORM_FAIL" == "true" ]]; then
            echo -e "${RED}RESULT: PLATFORM ISSUES${NC}"
            exit 2
        elif [[ "$WARNINGS" == "true" ]]; then
            echo -e "${YELLOW}RESULT: PASSED WITH WARNINGS${NC}"
            exit 3
        else
            echo -e "${GREEN}RESULT: ALL CHECKS PASSED${NC}"
            exit 0
        fi
    fi
}

main "$@"
