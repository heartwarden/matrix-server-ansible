#!/bin/bash
# Quick deployment script for Matrix server setup
# This script helps users deploy on their Debian 12 server

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date +'%H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[WARNING] $1${NC}"; }
error() { echo -e "${RED}[ERROR] $1${NC}"; }
info() { echo -e "${BLUE}[INFO] $1${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if we're on Debian 12
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [[ "$ID" != "debian" ]] || [[ "$VERSION_ID" != "12" ]]; then
        warn "This script is designed for Debian 12. Current OS: $ID $VERSION_ID"
        echo "Continue anyway? (y/N)"
        read -r response
        if [[ "$response" != "y" && "$response" != "Y" ]]; then
            exit 1
        fi
    fi
else
    warn "Cannot detect OS version. Continuing anyway..."
fi

# Install dependencies
log "Installing required packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y python3 python3-pip python3-venv whiptail openssl openssh-client git curl

# Install Ansible
log "Installing Ansible..."
pip3 install --break-system-packages ansible-core==2.15.8

# Install required Ansible collections
log "Installing required Ansible collections..."
ansible-galaxy collection install ansible.posix community.crypto --force

# Set working directory
cd "$SCRIPT_DIR"

# Check if configuration exists
if [ -d "server-configs" ] && [ "$(ls -A server-configs)" ]; then
    info "Found existing configurations:"
    ls -la server-configs/
    echo
    echo "1) Use existing configuration"
    echo "2) Create new configuration"
    echo "3) Exit"
    read -p "Choose option (1-3): " choice

    case $choice in
        1)
            echo "Select configuration to deploy:"
            select config_dir in server-configs/*-deploy.sh; do
                if [ -n "$config_dir" ]; then
                    log "Deploying with $config_dir"
                    chmod +x "$config_dir"
                    "$config_dir"
                    exit 0
                fi
            done
            ;;
        2)
            log "Creating new configuration..."
            ;;
        3)
            exit 0
            ;;
        *)
            error "Invalid choice"
            exit 1
            ;;
    esac
fi

# Run configuration wizard
log "Running Matrix server configuration wizard..."
chmod +x scripts/configure-server.sh
scripts/configure-server.sh

# Find the latest deployment script
latest_deploy=$(find server-configs -name "*-deploy.sh" -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)

if [ -n "$latest_deploy" ]; then
    echo
    echo "Configuration complete! To deploy:"
    echo "  chmod +x $latest_deploy"
    echo "  $latest_deploy"
    echo
    echo "Or run this script again to use the existing configuration."
else
    error "No deployment script found. Configuration may have failed."
    exit 1
fi