#!/bin/bash
# Matrix Server Deployment Script
# Automated deployment with pre-flight checks and validation

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Default values
ENVIRONMENT="production"
PLAYBOOK="site"
INVENTORY=""
VAULT_PASSWORD_FILE="$PROJECT_DIR/.vault_pass"
DRY_RUN=false
SKIP_CHECKS=false
VERBOSE=false
GENERATE_SECRETS=false
AUTO_MODE=false

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

debug() {
    if [ "$VERBOSE" = true ]; then
        echo -e "${PURPLE}[DEBUG] $1${NC}"
    fi
}

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Matrix Server Deployment Script

OPTIONS:
    -e, --environment ENV    Target environment (production|staging) [default: production]
    -p, --playbook BOOK      Playbook to run (site|hardening|matrix|maintenance) [default: site]
    -i, --inventory FILE     Custom inventory file path
    -v, --vault-file FILE    Vault password file [default: .vault_pass]
    -d, --dry-run           Perform a dry run (check mode)
    -s, --skip-checks       Skip pre-flight checks
    -g, --generate-secrets  Generate new secrets before deployment
    -a, --auto              Auto mode (generate secrets if missing, no prompts)
    --verbose               Enable verbose output
    -h, --help              Show this help message

EXAMPLES:
    $0                                          # Deploy complete stack to production
    $0 -e staging -p hardening                 # Harden staging servers only
    $0 -p matrix -d                            # Dry run Matrix deployment
    $0 -g                                      # Generate secrets and deploy
    $0 -a                                      # Auto mode (generate secrets if needed)
    $0 -i custom_inventory.yml -p maintenance  # Run maintenance with custom inventory

PLAYBOOKS:
    site        - Complete Matrix server deployment (hardening + matrix + monitoring)
    hardening   - Security hardening only
    matrix      - Matrix server installation only
    maintenance - System maintenance and updates

ENVIRONMENTS:
    production  - Production servers (inventory/production/hosts.yml)
    staging     - Staging servers (inventory/staging/hosts.yml)
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -e|--environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            -p|--playbook)
                PLAYBOOK="$2"
                shift 2
                ;;
            -i|--inventory)
                INVENTORY="$2"
                shift 2
                ;;
            -v|--vault-file)
                VAULT_PASSWORD_FILE="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -s|--skip-checks)
                SKIP_CHECKS=true
                shift
                ;;
            -g|--generate-secrets)
                GENERATE_SECRETS=true
                shift
                ;;
            -a|--auto)
                AUTO_MODE=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    # Set inventory if not provided
    if [ -z "$INVENTORY" ]; then
        INVENTORY="$PROJECT_DIR/inventory/$ENVIRONMENT/hosts.yml"
    fi

    debug "Environment: $ENVIRONMENT"
    debug "Playbook: $PLAYBOOK"
    debug "Inventory: $INVENTORY"
    debug "Vault file: $VAULT_PASSWORD_FILE"
    debug "Dry run: $DRY_RUN"
    debug "Generate secrets: $GENERATE_SECRETS"
    debug "Auto mode: $AUTO_MODE"
}

check_environment() {
    log "Checking deployment environment..."

    # Check if we're in the right directory
    if [ ! -f "$PROJECT_DIR/ansible.cfg" ]; then
        error "Not in Matrix server Ansible project directory"
        exit 1
    fi

    # Check Ansible installation
    if ! command -v ansible-playbook &> /dev/null; then
        error "ansible-playbook not found. Install Ansible first"
        info "macOS: brew install ansible"
        info "Ubuntu/Debian: sudo apt install ansible"
        exit 1
    fi

    # Check ansible-vault
    if ! command -v ansible-vault &> /dev/null; then
        error "ansible-vault not found. Install Ansible first"
        exit 1
    fi

    # Check inventory file
    if [ ! -f "$INVENTORY" ]; then
        error "Inventory file not found: $INVENTORY"
        info "Copy and edit: inventory/$ENVIRONMENT/hosts.yml.example"
        exit 1
    fi

    # Check playbook file
    local playbook_file="$PROJECT_DIR/playbooks/$PLAYBOOK.yml"
    if [ ! -f "$playbook_file" ]; then
        error "Playbook not found: $playbook_file"
        exit 1
    fi

    # Handle secrets and vault
    handle_secrets_and_vault

    log "Environment check completed"
}

