#!/bin/bash

# Wait for the server to be reachable via network.
#
# Arguments:
#   $1: The target IP address (e.g., 192.168.56.110)
#   $2: The port number to check (e.g., 6443)
#   $3: Maximum number of retries (optional, default: 20)
# Returns:
#   0 if the server is ready, 1 if timeout occurs.
wait_for_server() {
    local ip=$1
    local port=$2
    local max_retries=${3:-20}
    local wait_seconds=${4:-3}
    local retry_count=0

    echo "Waiting for Master Server ($ip:$port)..."

    while ! nc -z -w 1 "$ip" "$port"; do
        retry_count=$((retry_count + 1))
        echo "Retrying... ($retry_count/$max_retries) - Master is not ready yet."
        
        if [ $retry_count -ge $max_retries ]; then
            echo "❌ Error: Master Server did not respond after $((max_retries * wait_seconds)) seconds."
            return 1
        fi
        sleep $wait_seconds
    done

    echo "✅ Master Server is ready!"
    return 0
}

# Load environment variables from a .env file.
#
# This function exports all variables defined in the specified file
# so they are available to the current shell and sub-processes.
#
# Arguments:
#   $1: Path to the .env file (default: /vagrant/.env)
# Returns:
#   0 if success, 1 if file not found.
load_env() {
    local env_file="${1:-/vagrant/.env}"

    if [[ -f "$env_file" ]]; then
        echo "✅ Loading environment variables from $env_file"
        set -a
        # shellcheck disable=SC1090
        source "$env_file"
        set +a
    else
        echo "❌ Error: .env file not found at $env_file"
        return 1
    fi
    return 0
}
