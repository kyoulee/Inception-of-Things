#!/bin/bash

# import
SCRIPT_DIR="/vagrant/scripts"
source "$SCRIPT_DIR/utils.sh"

load_env "/vagrant/.env" || exit

# k3s config

# if systemctl is-active --quiet k3s; then
#     echo "K3s server is already running. Skipping installation."
#     systemctl status k3s | grep -E "Active:|Loaded:|Main PID: "
#     exit 0
# fi

SERVER_CONFIG_SRC="/vagrant/configs/config.yaml"
SERVER_CONFIG_DEST="/etc/rancher/k3s/config.yaml"

echo "Checking for config file at $SERVER_CONFIG_SRC..."
if [ -f "$SERVER_CONFIG_SRC" ]; then
    echo "✅ Config file found. Copying to $SERVER_CONFIG_DEST..."
    mkdir -p /etc/rancher/k3s

    # env setting on k3s yaml file
    echo "🔄 Substituting variables in config..."
    envsubst < "$SERVER_CONFIG_SRC" | tee "$SERVER_CONFIG_DEST" > /dev/null
else
    echo "❌ Error: $SERVER_CONFIG_SRC not found! Cannot proceed with K3s setup."
    exit 1
fi

# install & start k3s 

echo "Setting up K3s Master with IP: $K3S_SERVER_IP"
curl -sfL https://get.k3s.io | sh -
echo "K3s is up!"

# status log

systemctl status k3s | grep -E "Active:|Loaded:|Main PID: "

echo "End Server"

# k3s deploy pods

wait_for_server "$K3S_SERVER_IP" "$K3S_PORT" || exit 1

if [[ ! -d "$K3S_CLUSTER_DIR" ]]; then
    echo "❌ FATAL: Application directory not found at $K3S_CLUSTER_DIR"
    exit 1
fi

# k3s namespace create

echo "📦 Initializing Namespaces..."
kubectl apply -f "$K3S_CLUSTER_DIR/init-ns.yaml"

echo "⏳ Waiting for all namespaces to become Active..."
kubectl wait --for=jsonpath='{.status.phase}'=Active namespaces --all --timeout=60s

# k3s argo cd create

echo "🛠️ Installing Argo CD components..."
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml --server-side

echo "🔓 Disabling HTTPS redirect (insecure mode)..."
kubectl patch deployment argocd-server -n argocd --type='json' -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--insecure"}]'

echo "🔑 Setting up custom admin password"
#ARGOCD_PWD="password"
ARGOCD_PWD_HASH=$(perl -e 'print crypt($ARGV[0], "\$2b\$10\$" . "kyouleeIsTheBestAdmin1")' -- "${ARGOCD_PWD}")
kubectl -n argocd patch secret argocd-secret \
  -p '{"stringData": {
    "admin.password": "'${ARGOCD_PWD_HASH}'",
    "admin.passwordMtime": "'$(date +%FT%T%Z)'"
  }}'

echo "⚙️ Setting Argo CD"
kubectl apply -f "$K3S_CLUSTER_DIR/argocd" -R --server-side

echo "⏳ Waiting for Argo CD CRDs (applications.argoproj.io) to be established..."
kubectl wait --for condition=established --timeout=90s crd/applications.argoproj.io

# deploying all

echo "🚀 Deploying applications using $manifest..."
k3s kubectl apply -f "$K3S_CLUSTER_DIR/dev" -R --server-side

echo "⏳ Wait for all service is deploy..."

k3s kubectl wait --for=condition=available --timeout=300s deployment --all -A

echo "🎉 All apps are ready to serve traffic!"

echo "run k3s kubectl get deployments " 

echo "📊 --- Cluster Status Summary ---"
echo "[Deployments]"
kubectl get deployments -A
echo ""
echo "[Pods Information]"
kubectl get pods -A -o wide
echo ""
echo "[Kube-System Resources]"
kubectl get all -n kube-system

exit 0 
