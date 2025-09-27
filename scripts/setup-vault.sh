#!/bin/bash
# Vault Setup and Management Script
# Creates and manages Ansible Vault configurations
# Usage: ./scripts/setup-vault.sh [options]

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENVIRONMENT="production"
ACTION="setup"

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

step() {
    echo -e "${PURPLE}[STEP]${NC} $1"
}

usage() {
    cat << EOF
Vault Setup and Management Script

USAGE:
    $0 [OPTIONS] [ACTION]

ACTIONS:
    setup         Setup vault for environment (default)
    view          View vault contents
    edit          Edit vault contents
    rekey         Change vault password
    validate      Validate vault file
    backup        Backup vault file

OPTIONS:
    -e, --environment ENV     Target environment (production|staging) [default: production]
    -h, --help               Show this help message

EXAMPLES:
    $0                       # Setup vault for production
    $0 -e staging setup      # Setup vault for staging
    $0 view                  # View production vault
    $0 -e staging edit       # Edit staging vault
    $0 backup                # Backup production vault

VAULT MANAGEMENT:
    The script manages vault files at:
    inventory/ENVIRONMENT/group_vars/all/vault.yml

    Vault password files are stored at:
    .vault_pass (main password file)
    .vault_pass_ENVIRONMENT (environment-specific)

EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -e|--environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            setup|view|edit|rekey|validate|backup)
                ACTION="$1"
                shift
                ;;
            *)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

