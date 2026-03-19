#!/bin/bash
# env file link
ENV_FILE="/vagrant/.env"

echo "Start setting env from $ENV_FILE"

# env load
if [ -f "$ENV_FILE" ]; then
    set -a
    source "$ENV_FILE"
    set +a
else
    echo "Error: .env file not found at $ENV_FILE"
    exit 1
fi

# k3s config

SERVER_CONFIG_SRC="/vagrant/config.yaml"
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

echo "Setting up K3s Master with IP: $K3S_MASTER_IP"
curl -sfL https://get.k3s.io | sh -
echo "K3s is up!"

# status log

systemctl status k3s | grep -E "Active:|Loaded:|Main PID: "

echo "End Server"
