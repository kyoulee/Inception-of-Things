#!/bin/bash
# Create a k3d cluster, install Argo CD and let it deploy the app into "dev".
set -euo pipefail

CLUSTER="${CLUSTER:-iot}"
ARGOCD_VERSION="${ARGOCD_VERSION:-v2.14.11}"
CONFS_DIR="$(cd "$(dirname "$0")/../confs" && pwd)"
export KUBECONFIG="$(cd "$(dirname "$0")/.." && pwd)/.kubeconfig"

if ! k3d cluster list "$CLUSTER" >/dev/null 2>&1; then
    echo "creating k3d cluster $CLUSTER"
    # 8080 -> traefik (Argo CD UI), 8888 -> app (LoadBalancer service in dev)
    k3d cluster create "$CLUSTER" \
        -p "8080:80@loadbalancer" \
        -p "8888:8888@loadbalancer" \
        --kubeconfig-update-default=false --kubeconfig-switch-context=false
fi
k3d kubeconfig get "$CLUSTER" > "$KUBECONFIG"

# also merge into ~/.kube/config and switch to this cluster (KUBECONFIG above
# points at the local file, so name the default one explicitly)
mkdir -p "$HOME/.kube"
KUBECONFIG="$HOME/.kube/config" k3d kubeconfig merge "$CLUSTER" \
    --kubeconfig-merge-default --kubeconfig-switch-context >/dev/null

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace dev --dry-run=client -o yaml | kubectl apply -f -

echo "installing Argo CD $ARGOCD_VERSION"
kubectl apply -n argocd --server-side --force-conflicts \
    -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"
kubectl wait --for=condition=established --timeout=120s crd/applications.argoproj.io

# serve the UI over plain http behind traefik
kubectl -n argocd patch configmap argocd-cmd-params-cm --type merge -p '{"data":{"server.insecure":"true"}}'
kubectl -n argocd rollout restart deployment argocd-server
kubectl -n argocd rollout status deployment argocd-server --timeout=300s
kubectl -n argocd rollout status deployment argocd-repo-server --timeout=300s
kubectl -n argocd rollout status statefulset argocd-application-controller --timeout=300s

kubectl apply -f "$CONFS_DIR/argocd-ingress.yaml"
kubectl apply -f "$CONFS_DIR/application.yaml"

echo "waiting for the application to sync"
kubectl -n argocd wait --for=jsonpath='{.status.sync.status}'=Synced application/playground --timeout=300s
kubectl -n dev rollout status deployment --timeout=300s

echo
kubectl get ns
kubectl get pods -n dev
echo
echo "app:     curl http://localhost:8888/"
echo "argocd:  http://localhost:8080  (user: admin)"
echo "pwd:     KUBECONFIG=$KUBECONFIG kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
