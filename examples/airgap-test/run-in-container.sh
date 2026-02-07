#!/bin/bash
#
# Run airgap test in container with all required mounts
#
# Prerequisites:
#   - Docker running
#   - Azure CLI logged in (~/.azure mounted)
#   - Environment variables set (or will prompt)
#
# Usage:
#   ./run-in-container.sh [--skip-destroy]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default paths - adjust if your repos are elsewhere
BYOC_PATH="${BYOC_PATH:-$SCRIPT_DIR/../../../Infrastructure.BYOC}"
BYOCVERSIONS_PATH="${BYOCVERSIONS_PATH:-$SCRIPT_DIR/../../../Infrastructure.BYOCVersions}"

# Check required env vars
REQUIRED_VARS="QUIX_ACR_USERNAME QUIX_ACR_PASSWORD QUIX_ZIP_CLIENT_ID QUIX_ZIP_CLIENT_SECRET QUIX_ZIP_TENANT_ID QUIX_LICENSE_KEY"
MISSING=""
for var in $REQUIRED_VARS; do
    if [[ -z "${!var:-}" ]]; then
        MISSING="$MISSING $var"
    fi
done

if [[ -n "$MISSING" ]]; then
    echo "ERROR: Missing required environment variables:$MISSING"
    echo ""
    echo "Set them before running:"
    echo "  export QUIX_ACR_USERNAME=..."
    echo "  export QUIX_ACR_PASSWORD=..."
    echo "  export QUIX_ZIP_CLIENT_ID=..."
    echo "  export QUIX_ZIP_CLIENT_SECRET=..."
    echo "  export QUIX_ZIP_TENANT_ID=..."
    echo "  export QUIX_LICENSE_KEY=..."
    exit 1
fi

# Check paths exist
if [[ ! -d "$BYOC_PATH" ]]; then
    echo "ERROR: Infrastructure.BYOC not found at: $BYOC_PATH"
    echo "Set BYOC_PATH environment variable to the correct location"
    exit 1
fi

if [[ ! -d "$BYOCVERSIONS_PATH" ]]; then
    echo "ERROR: Infrastructure.BYOCVersions not found at: $BYOCVERSIONS_PATH"
    echo "Set BYOCVERSIONS_PATH environment variable to the correct location"
    exit 1
fi

echo "=== Airgap Test Container Runner ==="
echo "BYOC Path: $BYOC_PATH"
echo "BYOCVersions Path: $BYOCVERSIONS_PATH"
echo ""

# Run the container with ACR login first
docker run -it --rm \
    --platform linux/amd64 \
    -v ~/.azure:/root/.azure \
    -v ~/.kube:/root/.kube \
    -v "$SCRIPT_DIR:/workspace" \
    -v "$BYOC_PATH:/byoc" \
    -v "$BYOCVERSIONS_PATH:/byocversions" \
    -w /workspace \
    -e QUIX_ACR_USERNAME \
    -e QUIX_ACR_PASSWORD \
    -e QUIX_ZIP_CLIENT_ID \
    -e QUIX_ZIP_CLIENT_SECRET \
    -e QUIX_ZIP_TENANT_ID \
    -e QUIX_LICENSE_KEY \
    -e BYOC_PATH=/byoc \
    -e BYOCVERSIONS_DIR=/byocversions \
    -e AZURE_CLI_DISABLE_AZURELINUX2_WARNING=1 \
    --entrypoint /bin/bash \
    quixregistry.azurecr.io/airgap-test-runner:latest \
    -c "az acr login -n quixregistry && az acr login -n quixcontainerregistry && ./run-airgap-test.sh $*"
