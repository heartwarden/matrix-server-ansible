#!/bin/bash
# Matrix Server TUI Configuration & One-Shot Deployment
# Configure everything through an interactive interface, then deploy

set -e

# Colors and formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Unicode symbols
CHECK="✅"
CROSS="❌"
ARROW="➤"
STAR="⭐"
GEAR="⚙️"
SHIELD="🛡️"
ROCKET="🚀"

clear

echo -e "${PURPLE}${BOLD}"
cat << "EOF"
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║    🚀 MATRIX SERVER CONFIGURATION & DEPLOYMENT WIZARD       ║
║                                                              ║
║    Configure everything through this TUI, then deploy       ║
║    with a single command. No manual file editing needed.    ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Global variables for configuration
ENVIRONMENT="production"
MATRIX_DOMAIN=""
HOMESERVER_DOMAIN=""
SSL_EMAIL=""
SERVER_IP=""
SSH_PORT="2222"
ADMIN_USERNAME="admin"
ADMIN_PASSWORD=""
ENABLE_REGISTRATION="false"
DEPLOYMENT_TYPE="fresh"
CREATE_USER="zerokaine"
USE_LOCAL_DEPLOYMENT="true"

# Helper functions
show_header() {
    clear
    echo -e "${CYAN}${BOLD}$1${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

show_step() {
    echo -e "${YELLOW}${ARROW} $1${NC}"
}

show_success() {
    echo -e "${GREEN}${CHECK} $1${NC}"
}

show_error() {
    echo -e "${RED}${CROSS} $1${NC}"
}

show_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

prompt_input() {
    local prompt="$1"
    local default="$2"
    local variable="$3"

    if [ -n "$default" ]; then
        echo -ne "${WHITE}$prompt${NC} ${BLUE}[$default]${NC}: "
    else
        echo -ne "${WHITE}$prompt${NC}: "
    fi

    read user_input
    if [ -z "$user_input" ] && [ -n "$default" ]; then
        eval "$variable=\"$default\""
    else
        eval "$variable=\"$user_input\""
    fi
}

prompt_password() {
    local prompt="$1"
    local variable="$2"

    echo -ne "${WHITE}$prompt${NC}: "
    read -s user_input
    echo ""
    eval "$variable=\"$user_input\""
}

prompt_choice() {
    local prompt="$1"
    local options="$2"
    local default="$3"
    local variable="$4"

    echo -e "${WHITE}$prompt${NC}"
    echo -e "${BLUE}$options${NC}"
    echo -ne "${WHITE}Choice${NC} ${BLUE}[$default]${NC}: "

    read user_input
    if [ -z "$user_input" ]; then
        eval "$variable=\"$default\""
    else
        eval "$variable=\"$user_input\""
    fi
}

validate_domain() {
    local domain="$1"
    if [[ "$domain" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9]\.[a-zA-Z]{2,}$ ]]; then
        return 0
    else
        return 1
    fi
}

validate_email() {
    local email="$1"
    if [[ "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        return 0
    else
        return 1
    fi
}

validate_ip() {
    local ip="$1"
    if [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 0
    else
        return 1
    fi
}

# Configuration steps
configure_deployment_type() {
    show_header "${GEAR} DEPLOYMENT TYPE"

    show_info "Choose your deployment scenario:"
    echo ""
    echo -e "${WHITE}1.${NC} Fresh installation (recommended)"
    echo -e "${WHITE}2.${NC} Update existing installation"
    echo -e "${WHITE}3.${NC} Recovery from broken installation"
    echo ""

    prompt_choice "Select deployment type:" "1=Fresh, 2=Update, 3=Recovery" "1" choice

    case "$choice" in
        "1") DEPLOYMENT_TYPE="fresh" ;;
        "2") DEPLOYMENT_TYPE="update" ;;
        "3") DEPLOYMENT_TYPE="recovery" ;;
        *) DEPLOYMENT_TYPE="fresh" ;;
    esac

    show_success "Deployment type: $DEPLOYMENT_TYPE"
    echo ""
}

configure_environment() {
    show_header "${STAR} ENVIRONMENT SETUP"

    show_info "Choose deployment environment:"
    echo ""
    echo -e "${WHITE}1.${NC} Production (recommended)"
    echo -e "${WHITE}2.${NC} Staging/Testing"
    echo ""

    prompt_choice "Select environment:" "1=Production, 2=Staging" "1" choice

    case "$choice" in
        "1") ENVIRONMENT="production" ;;
        "2") ENVIRONMENT="staging" ;;
        *) ENVIRONMENT="production" ;;
    esac

    show_success "Environment: $ENVIRONMENT"
    echo ""
}

