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

# Generate RSA key pair

if [ ! -f /home/vagrant/.ssh/id_rsa ]; then
    echo "🔑 Generating Server SSH Key..."
    ssh-keygen -t rsa -b 2048 -f /home/vagrant/.ssh/id_rsa -N ""
    chown vagrant:vagrant /home/vagrant/.ssh/id_rsa*
fi

# Export public key to the shared volume for Worker nodes

cp /home/vagrant/.ssh/id_rsa.pub $VAGRANT_SSH_PATH/server_id_rsa.pub
echo "Public key exported to $VAGRANT_SSH_PATH/server_id_rsa.pub"