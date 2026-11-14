#!/bin/bash
#
# Main orchestrator for the infrastructure deployment pipeline.
#
# This script sequentially executes the installation and configuration scripts
# to establish the Docker and k3d environment, create the cluster, and deploy
# Argo CD. It ensures that the execution stops immediately if any step fails.
#
# Usage:
#   ./run_all.sh

set -euo pipefail
source "$(dirname "$0")/libs/utils.sh"

log_info "Starting infrastructure configuration pipeline..."

bash "$(dirname "$0")/install_docker.sh"
bash "$(dirname "$0")/install_k3d.sh"
bash "$(dirname "$0")/create_cluster.sh"
bash "$(dirname "$0")/deploy_argocd.sh"

log_info "All configuration pipelines completed successfully."