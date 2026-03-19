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

# k3s confing

WORKER_CONFIG_SRC="/vagrant/config.yaml"
WORKER_CONFIG_DEST="/etc/rancher/k3s/config.yaml"

echo "Checking for config file at $WORKER_CONFIG_SRC..."

if [ -f "$WORKER_CONFIG_SRC" ]; then
    echo "✅ Config file found. Copying to $CONFIG_DEST..."
    mkdir -p /etc/rancher/k3s

    # env setting on k3s yaml file
    echo "🔄 Substituting variables in config..."
    envsubst < "$WORKER_CONFIG_SRC" | tee "$WORKER_CONFIG_DEST" > /dev/null

else
    echo "❌ Error: $WORKER_CONFIG_SRC not found! Cannot proceed with K3s setup."
    exit 1
fi

# wait server

MAX_RETRIES=20
RETRY_COUNT=0
WAIT_SECONDS=3

echo "Waiting for Master Server ($K3S_MASTER_IP:$K3S_PORT)..."

while ! nc -z -w 1 "$K3S_MASTER_IP" "$K3S_PORT" ; do
    RETRY_COUNT=$((RETRY_COUNT + 1))
    
    echo "Retrying... ($RETRY_COUNT/$MAX_RETRIES) - Master is not ready yet."
    
    if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
        echo "❌ Error: Master Server did not respond after $((MAX_RETRIES * WAIT_SECONDS)) seconds."
        echo "Please check if the Master VM is running and K3s service is started."
        exit 1
    fi
    
    sleep $WAIT_SECONDS
done

echo "🚀 Master Server is up! Proceeding with installation..."

# install & start k3s 

echo "Setting up K3s Worker with IP: $K3S_WORKER_IP"
curl -sfL https://get.k3s.io | sh -s - agent
echo "K3s Server is up! Installing Agent..."

# status log

systemctl status k3s-agent | grep -E 'Active:|Loaded:|Main PID:'

echo "End ServerWorker"