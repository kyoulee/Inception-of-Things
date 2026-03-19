#!/bin/bash

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

# Loop until the file exists or the maximum retries are reached
MAX_RETRIES=60
RETRY_COUNT=0
WAIT_SECONDS=3
KEY_FILE="/v_ssh/server_id_rsa.pub"

echo "Waiting for Master's public key..."

while [ ! -f "$KEY_FILE" ]; do
    echo "  (Attempt $RETRY_COUNT/$MAX_RETRIES): Key not ready yet. Retrying in 2s..."
    if [ "$RETRY_COUNT" -ge "$MAX_RETRIES" ]; then
        echo "❌ Timeout reached: Master's key not found. Exiting..."
        exit 1
    fi
    RETRY_COUNT=$((RETRY_COUNT + 1))
    sleep $WAIT_SECONDS
done

# Register the Master's public key into authorized_keys
cat $VAGRANT_SSH_PATH/server_id_rsa.pub >> /home/vagrant/.ssh/authorized_keys
echo "Master's public key registered successfully."

# Set strict permissions for the authorized_keys file
chmod 600 /home/vagrant/.ssh/authorized_keys
chown vagrant:vagrant /home/vagrant/.ssh/authorized_keys

echo "✅ Provisioning complete."