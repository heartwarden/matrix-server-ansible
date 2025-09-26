#!/bin/bash
# Matrix Server TUI Configuration Script
# Interactive setup for Matrix server deployment

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_DIR="$PROJECT_DIR/server-configs"
TEMP_CONFIG="/tmp/matrix-server-config.tmp"

# Default values
SERVER_NAME=""
MATRIX_DOMAIN=""
MATRIX_HOMESERVER=""
SSL_EMAIL=""
SSH_PORT="2222"
TIMEZONE="UTC"
SERVER_IP=""
SSH_KEY_PATH=""
DEPLOYMENT_TYPE="production"

# Configuration file
CONFIG_FILE=""

# Required commands
REQUIRED_COMMANDS=("whiptail" "openssl" "ssh-keygen" "ansible-playbook")

log() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')] $1${NC}"
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

success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

check_dependencies() {
    local missing_deps=()

    for cmd in "${REQUIRED_COMMANDS[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done

    if [ ${#missing_deps[@]} -gt 0 ]; then
        error "Missing required dependencies: ${missing_deps[*]}"
        echo
        echo "Please install missing dependencies:"
        echo "  Ubuntu/Debian: sudo apt install whiptail openssl openssh-client ansible"
        echo "  macOS: brew install newt openssl openssh ansible"
        exit 1
    fi
}

show_banner() {
    clear
    echo -e "${CYAN}"
    cat << 'EOF'
    ███╗   ███╗ █████╗ ████████╗██████╗ ██╗██╗  ██╗
    ████╗ ████║██╔══██╗╚══██╔══╝██╔══██╗██║╚██╗██╔╝
    ██╔████╔██║███████║   ██║   ██████╔╝██║ ╚███╔╝
    ██║╚██╔╝██║██╔══██║   ██║   ██╔══██╗██║ ██╔██╗
    ██║ ╚═╝ ██║██║  ██║   ██║   ██║  ██║██║██╔╝ ██╗
    ╚═╝     ╚═╝╚═╝  ╚═╝   ╚═╝   ╚═╝  ╚═╝╚═╝╚═╝  ╚═╝

    Secure Matrix Server Configuration
    Interactive Setup Wizard
EOF
    echo -e "${NC}"
    echo
}

welcome_screen() {
    whiptail --title "Matrix Server Setup" --msgbox "Welcome to the Matrix Server Setup Wizard!

This tool will help you configure a secure Matrix (Synapse) server with:

🔒 Security hardening (SSH, firewall, system)
🏠 Matrix Synapse homeserver
🌐 Element web client
🔐 Automatic SSL certificates (Let's Encrypt)
📊 System monitoring and alerting
🚀 Caddy web server with automatic HTTPS

Press OK to continue..." 16 70
}

collect_basic_info() {
    # Server name/identifier
    SERVER_NAME=$(whiptail --title "Server Configuration" --inputbox "Enter a name for this server (for identification):" 8 60 "matrix-server-01" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then exit 1; fi

    # Matrix domain
    MATRIX_DOMAIN=$(whiptail --title "Matrix Domain" --inputbox "Enter your Matrix domain (where Element will be hosted):" 8 60 "example.com" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then exit 1; fi

    # Matrix homeserver
    local default_homeserver="matrix.$MATRIX_DOMAIN"
    MATRIX_HOMESERVER=$(whiptail --title "Matrix Homeserver" --inputbox "Enter your Matrix homeserver domain:" 8 60 "$default_homeserver" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then exit 1; fi

    # SSL Email
    SSL_EMAIL=$(whiptail --title "SSL Configuration" --inputbox "Enter email for Let's Encrypt SSL certificates:" 8 60 "admin@$MATRIX_DOMAIN" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then exit 1; fi

    # Server IP
    SERVER_IP=$(whiptail --title "Server Network" --inputbox "Enter your server's public IP address:" 8 60 "" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then exit 1; fi
}

collect_security_settings() {
    # SSH Port
    SSH_PORT=$(whiptail --title "SSH Configuration" --inputbox "Enter SSH port (default 2222 for security):" 8 60 "2222" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then exit 1; fi

    # Timezone
    local timezones=(
        "UTC" "Coordinated Universal Time"
        "America/New_York" "Eastern Time"
        "America/Chicago" "Central Time"
        "America/Denver" "Mountain Time"
        "America/Los_Angeles" "Pacific Time"
        "Europe/London" "British Time"
        "Europe/Paris" "Central European Time"
        "Europe/Berlin" "Central European Time"
        "Asia/Tokyo" "Japan Standard Time"
        "Asia/Shanghai" "China Standard Time"
        "Australia/Sydney" "Australian Eastern Time"
    )

    TIMEZONE=$(whiptail --title "Timezone Configuration" --menu "Select your server timezone:" 16 70 10 "${timezones[@]}" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then exit 1; fi
}

handle_ssh_key() {
    if whiptail --title "SSH Key Configuration" --yesno "Do you have an existing SSH public key you'd like to use?" 8 60; then
        SSH_KEY_PATH=$(whiptail --title "SSH Key Path" --inputbox "Enter the path to your SSH public key:" 8 60 "$HOME/.ssh/id_ed25519.pub" 3>&1 1>&2 2>&3)
        if [ $? -ne 0 ]; then exit 1; fi

        if [ ! -f "$SSH_KEY_PATH" ]; then
            if whiptail --title "SSH Key Not Found" --yesno "SSH key not found at $SSH_KEY_PATH. Generate a new one?" 8 60; then
                generate_ssh_key
            else
                error "SSH key is required for secure access"
                exit 1
            fi
        fi
    else
        generate_ssh_key
    fi
}

generate_ssh_key() {
    local key_name="matrix-server-${SERVER_NAME}"
    local key_path="$HOME/.ssh/${key_name}"

    info "Generating SSH key pair..."

    if [ -f "${key_path}" ]; then
        if ! whiptail --title "SSH Key Exists" --yesno "SSH key ${key_path} already exists. Overwrite?" 8 60; then
            SSH_KEY_PATH="${key_path}.pub"
            return
        fi
    fi

    ssh-keygen -t ed25519 -f "${key_path}" -N "" -C "matrix-server-${SERVER_NAME}"
    SSH_KEY_PATH="${key_path}.pub"

    whiptail --title "SSH Key Generated" --msgbox "SSH key pair generated:

Private key: ${key_path}
Public key: ${key_path}.pub

Keep the private key secure and use it to connect to your server." 12 70
}

select_deployment_type() {
    DEPLOYMENT_TYPE=$(whiptail --title "Deployment Type" --menu "Select deployment type:" 12 60 3 \
        "production" "Full production setup with all security features" \
        "staging" "Staging environment for testing" \
        "development" "Development setup with relaxed security" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then exit 1; fi
}

generate_passwords() {
    info "Generating secure passwords..."

    # Generate random passwords
    local db_password=$(openssl rand -base64 32)
    local coturn_secret=$(openssl rand -base64 32)
    local registration_secret=$(openssl rand -base64 32)
    local macaroon_secret=$(openssl rand -base64 64)
    local form_secret=$(openssl rand -base64 32)

    # Store in temporary config
    cat > "$TEMP_CONFIG" << EOF
# Generated passwords for $SERVER_NAME
MATRIX_DB_PASSWORD="$db_password"
COTURN_SECRET="$coturn_secret"
REGISTRATION_SECRET="$registration_secret"
MACAROON_SECRET="$macaroon_secret"
FORM_SECRET="$form_secret"
EOF

    success "Secure passwords generated"
}

create_server_config() {
    mkdir -p "$CONFIG_DIR"
    CONFIG_FILE="$CONFIG_DIR/${SERVER_NAME}-config.yml"

    info "Creating server configuration..."

    # Read SSH public key
    local ssh_public_key=""
    if [ -f "$SSH_KEY_PATH" ]; then
        ssh_public_key=$(cat "$SSH_KEY_PATH")
    fi

    # Source the temporary password config
    source "$TEMP_CONFIG"

    cat > "$CONFIG_FILE" << EOF
---
# Matrix Server Configuration for $SERVER_NAME
# Generated on $(date)

server_info:
  name: "$SERVER_NAME"
  ip: "$SERVER_IP"
  deployment_type: "$DEPLOYMENT_TYPE"
  generated_date: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

domains:
  matrix_domain: "$MATRIX_DOMAIN"
  matrix_homeserver_name: "$MATRIX_HOMESERVER"
  ssl_email: "$SSL_EMAIL"

security:
  ssh_port: $SSH_PORT
  ssh_public_key: "$ssh_public_key"
  timezone: "$TIMEZONE"
  admin_username: "zerokaine"

passwords:
  matrix_database_password: "$MATRIX_DB_PASSWORD"
  coturn_secret: "$COTURN_SECRET"
  registration_secret: "$REGISTRATION_SECRET"
  macaroon_secret: "$MACAROON_SECRET"
  form_secret: "$FORM_SECRET"

features:
  matrix_element_enabled: true
  matrix_coturn_enabled: true
  matrix_federation_enabled: true
  monitoring_enabled: true
  backup_enabled: true
  fail2ban_enabled: true

network:
  ufw_enabled: true
  ssh_rate_limiting: true
  matrix_rate_limiting: true

caddy:
  auto_https: true
  security_headers: true
  rate_limiting: true
EOF

    success "Configuration saved to: $CONFIG_FILE"
}

create_inventory() {
    local inventory_file="$CONFIG_DIR/${SERVER_NAME}-inventory.yml"

    info "Creating Ansible inventory..."

    cat > "$inventory_file" << EOF
---
all:
  children:
    matrix_servers:
      hosts:
        $SERVER_NAME:
          ansible_connection: local
          ansible_python_interpreter: /usr/bin/python3
          matrix_domain: $MATRIX_DOMAIN
          matrix_homeserver_name: $MATRIX_HOMESERVER
          ssl_email: $SSL_EMAIL
          server_ip: $SERVER_IP
          ssh_port: $SSH_PORT
  vars:
    ansible_become: yes
    ansible_become_method: sudo
    # Local deployment - Ansible runs on the target server
    # SSH access from external machines will use zerokaine user on port $SSH_PORT
EOF

    success "Inventory saved to: $inventory_file"
}

create_vault_file() {
    local vault_file="$CONFIG_DIR/${SERVER_NAME}-vault.yml"
    local vault_pass_file="$CONFIG_DIR/${SERVER_NAME}-vault-pass"

    info "Creating encrypted vault file..."

    # Generate vault password
    openssl rand -base64 32 > "$vault_pass_file"
    chmod 600 "$vault_pass_file"

    # Source passwords
    source "$TEMP_CONFIG"

    # Create vault content with additional secrets
    local vault_content=$(cat << EOF
---
# Encrypted secrets for $SERVER_NAME
# Generated on $(date -u +%Y-%m-%dT%H:%M:%SZ)

# Matrix database secrets
vault_matrix_database_password: "$MATRIX_DB_PASSWORD"
vault_matrix_database_user: "synapse"
vault_matrix_database_name: "synapse"

# Matrix server secrets
vault_coturn_secret: "$COTURN_SECRET"
vault_registration_secret: "$REGISTRATION_SECRET"
vault_macaroon_secret_key: "$MACAROON_SECRET"
vault_form_secret: "$FORM_SECRET"

# SSH configuration
vault_ssh_public_key: "$(cat "$SSH_KEY_PATH" 2>/dev/null || echo '')"
vault_admin_username: "zerokaine"

# SSL configuration
vault_ssl_email: "$SSL_EMAIL"

# Server identification
vault_server_name: "$SERVER_NAME"
vault_server_ip: "$SERVER_IP"

# Monitoring secrets
vault_monitoring_email: "$SSL_EMAIL"
vault_alert_webhook: ""

# Backup encryption
vault_backup_encryption_key: "$(openssl rand -base64 32)"

# Additional security tokens
vault_api_secret: "$(openssl rand -base64 32)"
vault_webhook_secret: "$(openssl rand -base64 32)"
EOF
)

    # Encrypt vault file
    echo "$vault_content" | ansible-vault encrypt --vault-password-file="$vault_pass_file" --output="$vault_file"

    success "Encrypted vault created: $vault_file"
    success "Vault password saved to: $vault_pass_file"

    # Also create a vault info file (non-encrypted) for reference
    cat > "$CONFIG_DIR/${SERVER_NAME}-vault-info.txt" << EOF
# Vault Information for $SERVER_NAME
# Generated on $(date)

Vault file: ${SERVER_NAME}-vault.yml (encrypted)
Vault password file: ${SERVER_NAME}-vault-pass
Server: $SERVER_NAME ($SERVER_IP)
Domain: $MATRIX_DOMAIN

# To view vault contents:
ansible-vault view ${SERVER_NAME}-vault.yml --vault-password-file=${SERVER_NAME}-vault-pass

# To edit vault:
ansible-vault edit ${SERVER_NAME}-vault.yml --vault-password-file=${SERVER_NAME}-vault-pass

IMPORTANT: Keep the vault password file secure!
EOF

    chmod 600 "$CONFIG_DIR/${SERVER_NAME}-vault-info.txt"
    info "Vault reference created: ${SERVER_NAME}-vault-info.txt"
}

create_deployment_script() {
    local deploy_script="$CONFIG_DIR/${SERVER_NAME}-deploy.sh"

    info "Creating deployment script..."

    cat > "$deploy_script" << 'EOF'
#!/bin/bash
# Matrix Server Deployment Script for {{ SERVER_NAME }}
# Generated automatically - modify with care

set -euo pipefail

# Configuration
SERVER_NAME="{{ SERVER_NAME }}"
CONFIG_DIR="{{ CONFIG_DIR }}"
PROJECT_DIR="{{ PROJECT_DIR }}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date +'%H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[WARNING] $1${NC}"; }
error() { echo -e "${RED}[ERROR] $1${NC}"; }
info() { echo -e "${BLUE}[INFO] $1${NC}"; }

# Files
INVENTORY="$CONFIG_DIR/${SERVER_NAME}-inventory.yml"
VAULT_FILE="$CONFIG_DIR/${SERVER_NAME}-vault.yml"
VAULT_PASS="$CONFIG_DIR/${SERVER_NAME}-vault-pass"
CONFIG_FILE="$CONFIG_DIR/${SERVER_NAME}-config.yml"

main() {
    echo -e "${BLUE}"
    cat << 'BANNER'
    ███╗   ███╗ █████╗ ████████╗██████╗ ██╗██╗  ██╗
    ████╗ ████║██╔══██╗╚══██╔══╝██╔══██╗██║╚██╗██╔╝
    ██╔████╔██║███████║   ██║   ██████╔╝██║ ╚███╔╝
    ██║╚██╔╝██║██╔══██║   ██║   ██╔══██╗██║ ██╔██╗
    ██║ ╚═╝ ██║██║  ██║   ██║   ██║  ██║██║██╔╝ ██╗
    ╚═╝     ╚═╝╚═╝  ╚═╝   ╚═╝   ╚═╝  ╚═╝╚═╝╚═╝  ╚═╝

    Deploying: {{ SERVER_NAME }}
BANNER
    echo -e "${NC}"

    log "Starting deployment for $SERVER_NAME"

    # Check files exist
    for file in "$INVENTORY" "$VAULT_FILE" "$VAULT_PASS" "$CONFIG_FILE"; do
        if [ ! -f "$file" ]; then
            error "Required file not found: $file"
            exit 1
        fi
    done

    # Test local connectivity
    info "Testing local connectivity..."
    if ! ansible all -i "$INVENTORY" -m ping --connection=local; then
        error "Local connectivity test failed"
        exit 1
    fi

    # Deploy
    log "Deploying Matrix server..."
    ansible-playbook "$PROJECT_DIR/playbooks/site.yml" \
        -i "$INVENTORY" \
        --vault-password-file="$VAULT_PASS" \
        --extra-vars="@$CONFIG_FILE" \
        --extra-vars="@$VAULT_FILE"

    log "Deployment completed for $SERVER_NAME"
}

main "$@"
EOF

    # Replace placeholders
    sed -i.bak \
        -e "s|{{ SERVER_NAME }}|$SERVER_NAME|g" \
        -e "s|{{ CONFIG_DIR }}|$CONFIG_DIR|g" \
        -e "s|{{ PROJECT_DIR }}|$PROJECT_DIR|g" \
        "$deploy_script"
    rm "${deploy_script}.bak"

    chmod +x "$deploy_script"

    success "Deployment script created: $deploy_script"
}

show_summary() {
    whiptail --title "Configuration Complete" --msgbox "Matrix Server Configuration Complete!

Server: $SERVER_NAME
Domain: $MATRIX_DOMAIN
Homeserver: $MATRIX_HOMESERVER
IP: $SERVER_IP
SSH Port: $SSH_PORT

Files created in $CONFIG_DIR/:
• ${SERVER_NAME}-config.yml (server configuration)
• ${SERVER_NAME}-inventory.yml (Ansible inventory)
• ${SERVER_NAME}-vault.yml (encrypted secrets)
• ${SERVER_NAME}-vault-pass (vault password)
• ${SERVER_NAME}-deploy.sh (deployment script)

Next steps:
1. Review configuration files
2. Ensure DNS records are configured
3. Run: ./${SERVER_NAME}-deploy.sh

Press OK to continue..." 20 80

    echo
    success "Configuration complete!"
    echo
    info "Next steps:"
    echo "1. Configure DNS records:"
    echo "   $MATRIX_DOMAIN A $SERVER_IP"
    echo "   $MATRIX_HOMESERVER A $SERVER_IP"
    echo
    echo "2. Review configuration:"
    echo "   cat $CONFIG_DIR/${SERVER_NAME}-config.yml"
    echo
    echo "3. Deploy the server:"
    echo "   cd $CONFIG_DIR"
    echo "   ./${SERVER_NAME}-deploy.sh"
    echo
    echo "4. Connect to server after deployment:"
    echo "   ssh -p $SSH_PORT zerokaine@$SERVER_IP"
    echo "   (Uses the same SSH key currently in /root/.ssh/authorized_keys)"
}

cleanup() {
    # Clean up temporary files
    rm -f "$TEMP_CONFIG"
}

main() {
    trap cleanup EXIT

    check_dependencies
    show_banner
    welcome_screen

    collect_basic_info
    collect_security_settings
    handle_ssh_key
    select_deployment_type

    generate_passwords
    create_server_config
    create_inventory
    create_vault_file
    create_deployment_script

    show_summary
}

# Run if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi