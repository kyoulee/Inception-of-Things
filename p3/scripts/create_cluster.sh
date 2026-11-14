#!/bin/bash
#
# Creates a k3d Kubernetes cluster.
#
# This script parses the target cluster name dynamically from the provided 
# k3d configuration file. It verifies dependencies (Docker and k3d) beforehand 
# to ensure a fail-fast execution and guarantees idempotency by skipping 
# creation if the cluster already exists.
#
# Usage:
#   ./create_cluster.sh

set -euo pipefail
source "$(dirname "$0")/libs/utils.sh"

readonly K3D_CONFIG="./confs/k3d/config.yaml"

log_info "Verifying dependencies (k3d, docker) and permissions..."
if ! command -v k3d >/dev/null 2>&1; then
  log_error "k3d command not found. Please verify k3d installation."
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  log_error "Docker command not found. Please verify Docker installation."
  exit 1
fi

if ! docker ps >/dev/null 2>&1; then
  log_error "Cannot access Docker daemon. Please verify Docker status and permissions."
  exit 1
fi

log_info "Verifying k3d configuration file..."
if [[ ! -f "${K3D_CONFIG}" ]]; then
  log_error "Configuration file not found: ${K3D_CONFIG}"
  exit 1
fi

readonly CLUSTER_NAME=$(grep -E '^\s*name:' "${K3D_CONFIG}" | head -n 1 | awk '{print $2}' | tr -d '""'"''")
if [[ -z "${CLUSTER_NAME}" ]]; then
  log_error "Failed to parse the cluster name from the configuration file."
  exit 1
fi
log_info "Target cluster name: ${CLUSTER_NAME}"

log_info "Preparing to create k3d cluster..."
if k3d cluster list "${CLUSTER_NAME}" >/dev/null 2>&1; then
  log_info "k3d cluster '${CLUSTER_NAME}' already exists. (Skipping creation)"
else
  log_info "Creating k3d cluster '${CLUSTER_NAME}'..."
  k3d cluster create --config="${K3D_CONFIG}"
fi

if k3d cluster list >/dev/null 2>&1; then
  log_info "k3d cluster is running successfully. (Health Check PASS)"
else
  log_error "Failed to verify k3d cluster status."
  exit 1
fi