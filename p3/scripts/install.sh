#!/bin/bash
# Install docker, kubectl, k3d and the argocd CLI on Ubuntu. Run with sudo.
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "run as root: sudo $0"
    exit 1
fi

apt-get update
apt-get install -y curl ca-certificates

if ! command -v docker >/dev/null; then
    curl -fsSL https://get.docker.com | sh
fi
if [ -n "${SUDO_USER:-}" ]; then
    usermod -aG docker "$SUDO_USER"
fi

if ! command -v kubectl >/dev/null; then
    KUBECTL_VERSION="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
    curl -fsSL -o /usr/local/bin/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
    chmod +x /usr/local/bin/kubectl
fi

if ! command -v k3d >/dev/null; then
    curl -fsSL https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
fi

if ! command -v argocd >/dev/null; then
    curl -fsSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
    chmod +x /usr/local/bin/argocd
fi

echo "done. log out and in again if you were just added to the docker group."
