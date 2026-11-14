#!/bin/bash
#
# Installs the k3d binary.
#
# This script fetches and installs k3d from its official repository. 
# It includes an idempotency check to skip installation if the binary 
# already exists, and performs a health check to verify functionality.
#
# Usage:
#   ./install_k3d.sh

set -euo pipefail
source "$(dirname "$0")/libs/utils.sh"

readonly K3D_URL="https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh"

log_info "Checking k3d installation status..."
if command -v k3d >/dev/null 2>&1; then
  log_info "k3d is already installed. (Skipping installation)"
else
  log_info "Downloading and installing k3d..."
  curl -fsSL -o get-k3d.sh "${K3D_URL}"
  chmod +x ./get-k3d.sh
  ./get-k3d.sh
  rm -f ./get-k3d.sh
fi

if k3d version >/dev/null 2>&1; then
  log_info "k3d binary is operational. (Health Check PASS)"
else
  log_error "Failed to execute k3d binary."
  exit 1
fi