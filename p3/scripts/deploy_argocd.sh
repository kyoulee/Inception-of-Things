#!/bin/bash
#
# Deploys Argo CD to the target k3d cluster.
#
# This script extracts the cluster name from the k3d configuration file,
# identifies the corresponding Docker container node, and uses 'docker exec'
# to deploy Argo CD manifests directly into the cluster. It ensures idempotency
# by verifying current states and performs health checks by waiting for the 
# Argo CD server pod to become ready. It also generates and patches the initial 
# admin password using bcrypt.
#
# Usage:
#   ./deploy_argocd.sh

set -euo pipefail
source "$(dirname "$0")/libs/utils.sh"

readonly K3D_CONFIG="./confs/k3d/config.yaml"
readonly LOCAL_CONF_DIR="./confs/server"
readonly REMOTE_TMP_DIR="/tmp/server"
readonly ARGOCD_VERSION="v2.6.15"
readonly ARGOCD_INSTALL_URL="https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"
readonly TARGET_PASSWORD="password123"

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

readonly CLUSTER_NODE="k3d-${CLUSTER_NAME}-server-0"
log_info "Target cluster node resolved: ${CLUSTER_NODE}"

log_info "Checking status of cluster node container..."
if ! docker ps --format '{{.Names}}' | grep -q "^${CLUSTER_NODE}$"; then
  log_error "Target cluster node is not running: ${CLUSTER_NODE}"
  exit 1
fi

log_info "Copying manifest files to the cluster node..."
if [[ ! -d "${LOCAL_CONF_DIR}" ]]; then
  log_error "Local configuration directory not found: ${LOCAL_CONF_DIR}"
  exit 1
fi

docker exec -i "${CLUSTER_NODE}" rm -rf "${REMOTE_TMP_DIR}" || true
docker cp "${LOCAL_CONF_DIR}" "${CLUSTER_NODE}:/tmp"

log_info "Applying namespace configurations..."
docker exec -i "${CLUSTER_NODE}" kubectl apply -f "${REMOTE_TMP_DIR}/init-ns.yaml"

log_info "Deploying Argo CD (${ARGOCD_VERSION})..."
docker exec -i "${CLUSTER_NODE}" kubectl apply -n argocd -f "${ARGOCD_INSTALL_URL}"

log_info "Waiting for Argo CD CRDs to be established..."
docker exec -i "${CLUSTER_NODE}" kubectl wait --for=condition=established --timeout=300s crd/applications.argoproj.io

log_info "Deploying custom Argo CD services and applications..."
docker exec -i "${CLUSTER_NODE}" kubectl apply -f "${REMOTE_TMP_DIR}/argocd/service.yaml"
docker exec -i "${CLUSTER_NODE}" kubectl apply -f "${REMOTE_TMP_DIR}/argocd/application.yaml"

log_info "Waiting for Argo CD server pod to become ready..."
if docker exec -i "${CLUSTER_NODE}" kubectl wait --namespace argocd --for=condition=ready pod --selector=app.kubernetes.io/name=argocd-server --timeout=300s; then
  log_info "Argo CD deployed successfully. (Health Check PASS)"
else
  log_error "Argo CD server pod failed to start properly."
  exit 1
fi

log_info "Updating Argo CD admin password to '${TARGET_PASSWORD}'..."
ARGOCD_POD=$(docker exec -i "${CLUSTER_NODE}" kubectl get pod -n argocd -l app.kubernetes.io/name=argocd-server -o jsonpath='{.items[0].metadata.name}')
BCRYPT_HASH=$(docker exec -i "${CLUSTER_NODE}" kubectl exec -n argocd "${ARGOCD_POD}" -- argocd account bcrypt --password "${TARGET_PASSWORD}" | tr -d '\r\n')

docker exec -i "${CLUSTER_NODE}" kubectl patch secret argocd-secret -n argocd \
  -p '{"stringData": {
         "admin.password": "'"${BCRYPT_HASH}"'",
         "admin.passwordMtime": "'$(date -u +%FT%TZ)'"
       }}'

docker exec -i "${CLUSTER_NODE}" kubectl delete secret argocd-initial-admin-secret -n argocd --ignore-not-found

log_info "Argo CD deployment and password setup pipeline completed."