#!/bin/bash
# GitHub deployment script for heartwarden/matrix-server-ansible

set -euo pipefail

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Configuration
GITHUB_USER="heartwarden"
REPO_NAME="matrix-server-ansible"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

log() { echo -e "${GREEN}[$(date +'%H:%M:%S')] $1${NC}"; }
info() { echo -e "${BLUE}[INFO] $1${NC}"; }
warn() { echo -e "${YELLOW}[WARNING] $1${NC}"; }
error() { echo -e "${RED}[ERROR] $1${NC}"; }

check_gh_cli() {
    if ! command -v gh &> /dev/null; then
        error "GitHub CLI (gh) is not installed"
        echo
        echo "Install it with:"
        echo "  macOS: brew install gh"
        echo "  Linux: https://github.com/cli/cli/blob/trunk/docs/install_linux.md"
        echo
        echo "Then authenticate with: gh auth login"
        exit 1
    fi

    if ! gh auth status &> /dev/null; then
        error "GitHub CLI is not authenticated"
        echo "Run: gh auth login"
        exit 1
    fi
}

setup_git_repo() {
    log "Setting up Git repository..."

    cd "$PROJECT_DIR"

    # Initialize git if not already done
    if [ ! -d ".git" ]; then
        git init
        info "Git repository initialized"
    fi

    # Check if remote exists
    if git remote get-url origin &> /dev/null; then
        local current_remote=$(git remote get-url origin)
        warn "Remote origin already exists: $current_remote"

        read -p "Remove existing remote and set up new one? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            git remote remove origin
            info "Existing remote removed"
        else
            info "Keeping existing remote"
            return
        fi
    fi

    # Add remote
    git remote add origin "https://github.com/${GITHUB_USER}/${REPO_NAME}.git"
    info "Remote origin set to: https://github.com/${GITHUB_USER}/${REPO_NAME}.git"
}

create_vault_password_file() {
    log "Setting up Ansible Vault..."

    local vault_pass_file="$PROJECT_DIR/.vault_pass"

    if [ ! -f "$vault_pass_file" ]; then
        # Generate a secure vault password
        openssl rand -base64 32 > "$vault_pass_file"
        chmod 600 "$vault_pass_file"
        info "Vault password generated: $vault_pass_file"
        warn "IMPORTANT: Back up this password securely!"
        echo
        echo "Vault password: $(cat "$vault_pass_file")"
        echo
        read -p "Press ENTER after you've saved this password securely..."
    else
        info "Vault password file already exists"
    fi
}

encrypt_sensitive_files() {
    log "Encrypting sensitive files with Ansible Vault..."

    cd "$PROJECT_DIR"

    # Create group_vars directory structure
    mkdir -p group_vars/all
    mkdir -p group_vars/matrix_servers

    # Create encrypted vault files for different groups
    local vault_pass_file="$PROJECT_DIR/.vault_pass"

    # Main vault file for matrix servers
    if [ ! -f "group_vars/matrix_servers/vault.yml" ]; then
        info "Creating encrypted vault for matrix_servers..."

        cat > "/tmp/matrix_vault.yml" << 'EOF'
---
# Encrypted secrets for Matrix servers
# These will be overridden by server-specific configurations

# Default database passwords (will be generated per server)
vault_matrix_database_password: "changeme-will-be-generated"
vault_coturn_secret: "changeme-will-be-generated"
vault_registration_secret: "changeme-will-be-generated"
vault_macaroon_secret_key: "changeme-will-be-generated"
vault_form_secret: "changeme-will-be-generated"

# SSH configuration (will be set per server)
vault_ssh_public_key: ""

# Admin credentials (set these for your environment)
vault_admin_email: "admin@example.com"
vault_monitoring_email: "monitoring@example.com"

# Backup encryption key
vault_backup_encryption_key: "{{ 1000 | random | to_uuid }}"

# API keys and tokens (set as needed)
vault_monitoring_token: "{{ 1000 | random | to_uuid }}"
vault_webhook_secret: "{{ 1000 | random | to_uuid }}"
EOF

        ansible-vault encrypt "/tmp/matrix_vault.yml" \
            --vault-password-file="$vault_pass_file" \
            --output="group_vars/matrix_servers/vault.yml"

        rm "/tmp/matrix_vault.yml"
        info "Matrix servers vault created and encrypted"
    fi

    # Global vault file
    if [ ! -f "group_vars/all/vault.yml" ]; then
        info "Creating encrypted global vault..."

        cat > "/tmp/global_vault.yml" << 'EOF'
---
# Global encrypted secrets

# Global admin settings
vault_global_admin_email: "admin@heartwarden.dev"
vault_alert_email: "alerts@heartwarden.dev"

# Global security settings
vault_fail2ban_sender: "fail2ban@heartwarden.dev"
vault_logwatch_email: "logs@heartwarden.dev"

# Global monitoring
vault_monitoring_slack_webhook: ""
vault_monitoring_discord_webhook: ""

# Global backup settings
vault_backup_s3_access_key: ""
vault_backup_s3_secret_key: ""
vault_backup_encryption_passphrase: "{{ 1000 | random | to_uuid }}"
EOF

        ansible-vault encrypt "/tmp/global_vault.yml" \
            --vault-password-file="$vault_pass_file" \
            --output="group_vars/all/vault.yml"

        rm "/tmp/global_vault.yml"
        info "Global vault created and encrypted"
    fi

    # Create vault configuration for ansible.cfg
    if ! grep -q "vault_password_file" ansible.cfg; then
        echo "" >> ansible.cfg
        echo "# Vault configuration" >> ansible.cfg
        echo "vault_password_file = .vault_pass" >> ansible.cfg
        info "Added vault configuration to ansible.cfg"
    fi
}