handle_secrets_and_vault() {
    local vault_file="$PROJECT_DIR/inventory/$ENVIRONMENT/group_vars/all/vault.yml"

    # Generate secrets if requested or in auto mode
    if [ "$GENERATE_SECRETS" = true ]; then
        log "Generating secrets..."
        if ! "$SCRIPT_DIR/generate-secrets.sh" "$ENVIRONMENT"; then
            error "Secret generation failed"
            exit 1
        fi
    elif [ "$AUTO_MODE" = true ] && [ ! -f "$vault_file" ]; then
        log "Auto mode: Generating missing secrets..."
        if ! "$SCRIPT_DIR/generate-secrets.sh" "$ENVIRONMENT"; then
            error "Secret generation failed"
            exit 1
        fi
    fi

    # Check vault file exists
    if [ ! -f "$vault_file" ]; then
        error "Vault file not found: $vault_file"
        info "Generate secrets with: $0 --generate-secrets"
        exit 1
    fi

    # Try to find vault password file
    local found_vault_file=""
    local possible_files=(
        "$VAULT_PASSWORD_FILE"
        "$PROJECT_DIR/.vault_pass"
        "$PROJECT_DIR/.ansible_vault_password"
        "$HOME/.ansible_vault_password"
    )

    for file in "${possible_files[@]}"; do
        if [ -f "$file" ]; then
            found_vault_file="$file"
            VAULT_PASSWORD_FILE="$file"
            break
        fi
    done

    if [ -z "$found_vault_file" ]; then
        warn "Vault password file not found"
        if [ "$AUTO_MODE" = false ]; then
            info "Will prompt for vault password during deployment"
            VAULT_PASSWORD_FILE=""  # Will use --ask-vault-pass
        else
            error "Auto mode requires vault password file"
            info "Create .vault_pass with your vault password"
            exit 1
        fi
    else
        log "✓ Using vault password file: $found_vault_file"
    fi
}

run_preflight_checks() {
    if [ "$SKIP_CHECKS" = true ]; then
        warn "Skipping pre-flight checks"
        return
    fi

    log "Running pre-flight checks..."

    # Test inventory syntax
    info "Validating inventory syntax..."
    if ! ansible-inventory -i "$INVENTORY" --list > /dev/null; then
        error "Invalid inventory syntax"
        exit 1
    fi

    # Build vault options
    local vault_opts=()
    if [ -n "$VAULT_PASSWORD_FILE" ]; then
        vault_opts=("--vault-password-file=$VAULT_PASSWORD_FILE")
    else
        vault_opts=("--ask-vault-pass")
    fi

    # Test connectivity
    info "Testing SSH connectivity..."
    if ! ansible all -i "$INVENTORY" -m ping "${vault_opts[@]}" > /dev/null 2>&1; then
        error "SSH connectivity test failed"
        info "Check your SSH keys and server access"
        exit 1
    fi

    # Test sudo access
    info "Testing sudo access..."
    if ! ansible all -i "$INVENTORY" -m command -a "whoami" -b "${vault_opts[@]}" > /dev/null 2>&1; then
        error "Sudo access test failed"
        exit 1
    fi

    # Validate playbook syntax
    info "Validating playbook syntax..."
    if ! ansible-playbook "$PROJECT_DIR/playbooks/$PLAYBOOK.yml" -i "$INVENTORY" --syntax-check "${vault_opts[@]}" > /dev/null 2>&1; then
        error "Playbook syntax validation failed"
        exit 1
    fi

    # Check for required variables
    info "Checking required variables..."
    local missing_vars=()

    # Check if variables are defined in inventory
    if ! ansible-inventory -i "$INVENTORY" --host matrix.example.com 2>/dev/null | grep -q "matrix_domain"; then
        missing_vars+=("matrix_domain")
    fi

    if ! ansible-inventory -i "$INVENTORY" --host matrix.example.com 2>/dev/null | grep -q "ssl_email"; then
        missing_vars+=("ssl_email")
    fi

    if [ ${#missing_vars[@]} -gt 0 ]; then
        error "Missing required variables: ${missing_vars[*]}"
        info "Check your inventory configuration"
        exit 1
    fi

    log "Pre-flight checks completed successfully"
}

show_deployment_summary() {
    echo -e "${BLUE}"
    cat << 'EOF'
╔═══════════════════════════════════════════════════════════════╗
║                    DEPLOYMENT SUMMARY                         ║
╚═══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"

    echo "Environment:     $ENVIRONMENT"
    echo "Playbook:        $PLAYBOOK.yml"
    echo "Inventory:       $INVENTORY"
    echo "Dry Run:         $DRY_RUN"

    # Show target hosts
    echo
    info "Target hosts:"
    ansible-inventory -i "$INVENTORY" --list | jq -r '.["matrix_servers"]["hosts"] // [] | keys[]' 2>/dev/null || echo "Failed to parse inventory"

    echo
    if [ "$DRY_RUN" = true ]; then
        warn "This is a DRY RUN - no changes will be made"
    else
        warn "This will make changes to your servers!"
    fi

    echo
    read -p "Continue with deployment? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Deployment cancelled"
        exit 0
    fi
}

run_deployment() {
    log "Starting deployment..."

    # Build ansible-playbook command
    local cmd=(
        "ansible-playbook"
        "$PROJECT_DIR/playbooks/$PLAYBOOK.yml"
        "-i" "$INVENTORY"
    )

    # Add vault options
    if [ -n "$VAULT_PASSWORD_FILE" ]; then
        cmd+=("--vault-password-file=$VAULT_PASSWORD_FILE")
    else
        cmd+=("--ask-vault-pass")
    fi

    # Add options
    if [ "$DRY_RUN" = true ]; then
        cmd+=("--check" "--diff")
    fi

    if [ "$VERBOSE" = true ]; then
        cmd+=("-vvv")
    fi

    # Add timestamp
    local start_time=$(date +%s)
    local log_file="$PROJECT_DIR/deployment-$(date +%Y%m%d-%H%M%S).log"

    info "Command: ${cmd[*]}"
    info "Logging to: $log_file"

    # Run the deployment
    if "${cmd[@]}" 2>&1 | tee "$log_file"; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))

        log "Deployment completed successfully in ${duration}s"

        # Show post-deployment info
        show_post_deployment_info
    else
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))

        error "Deployment failed after ${duration}s"
        error "Check the log file: $log_file"
        exit 1
    fi
}

