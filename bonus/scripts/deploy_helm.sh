#!/bin/bash
#
# Deploys GitLab via Helm to the target k3d cluster.
#
# [Description]
# This script extracts the cluster name dynamically from the k3d configuration 
# file to ensure a Single Source of Truth. It identifies the corresponding 
# Docker container node and ensures the GitLab Helm chart is deployed idempotently. 
# It also pre-creates the target namespace and injects the initial root password 
# secret before Helm execution. Finally, it performs a health check by waiting 
# for the essential GitLab pods to become ready.
#
# [Execution Flow & Rules]
# 1. Base State Check: Verify dependencies (k3d, helm, docker) and config files.
# 2. State Check (Cluster): Resolve target node dynamically and verify status.
# 3. State Check (Helm Repo): Verify and add GitLab chart repository.
# 4. State Preparation (Namespace): Create the target namespace if it is missing.
# 5. State Modification (Secret): Inject the root password secret idempotently.
# 6. State Modification (Helm): Deploy GitLab if not already deployed.
# 7. Verification: Verify Helm release status and wait for pod readiness.
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
readonly SECRET_NAME="gitlab-root-password"
readonly GITLAB_PASSWORD="password@123"

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

log_info "Evaluating current state of the namespace '${NAMESPACE}'..."
if ! docker exec -i "${CLUSTER_NODE}" kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
  log_info "Namespace not found. Creating namespace '${NAMESPACE}'..."
  if ! docker exec -i "${CLUSTER_NODE}" kubectl create namespace "${NAMESPACE}"; then
    log_error "State modification failed: Unable to create namespace '${NAMESPACE}'."
    exit 1
  fi
fi

log_info "Evaluating current state of the GitLab root password secret..."
if docker exec -i "${CLUSTER_NODE}" kubectl get secret "${SECRET_NAME}" -n "${NAMESPACE}" >/dev/null 2>&1; then
  log_info "State intact: Secret '${SECRET_NAME}' already exists. Skipping creation."
else
  log_info "State modification: Secret not found. Injecting '${SECRET_NAME}'..."
  if ! docker exec -i "${CLUSTER_NODE}" sh -c "kubectl create secret generic '${SECRET_NAME}' --from-literal=password='${GITLAB_PASSWORD}' -n '${NAMESPACE}' --dry-run=client -o yaml | kubectl apply -f -"; then
    log_error "State modification failed: Unable to create or update the secret."
    exit 1
  fi
fi

log_info "Launching event monitoring popup window..."
xterm -title "GitLab Events" -e "docker exec -it ${CLUSTER_NODE} kubectl get events -n gitlab -w" &
POPUP_PID=$!

sleep 1

log_info "Deploying GitLab with 20m timeout (Silent wait)..."

log_info "Checking GitLab release status..."
if helm status "${RELEASE_NAME}" -n "${NAMESPACE}" >/dev/null 2>&1; then
  log_info "GitLab release ('${RELEASE_NAME}') is already deployed. (upgrade helm)"
  helm upgrade "${RELEASE_NAME}" "${CHART_NAME}" \
    --version "${CHART_VERSION}" \
    --namespace "${NAMESPACE}" \
    -f "${VALUES_FILE}" \
    --wait \
    --timeout 20m
else
  log_info "Deploying GitLab (Version: ${CHART_VERSION}). This process may take several minutes..."
  helm install "${RELEASE_NAME}" "${CHART_NAME}" \
    --version "${CHART_VERSION}" \
    --namespace "${NAMESPACE}" \
    -f "${VALUES_FILE}" \
    --wait \
    --timeout 20m 
fi

log_info "Deployment complete. Closing monitoring popup window..."
kill -9 "${POPUP_PID}" 2>/dev/null || true

log_info "Waiting for essential GitLab pods to become ready (up to 15 minutes)..."
if docker exec -i "${CLUSTER_NODE}" kubectl wait --namespace "${NAMESPACE}" --for=condition=ready pod --selector='!job-name' --timeout=900s >/dev/null 2>&1; then  if helm status "${RELEASE_NAME}" -n "${NAMESPACE}" | grep -i -q "STATUS: deployed"; then
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

if helm status "${RELEASE_NAME}" -n "${NAMESPACE}" | grep -i -q "STATUS: deployed"; then
  log_info "GitLab Helm deployment completed successfully. (Helm Status PASS)"
else
  log_error "GitLab deployment failed or is in an invalid state."
  exit 1
fi