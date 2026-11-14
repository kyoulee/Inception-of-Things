#!/bin/bash
#
# Installs Docker engine and configures the daemon.
#
# This script ensures that Docker is downloaded, installed, and enabled as a 
# systemd service. It also assigns the current user to the 'docker' group 
# and performs a health check to verify that the terminal session has acquired 
# the necessary socket permissions without requiring sudo.
#
# Usage:
#   ./install_docker.sh

set -euo pipefail
source "$(dirname "$0")/libs/utils.sh"

readonly DOCKER_URL="https://get.docker.com/"
readonly CURRENT_USER="${USER:-$(whoami)}"

log_info "Checking Docker installation status..."
if command -v docker >/dev/null 2>&1; then
  log_info "Docker is already installed. (Skipping installation)"
else
  log_info "Downloading and installing Docker..."
  curl -fsSL -o get-docker.sh "${DOCKER_URL}"
  chmod +x ./get-docker.sh
  ./get-docker.sh
  rm -f ./get-docker.sh
fi

if ! systemctl is-active --quiet docker; then
  log_info "Starting and enabling Docker daemon..."
  sudo systemctl enable --now docker
fi

if ! groups "${CURRENT_USER}" | grep -q '\bdocker\b'; then
  log_info "Adding user (${CURRENT_USER}) to the docker group..."
  sudo usermod -aG docker "${CURRENT_USER}"
fi

if ! docker info >/dev/null 2>&1; then
  log_error "Docker group permissions are not applied to the current shell session."
  log_error "Safely aborting script. Run the following commands manually to refresh the session, then re-run the script."
  echo ""
  echo -e "\e[33m  newgrp docker\e[0m"
  echo -e "\e[33m  ./run_all.sh\e[0m"
  echo ""
  exit 1
fi

log_info "Docker daemon is running and permissions are secured. (Health Check PASS)"