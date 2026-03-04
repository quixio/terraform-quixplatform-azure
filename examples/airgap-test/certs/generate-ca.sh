#!/usr/bin/env bash
# generate-ca.sh - One-time generation of the Airgap Test Root CA.
#
# This CA is checked into the repo so developers can trust it once and have all
# airgap test environments automatically trusted. The wildcard TLS certificate
# is still generated fresh per pipeline run (signed by this CA).
#
# Usage: ./generate-ca.sh          (generates ca.key + ca.crt in this directory)
#
# To trust on macOS:
#   sudo security add-trusted-cert -d -r trustRoot \
#       -k /Library/Keychains/System.keychain certs/ca.crt

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CA_KEY="$SCRIPT_DIR/ca.key"
CA_CRT="$SCRIPT_DIR/ca.crt"

if [[ -f "$CA_KEY" || -f "$CA_CRT" ]]; then
    echo "CA files already exist. Remove them first to regenerate."
    echo "  $CA_KEY"
    echo "  $CA_CRT"
    exit 1
fi

openssl req -x509 -newkey rsa:4096 -nodes \
    -keyout "$CA_KEY" \
    -out "$CA_CRT" \
    -days 3650 \
    -subj "/CN=Airgap Test Root CA/O=Quix" \
    -addext "basicConstraints=critical,CA:TRUE" \
    -addext "keyUsage=critical,keyCertSign,cRLSign" 2>/dev/null

echo "Generated:"
echo "  $CA_KEY"
echo "  $CA_CRT"
echo ""
echo "To trust on macOS:"
echo "  sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain $CA_CRT"
