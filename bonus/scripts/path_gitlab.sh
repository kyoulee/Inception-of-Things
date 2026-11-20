#!/bin/bash
#
# Provisions a GitLab user, configures SSL trust, and pushes the local repository.
#
# [Description]
# This script transfers a local Ruby provisioning script into the nested GitLab
# toolbox pod within the k3d cluster and executes it to ensure the target user 
# and namespace exist. It then extracts the self-signed SSL certificate from 
# the GitLab ingress, configures local Git trust, and idempotently sets the 
# remote URL. Finally, it pushes the codebase using an inline credential helper 
# to bypass interactive prompts.
#
# [Execution Flow & Rules]
# 1. Base State Check: Verify essential dependencies (docker, openssl, git).
# 2. Base State Check: Verify the existence of the local Ruby script.
# 3. State Check (Pod): Resolve the target toolbox pod name dynamically.
# 4. State Modification (Transfer): Copy the Ruby script to the node, then to the pod.
# 5. State Modification (Execution): Run the Ruby script via gitlab-rails runner.
# 6. State Modification (SSL): Extract the certificate and apply Git SSL trust.
# 7. State Modification (Remote): Add or update the Git remote URL idempotently.
# 8. State Modification (Push): Push the repository using inline credentials.
#
# Usage:
#   ./execute_and_push.sh

set -euo pipefail
source "$(dirname "$0")/libs/utils.sh"

readonly GIT_ROOT=$(git rev-parse --show-toplevel)
readonly K3D_CONFIG="./confs/k3d/config.yaml"
readonly HELM_VALUES="./confs/helm/values.yaml"
readonly NAMESPACE="gitlab"
readonly LOCAL_FILE="./confs/gitlab/create_gitlab_user.rb"
readonly TARGET_FILE="/tmp/create_gitlab_user.rb"
readonly REMOTE_REPO="kyoulee/Inception-of-Things.git"
readonly CERT_FILE="${GIT_ROOT}/.git/gitlab-cert.pem"
readonly GIT_USER="kyoulee"
readonly GIT_PASS="password@1234"

log_info "Verifying dependencies (docker, openssl, git)..."
if ! command -v docker >/dev/null 2>&1; then
  log_error "docker command not found."
  exit 1
fi
if ! command -v openssl >/dev/null 2>&1; then
  log_error "openssl command not found."
  exit 1
fi
if ! command -v git >/dev/null 2>&1; then
  log_error "git command not found."
  exit 1
fi

log_info "Verifying target local file..."
if [[ ! -f "${LOCAL_FILE}" ]]; then
  log_error "Ruby provisioning script not found: ${LOCAL_FILE}"
  exit 1
fi


readonly DOMAIN=$(grep -E '^\s*domain:' "${HELM_VALUES}" | head -n 1 | awk '{print $2}' | tr -d '""'"''")
readonly GITLAB_HOST="gitlab.${DOMAIN}"

if [[ -z "${GITLAB_HOST}" ]]; then
  log_error "Failed to parse the GitLab host from the configuration file (${HELM_VALUES})."
  exit 1
fi

readonly GITLAB_URL="https://${GITLAB_HOST}"


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


log_info "Evaluating current state of the toolbox pod in namespace '${NAMESPACE}'..."
TARGET_POD=$(docker exec -i "${CLUSTER_NODE}" kubectl get pod -n "${NAMESPACE}" -l app=toolbox -o jsonpath='{.items[0].metadata.name}' || true)
if [[ -z "${TARGET_POD}" ]]; then
  log_error "Failed to resolve the target toolbox pod. Is GitLab running?"
  exit 1
fi

log_info "State modification: Transferring Ruby script to the node and toolbox pod..."
if ! docker cp "${LOCAL_FILE}" "${CLUSTER_NODE}:${TARGET_FILE}"; then
  log_error "Failed to copy file to cluster node: ${CLUSTER_NODE}"
  exit 1
fi

if ! docker exec -i "${CLUSTER_NODE}" kubectl cp "${TARGET_FILE}" "${NAMESPACE}/${TARGET_POD}:${TARGET_FILE}"; then
  log_error "Failed to copy file from cluster node to toolbox pod: ${TARGET_POD}"
  exit 1
fi

log_info "State modification: Executing Ruby provisioning script via gitlab-rails runner..."
if ! docker exec -i "${CLUSTER_NODE}" kubectl exec -i "deployment/gitlab-toolbox" -n "${NAMESPACE}" -- gitlab-rails runner "${TARGET_FILE}"; then
  log_error "Failed to execute gitlab-rails runner. Please check the Ruby script output."
  exit 1
fi

log_info "State modification: Extracting SSL certificate from ${GITLAB_HOST}..."
if ! echo -n | openssl s_client -showcerts -connect "${GITLAB_HOST}:443" 2>/dev/null | openssl x509 -outform PEM > "${CERT_FILE}"; then
  log_error "Failed to extract SSL certificate from the server."
  exit 1
fi

if [ ! -s "${CERT_FILE}" ]; then
  log_error "Verification failed: Certificate file '${CERT_FILE}' is empty or was not created."
  exit 1
fi

if ! openssl x509 -in "${CERT_FILE}" -noout > /dev/null 2>&1; then
  log_error "Verification failed: The extracted file is not a valid PEM certificate."
  exit 1
fi

log_info "State modification: Configuring Git SSL trust..."
if ! git config http.sslCAInfo "${CERT_FILE}"; then
  log_error "Failed to configure Git to trust the extracted certificate."
  exit 1
fi
git config http.sslVerify false

log_info "Evaluating current state of Git remote 'gitlab'..."
if ! git remote get-url gitlab >/dev/null 2>&1; then
  log_info "State modification: Adding Git remote 'gitlab'..."
  git remote add gitlab "${GITLAB_URL}/${REMOTE_REPO}"
else
  log_info "State modification: Updating Git remote 'gitlab'..."
  git remote set-url gitlab "${GITLAB_URL}/${REMOTE_REPO}"
fi

log_info "State modification: Pushing codebase to GitLab..."
if git -c credential.helper="!f() { echo \"username=${GIT_USER}\"; echo \"password=${GIT_PASS}\"; }; f" push --set-upstream gitlab main; then
  log_info "Git push completed successfully. (End-to-End Pipeline PASS)"
else
  log_error "Git push failed."
  exit 1
fi

