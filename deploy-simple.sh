#!/bin/bash
# Simple Matrix Deployment - No TUI, just prompts and deploy
# For when you just want to get Matrix running quickly

set -e

echo "🚀 Matrix Server Quick Deploy"
echo "============================="
echo ""

# Check if we're root
if [ "$EUID" -ne 0 ]; then
    echo "❌ Please run as root: sudo $0"
    exit 1
fi

# Get current directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Simple prompts
read -p "Matrix domain (where Element web will be hosted): " MATRIX_DOMAIN
read -p "Homeserver domain (Matrix federation domain): " HOMESERVER_DOMAIN
read -p "SSL certificate email: " SSL_EMAIL
read -p "Admin username [zerokaine]: " ADMIN_USERNAME
ADMIN_USERNAME=${ADMIN_USERNAME:-zerokaine}

echo -n "Admin password (leave empty for auto-generation): "
read -s ADMIN_PASSWORD
echo ""

if [ -z "$ADMIN_PASSWORD" ]; then
    ADMIN_PASSWORD=$(openssl rand -base64 12)
    echo "Auto-generated password: $ADMIN_PASSWORD"
fi

read -p "Enable user registration? (y/N): " ENABLE_REG
if [[ "$ENABLE_REG" =~ ^[Yy]$ ]]; then
    ENABLE_REGISTRATION="true"
else
    ENABLE_REGISTRATION="false"
fi

echo ""
echo "Configuration:"
echo "=============="
echo "Matrix Domain: $MATRIX_DOMAIN"
echo "Homeserver: $HOMESERVER_DOMAIN"
echo "SSL Email: $SSL_EMAIL"
echo "Admin User: $ADMIN_USERNAME"
echo "Registration: $ENABLE_REGISTRATION"
echo ""

read -p "Proceed with deployment? (y/N): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Deployment cancelled."
    exit 0
fi

echo ""
echo "🔧 Creating configuration..."

# Create directories
mkdir -p inventory/production/group_vars/all

# Create hosts.yml
cat > inventory/production/hosts.yml << EOF
---
all:
  children:
    matrix_servers:
      hosts:
        localhost:
          ansible_connection: local
          ansible_python_interpreter: /usr/bin/python3
          matrix_domain: "$MATRIX_DOMAIN"
          matrix_homeserver_name: "$HOMESERVER_DOMAIN"
      vars:
        ansible_become: yes
        ansible_become_method: sudo
        gather_facts: yes
        host_key_checking: false
EOF

# Create all.yml
cat > inventory/production/group_vars/all.yml << EOF
---
matrix_domain: "$MATRIX_DOMAIN"
matrix_homeserver_name: "$HOMESERVER_DOMAIN"
ssl_email: "{{ vault_ssl_email }}"

# Security settings
ssh_port: 2222
fail2ban_enabled: true
ufw_enabled: true

# Matrix settings
matrix_registration_enabled: $ENABLE_REGISTRATION

# Admin user
admin_username: "{{ vault_admin_username }}"
create_user: "zerokaine"

# Vault secrets
matrix_database_password: "{{ vault_matrix_database_password }}"
form_secret: "{{ vault_form_secret }}"
macaroon_secret_key: "{{ vault_macaroon_secret_key }}"
registration_secret: "{{ vault_registration_secret }}"
coturn_secret: "{{ vault_coturn_secret }}"

# Privacy settings
matrix_presence_enabled: true
matrix_redaction_retention_period: 300
matrix_media_retention_days: 90
matrix_log_filter_ips: true
matrix_registration_requires_email: false
matrix_registration_requires_captcha: false
EOF

echo "🔐 Generating secrets..."

# Generate secrets
DB_PASSWORD=$(openssl rand -hex 16)
FORM_SECRET=$(openssl rand -hex 32)
MACAROON_SECRET=$(openssl rand -hex 32)
REGISTRATION_SECRET=$(openssl rand -hex 16)
COTURN_SECRET=$(openssl rand -hex 16)

# Generate vault password
VAULT_PASSWORD=$(openssl rand -base64 32)
echo "$VAULT_PASSWORD" > .vault_pass
chmod 600 .vault_pass

# Create vault file
cat > inventory/production/group_vars/all/vault.yml << EOF
---
vault_ssl_email: "$SSL_EMAIL"
vault_admin_username: "$ADMIN_USERNAME"
vault_admin_password: "$ADMIN_PASSWORD"
vault_matrix_database_password: "$DB_PASSWORD"
vault_form_secret: "$FORM_SECRET"
vault_macaroon_secret_key: "$MACAROON_SECRET"
vault_registration_secret: "$REGISTRATION_SECRET"
vault_coturn_secret: "$COTURN_SECRET"
EOF

# Encrypt vault file
ansible-vault encrypt inventory/production/group_vars/all/vault.yml --vault-password-file .vault_pass

echo "✅ Configuration created!"
echo ""
echo "🚀 Starting deployment..."

# Use the best available playbook
PLAYBOOK="playbooks/site.yml"
if [ -f "playbooks/site-fixed.yml" ]; then
    PLAYBOOK="playbooks/site-fixed.yml"
fi

# Deploy
ansible-playbook -i inventory/production/hosts.yml "$PLAYBOOK" --vault-password-file .vault_pass -v

echo ""
echo "🎉 Matrix server deployment complete!"
echo ""
echo "Admin credentials:"
echo "Username: $ADMIN_USERNAME"
echo "Password: $ADMIN_PASSWORD"
echo ""
echo "Next steps:"
echo "1. Configure DNS:"
echo "   $MATRIX_DOMAIN → $(hostname -I | awk '{print $1}')"
echo "   $HOMESERVER_DOMAIN → $(hostname -I | awk '{print $1}')"
echo ""
echo "2. Test at: https://$MATRIX_DOMAIN"
echo ""
echo "3. Create more users:"
echo "   sudo /usr/local/bin/create-matrix-admin.sh username password"
echo ""
echo "4. Monitor services:"
echo "   systemctl status matrix-synapse caddy postgresql redis-server"
echo ""