configure_domains() {
    show_header "${GLOBE} DOMAIN CONFIGURATION"

    show_info "Configure your Matrix server domains"
    echo ""

    while true; do
        prompt_input "Matrix domain (where Element web will be hosted)" "chat.yourdomain.com" MATRIX_DOMAIN
        if validate_domain "$MATRIX_DOMAIN"; then
            show_success "Matrix domain: $MATRIX_DOMAIN"
            break
        else
            show_error "Invalid domain format. Please try again."
        fi
    done

    echo ""

    while true; do
        prompt_input "Homeserver domain (Matrix federation domain)" "matrix.yourdomain.com" HOMESERVER_DOMAIN
        if validate_domain "$HOMESERVER_DOMAIN"; then
            show_success "Homeserver domain: $HOMESERVER_DOMAIN"
            break
        else
            show_error "Invalid domain format. Please try again."
        fi
    done

    echo ""

    while true; do
        prompt_input "SSL certificate email" "admin@yourdomain.com" SSL_EMAIL
        if validate_email "$SSL_EMAIL"; then
            show_success "SSL email: $SSL_EMAIL"
            break
        else
            show_error "Invalid email format. Please try again."
        fi
    done

    echo ""
}

configure_server() {
    show_header "${SHIELD} SERVER CONFIGURATION"

    show_info "Configure server connection details"
    echo ""

    echo -e "${WHITE}1.${NC} Local deployment (running on the target server)"
    echo -e "${WHITE}2.${NC} Remote deployment (SSH to another server)"
    echo ""

    prompt_choice "Deployment method:" "1=Local, 2=Remote" "1" choice

    if [ "$choice" = "2" ]; then
        USE_LOCAL_DEPLOYMENT="false"

        while true; do
            prompt_input "Server IP address" "" SERVER_IP
            if validate_ip "$SERVER_IP"; then
                show_success "Server IP: $SERVER_IP"
                break
            else
                show_error "Invalid IP address format. Please try again."
            fi
        done

        echo ""
        prompt_input "SSH port" "2222" SSH_PORT
        show_success "SSH port: $SSH_PORT"
    else
        USE_LOCAL_DEPLOYMENT="true"
        SERVER_IP="127.0.0.1"
        show_success "Local deployment configured"
    fi

    echo ""
}

