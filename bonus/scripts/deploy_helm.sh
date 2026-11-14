#!/bin/bash
#
# Deploys GitLab via Helm to the target k3d cluster.
#
# This script extracts the cluster name from the k3d configuration file,
# identifies the corresponding Docker container node, and ensures the 
# GitLab Helm chart is deployed idempotently. It also performs a health 
# check by waiting for the essential GitLab pods to become ready.
#
# Usage:
#   ./deploy_helm.sh

set -euo pipefail
source "$(dirname "$0")/libs/utils.sh"

readonly K3D_CONFIG="./confs/k3d/config.yaml"
readonly VALUES_FILE="./confs/helm/values.yaml"
readonly NAMESPACE="gitlab"
readonly RELEASE_NAME="gitlab"
readonly CHART_NAME="gitlab/gitlab"
readonly CHART_VERSION="9.11.14"
readonly HELM_REPO_URL="https://charts.gitlab.io/"

log_info "Verifying dependencies (k3d, helm, docker)..."
if ! command -v k3d >/dev/null 2>&1; then
  log_error "k3d command not found. Please verify k3d installation."
  exit 1
fi
if ! command -v helm >/dev/null 2>&1; then
  log_error "helm command not found. Please verify Helm installation."
  exit 1
fi
if ! docker ps >/dev/null 2>&1; then
  log_error "Cannot access Docker daemon. Please verify Docker status."
  exit 1
fi

log_info "Verifying k3d configuration file..."
if [[ ! -f "${K3D_CONFIG}" ]]; then
  log_error "Configuration file not found: ${K3D_CONFIG}"
  exit 1
fi

# Parse cluster name dynamically to ensure Single Source of Truth
readonly CLUSTER_NAME=$(grep -E '^\s*name:' "${K3D_CONFIG}" | head -n 1 | awk '{print $2}' | tr -d '""'"''")
if [[ -z "${CLUSTER_NAME}" ]]; then
  log_error "Failed to parse the cluster name from the configuration file."
  exit 1
fi

readonly CLUSTER_NODE="k3d-${CLUSTER_NAME}-server-0"
log_info "Target cluster node resolved: ${CLUSTER_NODE}"

if ! docker ps --format '{{.Names}}' | grep -q "^${CLUSTER_NODE}$"; then
  log_error "Target cluster node is not running: ${CLUSTER_NODE}"
  exit 1
fi

log_info "Verifying Helm values configuration file..."
if [[ ! -f "${VALUES_FILE}" ]]; then
  log_error "Helm values file not found: ${VALUES_FILE}"
  exit 1
fi

log_info "Checking GitLab Helm repository status..."
if helm repo list 2>/dev/null | grep -q "^gitlab\b"; then
  log_info "GitLab repository is already registered."
else
  log_info "Adding and syncing GitLab Helm repository..."
  helm repo add gitlab "${HELM_REPO_URL}" >/dev/null 2>&1
fi
helm repo update gitlab >/dev/null 2>&1

log_info "Checking GitLab release status..."
if helm status "${RELEASE_NAME}" -n "${NAMESPACE}" >/dev/null 2>&1; then
  log_info "GitLab release ('${RELEASE_NAME}') is already deployed. (Skipping installation)"
else
  log_info "Deploying GitLab (Version: ${CHART_VERSION}). This process may take several minutes..."
  helm install "${RELEASE_NAME}" "${CHART_NAME}" \
    --version "${CHART_VERSION}" \
    --namespace "${NAMESPACE}" \
    --create-namespace \
    -f "${VALUES_FILE}" \
    --wait \
    --timeout 20m \
    --debug
fi

if helm status "${RELEASE_NAME}" -n "${NAMESPACE}" | grep -i -q "STATUS: deployed"; then
  log_info "GitLab Helm deployment completed successfully. (Helm Status PASS)"
else
  log_error "GitLab deployment failed or is in an invalid state."
  exit 1
fi

log_info "Waiting for essential GitLab pods to become ready (up to 15 minutes)..."
if docker exec -i "${CLUSTER_NODE}" kubectl wait --namespace "${NAMESPACE}" --for=condition=ready pod --selector='!job-name' --timeout=900s >/dev/null 2>&1; then
  
  if helm status "${RELEASE_NAME}" -n "${NAMESPACE}" | grep -i -q "STATUS: deployed"; then
    log_info "All GitLab pods are running successfully. (Health Check PASS)"
  else
    log_error "Pods are running, but Helm release status is invalid."
    exit 1
  fi

else
  log_error "Some GitLab pods failed to become ready within the specified timeout."
  log_error "To investigate, run: docker exec -i ${CLUSTER_NODE} kubectl get pods -n ${NAMESPACE}"
  exit 1
fi