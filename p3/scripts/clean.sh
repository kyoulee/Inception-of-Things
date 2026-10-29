#!/bin/bash
set -euo pipefail
CLUSTER="${CLUSTER:-iot}"
k3d cluster delete "$CLUSTER"
rm -f "$(cd "$(dirname "$0")/.." && pwd)/.kubeconfig"