show_post_deployment_info() {
    echo
    echo -e "${GREEN}"
    cat << 'EOF'
╔═══════════════════════════════════════════════════════════════╗
║                 DEPLOYMENT COMPLETED                          ║
╚═══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"

    case $PLAYBOOK in
        "site"|"matrix")
            echo "🎉 Matrix server deployed successfully!"
            echo
            echo "Next steps:"
            echo "1. Create an admin user:"
            echo "   ssh user@your-server"
            echo "   sudo /usr/local/bin/create-matrix-admin.sh admin secure_password"
            echo
            echo "2. Test your Matrix server:"
            echo "   - Element Web: https://your-domain.com"
            echo "   - Federation test: https://federationtester.matrix.org/"
            echo
            echo "3. Configure your Matrix client:"
            echo "   - Homeserver: https://matrix.your-domain.com"
            echo "   - Use your admin credentials"
            ;;
        "hardening")
            echo "🔒 Server hardening completed!"
            echo
            echo "Security measures applied:"
            echo "- SSH hardened (port 2222, key-only auth)"
            echo "- Firewall configured"
            echo "- System monitoring enabled"
            echo "- Automatic updates configured"
            echo
            echo "⚠️  IMPORTANT: SSH now runs on port 2222"
            ;;
        "maintenance")
            echo "🔧 System maintenance completed!"
            echo
            echo "Maintenance tasks performed:"
            echo "- System updates applied"
            echo "- Logs rotated"
            echo "- Security scans run"
            echo "- Service health checked"
            ;;
    esac

    echo
    info "Deployment logs saved to: deployment-$(date +%Y%m%d)*.log"
}

display_banner() {
    echo -e "${BLUE}"
    cat << 'EOF'
    ███╗   ███╗ █████╗ ████████╗██████╗ ██╗██╗  ██╗
    ████╗ ████║██╔══██╗╚══██╔══╝██╔══██╗██║╚██╗██╔╝
    ██╔████╔██║███████║   ██║   ██████╔╝██║ ╚███╔╝
    ██║╚██╔╝██║██╔══██║   ██║   ██╔══██╗██║ ██╔██╗
    ██║ ╚═╝ ██║██║  ██║   ██║   ██║  ██║██║██╔╝ ██╗
    ╚═╝     ╚═╝╚═╝  ╚═╝   ╚═╝   ╚═╝  ╚═╝╚═╝╚═╝  ╚═╝

    Secure Matrix Server Deployment
EOF
    echo -e "${NC}"
}

main() {
    display_banner

    parse_args "$@"
    check_environment
    run_preflight_checks
    show_deployment_summary
    run_deployment
}

# Handle Ctrl+C gracefully
trap 'echo; error "Deployment interrupted by user"; exit 130' INT

# Run main function
main "$@"