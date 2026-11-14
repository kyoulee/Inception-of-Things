#!/bin/bash
#
# Installs the Helm binary.
#
# This script fetches and installs Helm using the official script.
# It includes an idempotency check to skip installation if the binary
# already exists, and performs a health check using the --client flag
# to ensure it works independently of the cluster state.
#
# Usage:
#   ./install_helm.sh

set -euo pipefail
source "$(dirname "$0")/libs/utils.sh"

readonly HELM_SCRIPT_URL="https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3"

log_info "Checking Helm installation status..."
if command -v helm >/dev/null 2>&1; then
  log_info "Helm is already installed. (Skipping installation)"
else
  log_info "Downloading and installing Helm..."
  curl -fsSL -o get_helm.sh "${HELM_SCRIPT_URL}"
  chmod +x get_helm.sh
  ./get_helm.sh
  rm -f get_helm.sh
fi

if helm version --client >/dev/null 2>&1; then
  log_info "Helm binary is operational. (Health Check PASS)"
else
  log_error "Failed to execute Helm binary."
  exit 1
fi