check_dependencies() {
    step "Checking dependencies..."

    local missing_deps=()

    if ! command -v ansible-vault >/dev/null 2>&1; then
        missing_deps+=("ansible")
    fi

    if [ ${#missing_deps[@]} -ne 0 ]; then
        error "Missing required dependencies:"
        printf '%s\n' "${missing_deps[@]}"
        echo ""
        echo "Install missing dependencies:"
        echo "  macOS: brew install ansible"
        echo "  Ubuntu/Debian: sudo apt install ansible"
        exit 1
    fi

    log "✓ All dependencies available"
}

setup_vault() {
    step "Setting up vault for $ENVIRONMENT environment..."

    local vault_file="$PROJECT_ROOT/inventory/$ENVIRONMENT/group_vars/all/vault.yml"
    local vault_dir="$(dirname "$vault_file")"

    # Check if vault already exists
    if [ -f "$vault_file" ]; then
        warn "Vault file already exists: $vault_file"
        echo -n "Do you want to recreate it? (y/N): "
        read -r recreate
        if [[ ! "$recreate" =~ ^[Yy]$ ]]; then
            info "Keeping existing vault file"
            return 0
        fi
    fi

    # Create directory structure
    mkdir -p "$vault_dir"

    # Generate secrets using the dedicated script
    if [ -f "$SCRIPT_DIR/generate-secrets.sh" ]; then
        log "Using generate-secrets.sh for comprehensive setup..."
        "$SCRIPT_DIR/generate-secrets.sh" "$ENVIRONMENT"
    else
        # Fallback: simple vault creation
        create_simple_vault "$vault_file"
    fi

    log "✓ Vault setup completed for $ENVIRONMENT"
}

create_simple_vault() {
    local vault_file="$1"

    info "Creating simple vault file..."

    # Get vault password
    echo -n "Enter vault password: "
    read -s vault_password
    echo ""

    # Create vault content
    cat > "$vault_file.tmp" <<EOF
---
# Matrix Server Secrets - $ENVIRONMENT
# Generated on $(date '+%Y-%m-%d %H:%M:%S')

# IMPORTANT: Add your actual secrets here
# This is a template - replace with real values

# PostgreSQL Database
vault_matrix_database_password: "CHANGE_ME_DB_PASSWORD"

# Matrix Synapse Secrets
vault_form_secret: "CHANGE_ME_FORM_SECRET"
vault_macaroon_secret_key: "CHANGE_ME_MACAROON_SECRET"
vault_registration_secret: "CHANGE_ME_REGISTRATION_SECRET"

# Coturn (TURN server) Secret
vault_coturn_secret: "CHANGE_ME_COTURN_SECRET"

# Admin User
vault_admin_username: "admin"
vault_admin_password: "CHANGE_ME_ADMIN_PASSWORD"

# SSL and Contact Information
vault_ssl_email: "admin@example.com"

# Instructions:
# 1. Edit this file: ansible-vault edit $vault_file
# 2. Replace all CHANGE_ME values with secure secrets
# 3. Use: openssl rand -base64 32  # to generate secure secrets
EOF

    # Encrypt the vault
    echo "$vault_password" | ansible-vault encrypt "$vault_file.tmp" --output "$vault_file"
    rm -f "$vault_file.tmp"

    # Save password file
    local vault_pass_file="$PROJECT_ROOT/.vault_pass"
    echo "$vault_password" > "$vault_pass_file"
    chmod 600 "$vault_pass_file"

    warn "IMPORTANT: Edit the vault file to replace template values:"
    echo "  ansible-vault edit $vault_file"
}

view_vault() {
    step "Viewing vault contents for $ENVIRONMENT..."

    local vault_file="$PROJECT_ROOT/inventory/$ENVIRONMENT/group_vars/all/vault.yml"

    if [ ! -f "$vault_file" ]; then
        error "Vault file not found: $vault_file"
        info "Run: $0 -e $ENVIRONMENT setup"
        exit 1
    fi

    local vault_pass_file
    if vault_pass_file=$(find_vault_password_file); then
        ansible-vault view "$vault_file" --vault-password-file "$vault_pass_file"
    else
        ansible-vault view "$vault_file"
    fi
}

edit_vault() {
    step "Editing vault for $ENVIRONMENT..."

    local vault_file="$PROJECT_ROOT/inventory/$ENVIRONMENT/group_vars/all/vault.yml"

    if [ ! -f "$vault_file" ]; then
        error "Vault file not found: $vault_file"
        info "Run: $0 -e $ENVIRONMENT setup"
        exit 1
    fi

    local vault_pass_file
    if vault_pass_file=$(find_vault_password_file); then
        ansible-vault edit "$vault_file" --vault-password-file "$vault_pass_file"
    else
        ansible-vault edit "$vault_file"
    fi
}

rekey_vault() {
    step "Changing vault password for $ENVIRONMENT..."

    local vault_file="$PROJECT_ROOT/inventory/$ENVIRONMENT/group_vars/all/vault.yml"

    if [ ! -f "$vault_file" ]; then
        error "Vault file not found: $vault_file"
        exit 1
    fi

    local vault_pass_file
    if vault_pass_file=$(find_vault_password_file); then
        ansible-vault rekey "$vault_file" --vault-password-file "$vault_pass_file"
    else
        ansible-vault rekey "$vault_file"
    fi

    # Update password file if it exists
    if [ -f "$PROJECT_ROOT/.vault_pass" ]; then
        warn "Don't forget to update your .vault_pass file with the new password"
    fi
}

validate_vault() {
    step "Validating vault for $ENVIRONMENT..."

    local vault_file="$PROJECT_ROOT/inventory/$ENVIRONMENT/group_vars/all/vault.yml"

    if [ ! -f "$vault_file" ]; then
        error "Vault file not found: $vault_file"
        exit 1
    fi

    # Check if file is encrypted
    if head -1 "$vault_file" | grep -q "^\\$ANSIBLE_VAULT"; then
        log "✓ Vault file is properly encrypted"
    else
        error "Vault file is not encrypted!"
        exit 1
    fi

    # Try to decrypt and validate YAML
    local vault_pass_file
    if vault_pass_file=$(find_vault_password_file); then
        if ansible-vault view "$vault_file" --vault-password-file "$vault_pass_file" > /dev/null 2>&1; then
            log "✓ Vault file can be decrypted successfully"
        else
            error "Failed to decrypt vault file"
            exit 1
        fi
    else
        info "No vault password file found - manual validation required"
        if ansible-vault view "$vault_file" > /dev/null 2>&1; then
            log "✓ Vault file can be decrypted successfully"
        else
            error "Failed to decrypt vault file"
            exit 1
        fi
    fi

    # Check for template values
    local vault_pass_file
    if vault_pass_file=$(find_vault_password_file); then
        local content
        content=$(ansible-vault view "$vault_file" --vault-password-file "$vault_pass_file" 2>/dev/null)

        if echo "$content" | grep -q "CHANGE_ME"; then
            warn "Vault contains template values that should be replaced:"
            echo "$content" | grep "CHANGE_ME" | sed 's/^/  /'
        else
            log "✓ No template values found in vault"
        fi
    fi

    log "✓ Vault validation completed"
}

backup_vault() {
    step "Backing up vault for $ENVIRONMENT..."

    local vault_file="$PROJECT_ROOT/inventory/$ENVIRONMENT/group_vars/all/vault.yml"

    if [ ! -f "$vault_file" ]; then
        error "Vault file not found: $vault_file"
        exit 1
    fi

    local backup_dir="$PROJECT_ROOT/vault-backups"
    local backup_file="$backup_dir/vault-$ENVIRONMENT-$(date +%Y%m%d-%H%M%S).yml"

    mkdir -p "$backup_dir"
    cp "$vault_file" "$backup_file"

    log "✓ Vault backed up to: $backup_file"

    # Clean old backups (keep last 10)
    local backup_count
    backup_count=$(find "$backup_dir" -name "vault-$ENVIRONMENT-*.yml" | wc -l)
    if [ "$backup_count" -gt 10 ]; then
        info "Cleaning old backups (keeping last 10)..."
        find "$backup_dir" -name "vault-$ENVIRONMENT-*.yml" -type f -printf '%T@ %p\n' | sort -n | head -n -10 | cut -d' ' -f2- | xargs rm -f
    fi
}

find_vault_password_file() {
    local possible_files=(
        "$PROJECT_ROOT/.vault_pass"
        "$PROJECT_ROOT/.vault_pass_$ENVIRONMENT"
        "$PROJECT_ROOT/.ansible_vault_password"
        "$HOME/.ansible_vault_password"
    )

    for file in "${possible_files[@]}"; do
        if [ -f "$file" ]; then
            echo "$file"
            return 0
        fi
    done

    return 1
}

main() {
    echo ""
    log "Vault Setup and Management Script"
    log "================================="

    cd "$PROJECT_ROOT"

    parse_args "$@"
    check_dependencies

    case $ACTION in
        setup)
            setup_vault
            ;;
        view)
            view_vault
            ;;
        edit)
            edit_vault
            ;;
        rekey)
            rekey_vault
            ;;
        validate)
            validate_vault
            ;;
        backup)
            backup_vault
            ;;
        *)
            error "Unknown action: $ACTION"
            usage
            exit 1
            ;;
    esac

    echo ""
    log "Vault operation completed successfully!"
}

# Run main function
main "$@"