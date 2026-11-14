#!/bin/bash
#
# Main orchestrator for the infrastructure deployment pipeline.
#
# Usage:
#   ./run_all.sh

set -euo pipefail
source "$(dirname "$0")/libs/utils.sh"

log_info "Starting infrastructure configuration pipeline..."

bash "$(dirname "$0")/install_docker.sh"
bash "$(dirname "$0")/install_k3d.sh"
bash "$(dirname "$0")/install_helm.sh"
bash "$(dirname "$0")/create_cluster.sh"
bash "$(dirname "$0")/deploy_helm.sh"

log_info "All configuration pipelines completed successfully."