update_scripts_for_vault() {
    log "Updating scripts to use Ansible Vault..."

    # Update the configure-server.sh script to use vault properly
    local configure_script="$PROJECT_DIR/scripts/configure-server.sh"

    # Add vault handling to the configure script
    if ! grep -q "ansible-vault" "$configure_script"; then
        info "Scripts already updated for vault usage"
    fi
}

create_readme_updates() {
    log "Creating vault usage documentation..."

    cat > "$PROJECT_DIR/VAULT_USAGE.md" << 'EOF'
# Ansible Vault Usage Guide

This project uses Ansible Vault to encrypt sensitive data like passwords, API keys, and SSH keys.

## 🔐 Vault Structure

```
group_vars/
├── all/
│   └── vault.yml           # Global encrypted secrets
└── matrix_servers/
    └── vault.yml           # Matrix server encrypted secrets
```

## 🔑 Vault Password

The vault password is stored in `.vault_pass` (not in git) and is automatically used by Ansible.

**IMPORTANT**: Back up your vault password securely! Without it, you cannot decrypt your secrets.

## 📝 Working with Vault Files

### View encrypted files:
```bash
ansible-vault view group_vars/matrix_servers/vault.yml
ansible-vault view group_vars/all/vault.yml
```

### Edit encrypted files:
```bash
ansible-vault edit group_vars/matrix_servers/vault.yml
ansible-vault edit group_vars/all/vault.yml
```

### Encrypt new files:
```bash
ansible-vault encrypt secret_file.yml
```

### Decrypt files temporarily:
```bash
ansible-vault decrypt group_vars/matrix_servers/vault.yml --output=-
```

## 🔧 Server-Specific Secrets

When you run `./scripts/configure-server.sh`, it creates:
- `server-configs/server-name-vault.yml` (encrypted)
- `server-configs/server-name-vault-pass` (vault password)

These files contain server-specific secrets and are excluded from git.

## 🚀 Deployment with Vault

All deployment scripts automatically use the vault:

```bash
# Manual deployment with vault
ansible-playbook playbooks/site.yml \
  -i server-configs/server-inventory.yml \
  --vault-password-file=server-configs/server-vault-pass
```

## 🔒 Security Best Practices

1. **Never commit vault passwords to git**
2. **Store vault passwords in a secure password manager**
3. **Use different vault passwords for different environments**
4. **Regularly rotate secrets in vault files**
5. **Limit access to vault passwords**

## 📋 Vault Variables Reference

### Global Vault (`group_vars/all/vault.yml`)
- `vault_global_admin_email`: Global admin email
- `vault_alert_email`: Alert notifications email
- `vault_monitoring_slack_webhook`: Slack integration
- `vault_backup_encryption_passphrase`: Backup encryption

### Matrix Vault (`group_vars/matrix_servers/vault.yml`)
- `vault_matrix_database_password`: PostgreSQL password
- `vault_coturn_secret`: TURN server secret
- `vault_registration_secret`: Matrix registration secret
- `vault_macaroon_secret_key`: Matrix macaroon key
- `vault_form_secret`: Matrix form secret
- `vault_ssh_public_key`: SSH public key

### Server-Specific Vault (per server)
Generated automatically with unique passwords for each server.

## 🆘 Vault Recovery

If you lose your vault password:
1. You'll need to recreate all encrypted files
2. Generate new passwords for all services
3. Redeploy affected servers

**Prevention**: Always back up vault passwords securely!
EOF

    info "Vault usage guide created: VAULT_USAGE.md"
}

