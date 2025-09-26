#!/bin/bash
# SSH Access Verification and Hardening Script
# Use this to safely complete SSH hardening after deployment

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

# Configuration
ADMIN_USER="zerokaine"
SSH_PORT="2222"
SERVER_IP=""

show_banner() {
    echo -e "${BLUE}"
    cat << 'EOF'
    🔐 SSH Access Verification & Hardening
    =====================================
EOF
    echo -e "${NC}"
}

check_current_ssh() {
    info "Checking current SSH configuration..."

    # Check if we're currently connected as root
    if [ "$(whoami)" = "root" ]; then
        warn "You are currently logged in as root"
        echo "This script will help you verify zerokaine access before disabling root login"
    else
        info "You are logged in as: $(whoami)"
    fi

    # Check SSH configuration
    echo
    info "Current SSH configuration:"
    grep -E "^Port|^PermitRootLogin|^PasswordAuthentication|^AllowUsers" /etc/ssh/sshd_config || true

    # Check SSH service status
    echo
    info "SSH service status:"
    systemctl status ssh --no-pager -l | head -5

    # Check what ports SSH is listening on
    echo
    info "SSH listening ports:"
    netstat -tlnp | grep sshd || true
}

test_zerokaine_access() {
    if [ -z "$SERVER_IP" ]; then
        SERVER_IP=$(hostname -I | awk '{print $1}')
        info "Auto-detected server IP: $SERVER_IP"
    fi

    info "Testing zerokaine SSH access..."
    echo
    echo "Please open a NEW terminal window and test this command:"
    echo -e "${YELLOW}ssh -p $SSH_PORT $ADMIN_USER@$SERVER_IP${NC}"
    echo
    echo "Do NOT close this terminal until you confirm the test works!"
    echo
    read -p "Did the SSH test connection work? (yes/no): " ssh_test_result

    if [[ "$ssh_test_result" =~ ^[Yy]([Ee][Ss])?$ ]]; then
        log "✅ SSH test successful!"
        return 0
    else
        error "❌ SSH test failed!"
        return 1
    fi
}

apply_ssh_hardening() {
    warn "Applying final SSH hardening..."
    echo
    echo "This will:"
    echo "1. Disable root login"
    echo "2. Disable password authentication (key-only)"
    echo "3. Restrict access to zerokaine user only"
    echo "4. Lock the root account"
    echo
    read -p "Are you sure you want to continue? (yes/no): " confirm

    if [[ ! "$confirm" =~ ^[Yy]([Ee][Ss])?$ ]]; then
        warn "SSH hardening cancelled"
        return 1
    fi

    # Create hardened SSH config
    info "Creating hardened SSH configuration..."

    # Backup current config
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup.$(date +%s)

    # Apply hardening
    sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
    sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
    sed -i 's/^AllowUsers.*/AllowUsers zerokaine/' /etc/ssh/sshd_config

    # Test configuration
    info "Testing SSH configuration..."
    if sshd -t; then
        log "✅ SSH configuration is valid"
    else
        error "❌ SSH configuration has errors!"
        return 1
    fi

    # Restart SSH service
    info "Restarting SSH service..."
    systemctl restart ssh

    # Lock root account
    info "Locking root account..."
    passwd -l root

    log "✅ SSH hardening completed successfully!"

    echo
    warn "IMPORTANT: From now on, you can only connect as:"
    echo -e "${YELLOW}ssh -p $SSH_PORT $ADMIN_USER@$SERVER_IP${NC}"
    echo
    warn "Root login is now disabled!"
}

show_final_instructions() {
    echo
    log "🎉 SSH Security Hardening Complete!"
    echo
    info "Security status:"
    echo "✅ Root login: DISABLED"
    echo "✅ Password authentication: DISABLED"
    echo "✅ Key-only authentication: ENABLED"
    echo "✅ Access restricted to: $ADMIN_USER"
    echo "✅ Root account: LOCKED"
    echo
    info "To connect to this server:"
    echo -e "${YELLOW}ssh -p $SSH_PORT $ADMIN_USER@$SERVER_IP${NC}"
    echo
    info "Management commands available:"
    echo "- matrix-status: Check Matrix server status"
    echo "- matrix-logs: View Matrix server logs"
    echo "- matrix-restart: Restart Matrix services"
    echo "- matrix-backup: Create system backup"
    echo "- system-info: Display system information"
}

rollback_ssh_config() {
    warn "Rolling back SSH configuration..."

    local backup_file=$(ls -t /etc/ssh/sshd_config.backup.* 2>/dev/null | head -1)
    if [ -n "$backup_file" ]; then
        cp "$backup_file" /etc/ssh/sshd_config
        systemctl restart ssh
        log "SSH configuration rolled back"
    else
        error "No backup file found!"
    fi
}

main() {
    show_banner

    # Check if script is run as root
    if [ "$EUID" -ne 0 ]; then
        error "This script must be run as root"
        echo "Please run: sudo $0"
        exit 1
    fi

    echo "This script will help you safely complete SSH hardening."
    echo "It will verify that zerokaine user access works before disabling root login."
    echo
    read -p "Continue? (yes/no): " continue_choice

    if [[ ! "$continue_choice" =~ ^[Yy]([Ee][Ss])?$ ]]; then
        info "Exiting..."
        exit 0
    fi

    check_current_ssh
    echo

    if test_zerokaine_access; then
        echo
        if apply_ssh_hardening; then
            show_final_instructions
        else
            error "SSH hardening failed!"
            read -p "Do you want to rollback the SSH configuration? (yes/no): " rollback
            if [[ "$rollback" =~ ^[Yy]([Ee][Ss])?$ ]]; then
                rollback_ssh_config
            fi
            exit 1
        fi
    else
        echo
        error "Cannot proceed with SSH hardening due to failed access test"
        echo
        info "Troubleshooting steps:"
        echo "1. Check that zerokaine user exists: id zerokaine"
        echo "2. Check SSH keys: ls -la /home/zerokaine/.ssh/"
        echo "3. Check SSH logs: journalctl -u ssh -f"
        echo "4. Test from another terminal: ssh -p $SSH_PORT zerokaine@$SERVER_IP"
        exit 1
    fi
}

# Handle Ctrl+C gracefully
trap 'echo; warn "Script interrupted"; exit 1' INT

main "$@"