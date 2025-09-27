#!/bin/bash
# Matrix Server Secret Generation Script
# Generates all required secrets and creates Ansible Vault files
# Usage: ./scripts/generate-secrets.sh [environment]

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENVIRONMENT="${1:-production}"
VAULT_FILE="$PROJECT_ROOT/inventory/$ENVIRONMENT/group_vars/all/vault.yml"
VAULT_DIR="$(dirname "$VAULT_FILE")"

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Generate secure random string
generate_secret() {
    local length="${1:-32}"
    openssl rand -base64 "$length" | tr -d "=+/" | cut -c1-"$length"
}

# Generate password with special characters
generate_password() {
    local length="${1:-24}"
    # Generate a strong password with mixed case, numbers, and symbols
    env LC_ALL=C tr -dc 'A-Za-z0-9!@#$%^&*()_+-=[]{}|;:,.<>?' < /dev/urandom | head -c "$length"
}

# Check if required tools are available
check_dependencies() {
    log "Checking dependencies..."

    local missing_deps=()

    if ! command -v ansible-vault >/dev/null 2>&1; then
        missing_deps+=("ansible (for ansible-vault)")
    fi

    if ! command -v openssl >/dev/null 2>&1; then
        missing_deps+=("openssl")
    fi

    if [ ${#missing_deps[@]} -ne 0 ]; then
        error "Missing required dependencies:"
        printf '%s\n' "${missing_deps[@]}"
        echo ""
        echo "Install missing dependencies:"
        echo "  macOS: brew install ansible openssl"
        echo "  Ubuntu/Debian: sudo apt install ansible openssl"
        exit 1
    fi

    log "✓ All dependencies available"
}

# Prompt for vault password
get_vault_password() {
    echo ""
    info "Ansible Vault will encrypt your secrets securely."
    echo "Choose a strong vault password and store it safely!"
    echo ""

    while true; do
        echo -n "Enter vault password: "
        read -s vault_password
        echo ""
        echo -n "Confirm vault password: "
        read -s vault_password_confirm
        echo ""

        if [ "$vault_password" = "$vault_password_confirm" ]; then
            if [ ${#vault_password} -lt 8 ]; then
                warn "Password should be at least 8 characters long"
                continue
            fi
            break
        else
            warn "Passwords don't match. Please try again."
        fi
    done

    # Store vault password for this session
    export ANSIBLE_VAULT_PASSWORD_FILE="/tmp/vault_pass_$$"
    echo "$vault_password" > "$ANSIBLE_VAULT_PASSWORD_FILE"
    chmod 600 "$ANSIBLE_VAULT_PASSWORD_FILE"

    # Cleanup function
    cleanup_vault_password() {
        if [ -f "$ANSIBLE_VAULT_PASSWORD_FILE" ]; then
            rm -f "$ANSIBLE_VAULT_PASSWORD_FILE"
        fi
    }
    trap cleanup_vault_password EXIT
}

# Create directory structure
create_directories() {
    log "Creating directory structure..."
    mkdir -p "$VAULT_DIR"
    log "✓ Created $VAULT_DIR"
}

# Generate all required secrets
generate_all_secrets() {
    log "Generating secure secrets..."

    # Matrix database
    MATRIX_DB_PASSWORD=$(generate_password 32)

    # Matrix application secrets
    FORM_SECRET=$(generate_secret 64)
    MACAROON_SECRET=$(generate_secret 64)
    REGISTRATION_SECRET=$(generate_secret 32)

    # Coturn (TURN server)
    COTURN_SECRET=$(generate_secret 32)

    # Admin user (will be prompted)
    echo ""
    info "Setting up initial admin user..."
    echo -n "Enter admin username (default: admin): "
    read admin_username
    admin_username="${admin_username:-admin}"

    echo -n "Enter admin password (leave empty to generate): "
    read -s admin_password
    echo ""

    if [ -z "$admin_password" ]; then
        admin_password=$(generate_password 16)
        info "Generated admin password: $admin_password"
        echo "Please save this password securely!"
    fi

    # SSL email
    echo -n "Enter SSL/admin email: "
    read ssl_email

    while [ -z "$ssl_email" ]; do
        warn "SSL email is required for Let's Encrypt certificates"
        echo -n "Enter SSL/admin email: "
        read ssl_email
    done

    log "✓ All secrets generated"
}

# Create vault file content
create_vault_content() {
    log "Creating vault file content..."

    cat > "$VAULT_FILE.tmp" <<EOF
---
# Matrix Server Secrets
# Generated on $(date '+%Y-%m-%d %H:%M:%S')
#
# IMPORTANT: This file contains sensitive information and is encrypted with Ansible Vault
# To edit: ansible-vault edit $VAULT_FILE
# To view: ansible-vault view $VAULT_FILE

# PostgreSQL Database
vault_matrix_database_password: "$MATRIX_DB_PASSWORD"

# Matrix Synapse Secrets
vault_form_secret: "$FORM_SECRET"
vault_macaroon_secret_key: "$MACAROON_SECRET"
vault_registration_secret: "$REGISTRATION_SECRET"

# Coturn (TURN server) Secret
vault_coturn_secret: "$COTURN_SECRET"

# Initial Admin User
vault_admin_username: "$admin_username"
vault_admin_password: "$admin_password"

# SSL and Contact Information
vault_ssl_email: "$ssl_email"

# Security Notice:
# - These secrets are randomly generated using cryptographically secure methods
# - Change the vault password regularly and store it securely
# - Never commit unencrypted secrets to version control
# - Rotate these secrets periodically for enhanced security
EOF

    log "✓ Vault content created"
}

# Encrypt vault file
encrypt_vault_file() {
    log "Encrypting vault file with Ansible Vault..."

    if ansible-vault encrypt "$VAULT_FILE.tmp" --output "$VAULT_FILE"; then
        rm -f "$VAULT_FILE.tmp"
        log "✓ Vault file encrypted successfully"
    else
        error "Failed to encrypt vault file"
        rm -f "$VAULT_FILE.tmp"
        exit 1
    fi
}

# Create vault password file template
create_vault_password_template() {
    local vault_pass_file="$PROJECT_ROOT/.vault_pass"

    if [ ! -f "$vault_pass_file" ]; then
        cat > "$vault_pass_file" <<EOF
# Ansible Vault Password File
#
# SECURITY WARNING: This file should contain your vault password
# 1. Add your vault password to this file (single line, no extra characters)
# 2. Set secure permissions: chmod 600 .vault_pass
# 3. Add to .gitignore to prevent accidental commits
#
# Example:
# your_secure_vault_password_here

EOF
        chmod 600 "$vault_pass_file"
        warn "Created $vault_pass_file template"
        warn "Add your vault password to this file and set chmod 600"
    fi
}

# Update gitignore
update_gitignore() {
    local gitignore="$PROJECT_ROOT/.gitignore"

    if [ ! -f "$gitignore" ]; then
        touch "$gitignore"
    fi

    # Add vault-related entries if not present
    local entries=(
        ".vault_pass"
        "*.vault"
        "vault_password*"
        ".ansible_vault_password"
    )

    for entry in "${entries[@]}"; do
        if ! grep -q "^$entry$" "$gitignore" 2>/dev/null; then
            echo "$entry" >> "$gitignore"
        fi
    done

    log "✓ Updated .gitignore with vault security entries"
}

# Display summary
show_summary() {
    echo ""
    log "============================================"
    log "SECRET GENERATION COMPLETED SUCCESSFULLY!"
    log "============================================"
    echo ""
    info "Generated files:"
    echo "  📁 Vault file: $VAULT_FILE"
    echo "  🔒 Encrypted with Ansible Vault"
    echo ""
    info "Generated secrets:"
    echo "  🔑 Matrix database password"
    echo "  🔑 Matrix application secrets (form, macaroon, registration)"
    echo "  🔑 Coturn TURN server secret"
    echo "  👤 Admin user: $admin_username"
    echo "  📧 SSL email: $ssl_email"
    echo ""
    info "Next steps:"
    echo "  1. Save your vault password securely!"
    echo "  2. Run deployment: ansible-playbook -i inventory/$ENVIRONMENT site.yml --ask-vault-pass"
    echo "  3. Or use password file: ansible-playbook -i inventory/$ENVIRONMENT site.yml --vault-password-file .vault_pass"
    echo ""
    info "Vault commands:"
    echo "  📖 View secrets: ansible-vault view $VAULT_FILE"
    echo "  ✏️  Edit secrets: ansible-vault edit $VAULT_FILE"
    echo "  🔓 Decrypt file: ansible-vault decrypt $VAULT_FILE"
    echo ""
    warn "SECURITY REMINDERS:"
    echo "  🔐 Store vault password in a secure password manager"
    echo "  🚫 Never commit .vault_pass or unencrypted secrets to git"
    echo "  🔄 Rotate secrets periodically for enhanced security"
    echo "  📝 Backup your vault password - you cannot recover secrets without it!"
}

# Main execution
main() {
    echo ""
    log "Matrix Server Secret Generation Script"
    log "======================================"
    echo ""

    info "Environment: $ENVIRONMENT"
    info "Vault file: $VAULT_FILE"
    echo ""

    # Check if vault file already exists
    if [ -f "$VAULT_FILE" ]; then
        warn "Vault file already exists: $VAULT_FILE"
        echo -n "Do you want to overwrite it? (y/N): "
        read -r overwrite
        if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
            info "Aborted. Existing vault file preserved."
            exit 0
        fi
    fi

    check_dependencies
    get_vault_password
    create_directories
    generate_all_secrets
    create_vault_content
    encrypt_vault_file
    create_vault_password_template
    update_gitignore
    show_summary
}

# Usage information
usage() {
    echo "Usage: $0 [environment]"
    echo ""
    echo "Generate secure secrets for Matrix server deployment"
    echo ""
    echo "Arguments:"
    echo "  environment    Target environment (default: production)"
    echo "                 Valid options: production, staging"
    echo ""
    echo "Examples:"
    echo "  $0                    # Generate secrets for production"
    echo "  $0 staging           # Generate secrets for staging"
    echo ""
    echo "This script will:"
    echo "  • Generate cryptographically secure secrets"
    echo "  • Create encrypted Ansible Vault file"
    echo "  • Set up proper security configurations"
    echo "  • Update .gitignore for security"
}

# Handle arguments
case "${1:-}" in
    -h|--help)
        usage
        exit 0
        ;;
    production|staging|"")
        main
        ;;
    *)
        error "Invalid environment: $1"
        echo ""
        usage
        exit 1
        ;;
esac