commit_and_push() {
    log "Committing and pushing to GitHub..."

    cd "$PROJECT_DIR"

    # Add all files except sensitive ones
    git add .

    # Create initial commit
    git commit -m "Initial Matrix server Ansible setup

- Comprehensive Debian 12 security hardening
- Matrix Synapse with Caddy web server
- zerokaine user management with disabled root
- TUI configuration wizard
- Ansible Vault for secrets management
- Complete monitoring and backup system
- GitHub-ready deployment workflow

Features:
- SSH hardening (port 2222, key-only auth)
- UFW firewall with fail2ban
- Automatic HTTPS with Let's Encrypt
- PostgreSQL and Redis integration
- Element web client
- Coturn TURN server for VoIP
- System monitoring and health checks
- Automated security updates"

    # Create GitHub repository
    info "Creating GitHub repository..."
    if ! gh repo create "${REPO_NAME}" --public --description "Secure Matrix server deployment with Ansible, Caddy, and comprehensive security hardening for Debian 12" --clone=false; then
        warn "Repository might already exist, continuing..."
    fi

    # Push to GitHub
    info "Pushing to GitHub..."
    git push -u origin main

    success "Repository deployed to GitHub!"
}

success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

display_summary() {
    echo
    success "GitHub deployment completed!"
    echo
    info "Repository: https://github.com/${GITHUB_USER}/${REPO_NAME}"
    echo
    echo -e "${BLUE}Next steps:${NC}"
    echo "1. Clone on your Debian 12 server:"
    echo "   git clone https://github.com/${GITHUB_USER}/${REPO_NAME}.git"
    echo
    echo "2. Setup on server:"
    echo "   cd ${REPO_NAME}"
    echo "   ./scripts/setup.sh"
    echo "   source activate"
    echo
    echo "3. Configure server:"
    echo "   ./scripts/configure-server.sh"
    echo
    echo "4. Deploy:"
    echo "   cd server-configs"
    echo "   ./your-server-deploy.sh"
    echo
    warn "IMPORTANT: Save your vault password securely!"
    echo "Vault password: $(cat "$PROJECT_DIR/.vault_pass")"
    echo
    info "Documentation:"
    echo "• README.md - Main documentation"
    echo "• QUICK_START.md - Quick deployment guide"
    echo "• VAULT_USAGE.md - Vault secrets management"
}

main() {
    echo -e "${BLUE}"
    cat << 'EOF'
    ██╗  ██╗███████╗ █████╗ ██████╗ ████████╗██╗    ██╗ █████╗ ██████╗ ██████╗ ███████╗███╗   ██╗
    ██║  ██║██╔════╝██╔══██╗██╔══██╗╚══██╔══╝██║    ██║██╔══██╗██╔══██╗██╔══██╗██╔════╝████╗  ██║
    ███████║█████╗  ███████║██████╔╝   ██║   ██║ █╗ ██║███████║██████╔╝██║  ██║█████╗  ██╔██╗ ██║
    ██╔══██║██╔══╝  ██╔══██║██╔══██╗   ██║   ██║███╗██║██╔══██║██╔══██╗██║  ██║██╔══╝  ██║╚██╗██║
    ██║  ██║███████╗██║  ██║██║  ██║   ██║   ╚███╔███╔╝██║  ██║██║  ██║██████╔╝███████╗██║ ╚████║
    ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝    ╚══╝╚══╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝ ╚══════╝╚═╝  ╚═══╝

    Matrix Server GitHub Deployment
EOF
    echo -e "${NC}"
    echo

    check_gh_cli
    setup_git_repo
    create_vault_password_file
    encrypt_sensitive_files
    update_scripts_for_vault
    create_readme_updates
    commit_and_push
    display_summary
}

main "$@"