configure_admin() {
    show_header "${GEAR} ADMIN CONFIGURATION"

    show_info "Configure Matrix administrator account"
    echo ""

    prompt_input "Admin username" "admin" ADMIN_USERNAME
    show_success "Admin username: $ADMIN_USERNAME"

    echo ""

    while true; do
        prompt_password "Admin password (leave empty for auto-generation)"
        if [ -z "$user_input" ]; then
            ADMIN_PASSWORD=$(openssl rand -base64 12)
            show_success "Auto-generated password: $ADMIN_PASSWORD"
            break
        else
            ADMIN_PASSWORD="$user_input"
            if [ ${#ADMIN_PASSWORD} -ge 8 ]; then
                show_success "Password set (hidden)"
                break
            else
                show_error "Password must be at least 8 characters"
            fi
        fi
    done

    echo ""
}

configure_security() {
    show_header "${SHIELD} SECURITY & PRIVACY"

    show_info "Configure security and privacy settings"
    echo ""

    prompt_choice "Enable user registration?" "y=Yes, n=No" "n" choice
    if [ "$choice" = "y" ] || [ "$choice" = "Y" ]; then
        ENABLE_REGISTRATION="true"
        show_success "User registration: Enabled"
    else
        ENABLE_REGISTRATION="false"
        show_success "User registration: Disabled (admin only)"
    fi

    echo ""

    prompt_input "Create system user" "zerokaine" CREATE_USER
    show_success "System user: $CREATE_USER"

    echo ""

    show_info "Privacy settings (pre-configured):"
    echo -e "${GREEN}${CHECK}${NC} No IP address logging"
    echo -e "${GREEN}${CHECK}${NC} No email/CAPTCHA required"
    echo -e "${GREEN}${CHECK}${NC} Presence indicators enabled"
    echo -e "${GREEN}${CHECK}${NC} 5-minute message redaction window"
    echo -e "${GREEN}${CHECK}${NC} 90-day media auto-cleanup"
    echo -e "${GREEN}${CHECK}${NC} Admin cannot access encrypted messages"

    echo ""
}

show_configuration_summary() {
    show_header "${STAR} CONFIGURATION SUMMARY"

    echo -e "${WHITE}${BOLD}Deployment Configuration:${NC}"
    echo -e "${BLUE}Environment:${NC} $ENVIRONMENT"
    echo -e "${BLUE}Type:${NC} $DEPLOYMENT_TYPE"
    echo -e "${BLUE}Method:${NC} $([ "$USE_LOCAL_DEPLOYMENT" = "true" ] && echo "Local" || echo "Remote")"
    echo ""

    echo -e "${WHITE}${BOLD}Domain Configuration:${NC}"
    echo -e "${BLUE}Matrix Domain:${NC} $MATRIX_DOMAIN"
    echo -e "${BLUE}Homeserver:${NC} $HOMESERVER_DOMAIN"
    echo -e "${BLUE}SSL Email:${NC} $SSL_EMAIL"
    echo ""

    echo -e "${WHITE}${BOLD}Server Configuration:${NC}"
    echo -e "${BLUE}Server IP:${NC} $SERVER_IP"
    echo -e "${BLUE}SSH Port:${NC} $SSH_PORT"
    echo ""

    echo -e "${WHITE}${BOLD}Admin Configuration:${NC}"
    echo -e "${BLUE}Username:${NC} $ADMIN_USERNAME"
    echo -e "${BLUE}Password:${NC} $([ ${#ADMIN_PASSWORD} -gt 0 ] && echo "Set (hidden)" || echo "Not set")"
    echo -e "${BLUE}Registration:${NC} $ENABLE_REGISTRATION"
    echo -e "${BLUE}System User:${NC} $CREATE_USER"
    echo ""

    echo -e "${WHITE}${BOLD}Security Features:${NC}"
    echo -e "${GREEN}${CHECK}${NC} SSH hardening & custom port"
    echo -e "${GREEN}${CHECK}${NC} UFW firewall configuration"
    echo -e "${GREEN}${CHECK}${NC} Fail2Ban intrusion detection"
    echo -e "${GREEN}${CHECK}${NC} Auto SSL certificate renewal"
    echo -e "${GREEN}${CHECK}${NC} Privacy-focused logging"
    echo -e "${GREEN}${CHECK}${NC} Encrypted vault storage"
    echo ""
}

generate_configuration_files() {
    show_header "${GEAR} GENERATING CONFIGURATION"

    show_step "Creating inventory file..."

    # Create inventory directory
    mkdir -p "inventory/$ENVIRONMENT"

    # Generate hosts.yml
    cat > "inventory/$ENVIRONMENT/hosts.yml" << EOF
---
# Matrix Server Inventory - $ENVIRONMENT
# Generated by TUI Configuration Wizard

all:
  children:
    matrix_servers:
      hosts:
        $([ "$USE_LOCAL_DEPLOYMENT" = "true" ] && echo "localhost:" || echo "$HOMESERVER_DOMAIN:")
          $([ "$USE_LOCAL_DEPLOYMENT" = "true" ] && echo "ansible_connection: local" || echo "ansible_host: $SERVER_IP")
          ansible_python_interpreter: /usr/bin/python3
          $([ "$USE_LOCAL_DEPLOYMENT" = "false" ] && echo "ansible_ssh_port: $SSH_PORT")
          $([ "$USE_LOCAL_DEPLOYMENT" = "false" ] && echo "ansible_user: root")
          $([ "$USE_LOCAL_DEPLOYMENT" = "false" ] && echo "ansible_ssh_private_key_file: ~/.ssh/id_rsa")

          # Matrix configuration
          matrix_domain: "$MATRIX_DOMAIN"
          matrix_homeserver_name: "$HOMESERVER_DOMAIN"

      vars:
        # Global settings
        ansible_become: yes
        ansible_become_method: sudo
        $([ "$USE_LOCAL_DEPLOYMENT" = "false" ] && echo "ansible_ssh_pipelining: true")
        $([ "$USE_LOCAL_DEPLOYMENT" = "false" ] && echo "ansible_ssh_common_args: '-o StrictHostKeyChecking=no'")

        # Deployment settings
        gather_facts: yes
        host_key_checking: false
EOF

    show_success "Inventory file created"

    show_step "Creating group variables..."

    # Create group_vars directory
    mkdir -p "inventory/$ENVIRONMENT/group_vars/all"

    # Generate all.yml
    cat > "inventory/$ENVIRONMENT/group_vars/all.yml" << EOF
---
# Global configuration for $ENVIRONMENT environment
# Generated by TUI Configuration Wizard

# Environment settings
timezone: "UTC"
environment: "$ENVIRONMENT"

# Security settings
ssh_port: $SSH_PORT
ssh_max_auth_tries: 3
ssh_client_alive_interval: 300
ssh_client_alive_count_max: 2
ssh_login_grace_time: 60

# Fail2Ban settings
fail2ban_enabled: true
fail2ban_bantime: 3600
fail2ban_findtime: 600
fail2ban_maxretry: 5

# Firewall settings
ufw_enabled: true
ufw_default_policy_incoming: deny
ufw_default_policy_outgoing: allow
ufw_default_policy_forward: deny

# System hardening
disable_ipv6: false
kernel_hardening_enabled: true
sysctl_hardening_enabled: true

# Automatic updates
unattended_upgrades_enabled: true
auto_reboot_if_required: true
auto_reboot_time: "03:00"

# Monitoring
monitoring_enabled: true
monitoring_email: "{{ vault_ssl_email }}"
log_retention_days: 30

# Matrix Server Configuration
matrix_domain: "$MATRIX_DOMAIN"
matrix_homeserver_name: "$HOMESERVER_DOMAIN"
ssl_email: "{{ vault_ssl_email }}"

# Matrix settings
matrix_registration_enabled: $ENABLE_REGISTRATION

# Admin user configuration
admin_username: "{{ vault_admin_username }}"
admin_user_password: "{{ vault_admin_password }}"
create_user: "$CREATE_USER"

# Database and secrets (from vault)
matrix_database_password: "{{ vault_matrix_database_password }}"
form_secret: "{{ vault_form_secret }}"
macaroon_secret_key: "{{ vault_macaroon_secret_key }}"
registration_secret: "{{ vault_registration_secret }}"
coturn_secret: "{{ vault_coturn_secret }}"

# Privacy settings (pre-configured)
matrix_presence_enabled: true
matrix_redaction_retention_period: 300  # 5 minutes
matrix_media_retention_days: 90
matrix_log_filter_ips: true
matrix_registration_requires_email: false
matrix_registration_requires_captcha: false
EOF

    show_success "Group variables created"

    show_step "Generating secrets..."

    # Generate all secrets
    DB_PASSWORD=$(openssl rand -hex 16)
    FORM_SECRET=$(openssl rand -hex 32)
    MACAROON_SECRET=$(openssl rand -hex 32)
    REGISTRATION_SECRET=$(openssl rand -hex 16)
    COTURN_SECRET=$(openssl rand -hex 16)

    # Generate vault password
    VAULT_PASSWORD=$(openssl rand -base64 32)
    echo "$VAULT_PASSWORD" > .vault_pass
    chmod 600 .vault_pass

    # Create vault file using helper
    if ! ./vault-helper.sh "$ENVIRONMENT" "$SSL_EMAIL" "$ADMIN_USERNAME" "$ADMIN_PASSWORD" "$DB_PASSWORD" "$FORM_SECRET" "$MACAROON_SECRET" "$REGISTRATION_SECRET" "$COTURN_SECRET"; then
        show_error "Failed to create vault file"
        return 1
    fi

    show_success "Secrets generated and encrypted"
    show_info "Vault password saved to: .vault_pass"

    echo ""
}

run_deployment() {
    show_header "${ROCKET} DEPLOYMENT"

    show_info "Starting one-shot deployment..."
    echo ""

    # Pre-flight check
    show_step "Running pre-flight checks..."
    if [ -f "./pre-flight-check.sh" ]; then
        if ./pre-flight-check.sh "$ENVIRONMENT" 2>/dev/null; then
            show_success "Pre-flight checks passed"
        else
            show_error "Pre-flight checks found issues (continuing anyway)"
        fi
    fi

    echo ""

    # Run deployment
    show_step "Executing deployment..."

    DEPLOY_START=$(date +%s)

    if [ -f "./smart-deploy.sh" ]; then
        # Use smart deployment
        show_info "Using intelligent deployment system..."
        ./smart-deploy.sh "$ENVIRONMENT" "site-fixed" "true"
    elif [ -f "./deploy-matrix.sh" ]; then
        # Use simple deployment
        show_info "Using simple deployment system..."
        ./deploy-matrix.sh "$ENVIRONMENT" "site-fixed"
    else
        # Direct ansible
        show_info "Using direct Ansible deployment..."
        ansible-playbook -i "inventory/$ENVIRONMENT/hosts.yml" "playbooks/site-fixed.yml" --vault-password-file .vault_pass -v
    fi

    DEPLOY_END=$(date +%s)
    DEPLOY_TIME=$((DEPLOY_END - DEPLOY_START))

    echo ""
    show_success "Deployment completed in ${DEPLOY_TIME} seconds!"

    echo ""
}

show_final_summary() {
    show_header "${STAR} DEPLOYMENT COMPLETE!"

    echo -e "${GREEN}${BOLD}🎉 Your Matrix server is now running!${NC}"
    echo ""

    echo -e "${WHITE}${BOLD}Access Information:${NC}"
    echo -e "${CYAN}${ARROW}${NC} Element Web: ${YELLOW}https://$MATRIX_DOMAIN${NC}"
    echo -e "${CYAN}${ARROW}${NC} Homeserver: ${YELLOW}https://$HOMESERVER_DOMAIN${NC}"
    echo -e "${CYAN}${ARROW}${NC} Admin Panel: ${YELLOW}https://$HOMESERVER_DOMAIN/_synapse/admin/${NC}"
    echo ""

    echo -e "${WHITE}${BOLD}Admin Account:${NC}"
    echo -e "${CYAN}${ARROW}${NC} Username: ${YELLOW}$ADMIN_USERNAME${NC}"
    echo -e "${CYAN}${ARROW}${NC} Password: ${YELLOW}$ADMIN_PASSWORD${NC}"
    echo ""

    echo -e "${WHITE}${BOLD}Important Commands:${NC}"
    echo -e "${CYAN}${ARROW}${NC} Create user: ${YELLOW}sudo /usr/local/bin/create-matrix-admin.sh username password${NC}"
    echo -e "${CYAN}${ARROW}${NC} Check status: ${YELLOW}systemctl status matrix-synapse${NC}"
    echo -e "${CYAN}${ARROW}${NC} View logs: ${YELLOW}journalctl -u matrix-synapse -f${NC}"
    echo ""

    echo -e "${WHITE}${BOLD}Next Steps:${NC}"
    echo -e "${GREEN}1.${NC} Configure DNS records:"
    echo -e "   ${BLUE}$MATRIX_DOMAIN${NC} → ${YELLOW}$SERVER_IP${NC}"
    echo -e "   ${BLUE}$HOMESERVER_DOMAIN${NC} → ${YELLOW}$SERVER_IP${NC}"
    echo ""
    echo -e "${GREEN}2.${NC} Test federation: ${YELLOW}https://federationtester.matrix.org/${NC}"
    echo ""
    echo -e "${GREEN}3.${NC} Access Element web client: ${YELLOW}https://$MATRIX_DOMAIN${NC}"
    echo ""

    echo -e "${WHITE}${BOLD}Files Created:${NC}"
    echo -e "${CYAN}${ARROW}${NC} Configuration: ${YELLOW}inventory/$ENVIRONMENT/${NC}"
    echo -e "${CYAN}${ARROW}${NC} Vault password: ${YELLOW}.vault_pass${NC}"
    echo -e "${CYAN}${ARROW}${NC} Deployment logs in system journals"
    echo ""
}

# Main execution flow
main() {
    # Check prerequisites
    if [ ! -f "roles/matrix_server/tasks/main.yml" ]; then
        show_error "Please run this from the matrix-server-ansible directory"
        exit 1
    fi

    # Configuration steps
    configure_deployment_type
    configure_environment
    configure_domains
    configure_server
    configure_admin
    configure_security

    # Show summary and confirm
    show_configuration_summary

    echo ""
    echo -e "${WHITE}${BOLD}Ready to deploy!${NC}"
    echo -ne "${YELLOW}Proceed with one-shot deployment? (y/N): ${NC}"
    read CONFIRM

    if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
        generate_configuration_files
        run_deployment
        show_final_summary
    else
        echo ""
        show_info "Configuration saved. Run ./deploy-matrix.sh $ENVIRONMENT when ready."
        echo -e "${BLUE}Configuration files created in: inventory/$ENVIRONMENT/${NC}"
    fi
}

# Run main function
main "$@"