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

echo "🚀 Deploying applications using $manifest..."
k3s kubectl apply -f "$K3S_CLUSTER_DIR" -R 

# check pods

wait_for_deployments() {
    local timeout="180s"
    local deployments=("$@")
    local failed_count=0

    if [ ${#deployments[@]} -eq 0 ]; then
        echo "⚠️ Warning: No deployments specified."
        return 0
    fi

    echo "⏳ Checking rollout status for: ${deployments[*]}"

    for dep in "${deployments[@]}"; do
        echo "🔄 Checking deployment/$dep..."
        if ! k3s kubectl rollout status deployment/"$dep" --timeout="$timeout"; then
            echo "❌ ERROR: Deployment/$dep failed to roll out."
            k3s kubectl describe deployment/"$dep" | grep -i "Events" -A 5
            ((failed_count++))
        else
            echo "✅ Deployment/$dep is READY."
        fi
    done

    if [ "$failed_count" -gt 0 ]; then
        echo "🚨 Total $failed_count deployment(s) failed."
        return 1
    else
        echo "✨ All specified deployments are successfully rolled out!"
        return 0
    fi
}

wait_for_deployments app-one app-two app-three

echo "🎉 All apps are ready to serve traffic!"

echo "run k3s kubectl get deployments " 
k3s kubectl get deployments
echo "run k3s kubectl get pods -o wide" 
k3s kubectl get pods -o wide
echo "run k3s kubectl get all -n kube-system"
k3s kubectl get all -n kube-system

exit 0 
