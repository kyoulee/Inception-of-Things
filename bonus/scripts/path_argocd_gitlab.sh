#!/bin/bash
#
# Configures GitLab DNS resolution and deploys the Repository Secret
# to the target Argo CD cluster.
#
# [Description]
# This script extracts the Argo CD cluster name from the k3d configuration file,
# identifies the corresponding Docker container node, and verifies its status.
# It then deploys the CoreDNS custom configuration (to resolve gitlab.localhost)
# and the repository secret (which contains credentials and the insecure flag
# for the self-signed SSL certificate) directly into the cluster via 'docker exec'.
# It ensures idempotency by verifying dependencies and checking for the existence
# of required configuration files before applying them.
#
# Usage:
#   ./path_argocd_gitlab.sh

set -euo pipefail

source "$(dirname "$0")/libs/utils.sh"

readonly K3D_CONFIG="../p3/confs/k3d/config.yaml"
readonly COREDNS_CUSTOM_FILE="./confs/gitlab/coredns-custom.yaml"
readonly ARGOCD_SECRET_FILE="../p3/confs/server/argocd/secret.yaml"
readonly ARGOCD_APPLICATION_FILE="./confs/gitlab/application.yaml"
readonly NAMESPACE="argocd"

log_info "Verifying dependencies (docker)..."
if ! command -v docker >/dev/null 2>&1; then
  log_error "docker command not found. Please verify Docker installation."
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

log_info "Verifying target CoreDNS custom file..."
if [[ ! -f "${COREDNS_CUSTOM_FILE}" ]]; then
  log_error "CoreDNS custom file not found: ${COREDNS_CUSTOM_FILE}"
  exit 1
fi

log_info "Verifying target secret file..."
if [[ ! -f "${ARGOCD_SECRET_FILE}" ]]; then
  log_error "ArgoCD secret file not found: ${ARGOCD_SECRET_FILE}"
  exit 1
fi

log_info "Verifying target argocd application file..."
if [[ ! -f "${ARGOCD_APPLICATION_FILE}" ]]; then
  log_error "ArgoCD application file not found: ${ARGOCD_APPLICATION_FILE}"
  exit 1
fi

readonly CLUSTER_NAME=$(grep -E '^\s*name:' "${K3D_CONFIG}" | head -n 1 | awk '{print $2}' | tr -d '""'"''")
if [[ -z "${CLUSTER_NAME}" ]]; then
  log_error "Failed to parse the cluster name from the configuration file."
  exit 1
fi

readonly CLUSTER_NODE="k3d-${CLUSTER_NAME}-server-0"
log_info "Target cluster node resolved: ${CLUSTER_NODE}"

log_info "Checking status of cluster node container..."
if ! docker ps --format '{{.Names}}' | grep -q "^${CLUSTER_NODE}$"; then
  log_error "Target cluster node is not running: ${CLUSTER_NODE}. Is Argo CD cluster up?"
  exit 1
fi

log_info "State modification: Applying CoreDNS custom configuration to ArgoCD cluster..."
if cat "${COREDNS_CUSTOM_FILE}" | docker exec -i "${CLUSTER_NODE}" kubectl apply -f -; then
  if docker exec -i "${CLUSTER_NODE}" kubectl rollout restart deployment coredns -n kube-system > /dev/null 2>&1 \
    && docker exec -i "${CLUSTER_NODE}" kubectl rollout status deployment coredns -n kube-system --timeout=60s > /dev/null 2>&1; then
    log_info "CoreDNS restarted successfully."
  else
    log_error "CoreDNS rollout failed or timed out."
    exit 1
  fi
  if docker exec -i "${CLUSTER_NODE}" kubectl get cm coredns-custom -n kube-system -o yaml \
    | grep -q "gitlab.localhost"; then
    log_info "CoreDNS custom ConfigMap ('gitlab.localhost') verified. (Health Check PASS)"
  else
    log_error "Verification failed: 'gitlab.localhost' not found in coredns-custom."
    exit 1
  fi
else
  log_error "Failed to apply CoreDNS custom configuration."
  exit 1
fi

log_info "State modification: Applying GitLab Repo Secret to ArgoCD cluster..."
if cat "${ARGOCD_SECRET_FILE}" | docker exec -i "${CLUSTER_NODE}" kubectl apply -n "${NAMESPACE}" -f -; then
  log_info "ArgoCD secret applied successfully. (Health Check PASS)"
else
  log_error "Failed to apply ArgoCD secret."
  exit 1
fi

log_info "State modification: Applying GitLab Repo update application url to ArgoCD cluster..."
if cat "${ARGOCD_APPLICATION_FILE}" | docker exec -i "${CLUSTER_NODE}" kubectl apply -n "${NAMESPACE}" -f -; then
  log_info "ArgoCD repo url updated applied successfully. (Health Check PASS)"
else
  log_error "Failed to apply ArgoCD repo update."
  exit 1
fi

log_info "ArgoCD-GitLab integration pipeline completed."