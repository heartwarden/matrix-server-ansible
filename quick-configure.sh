#!/bin/bash
# Quick Matrix Configuration - Simple prompts without complex TUI

set -e

echo "🚀 Quick Matrix Server Configuration"
echo "===================================="
echo ""

# Simple prompts
echo -n "Matrix domain (where Element web will be hosted): "
read MATRIX_DOMAIN

echo -n "Homeserver domain (Matrix federation domain): "
read HOMESERVER_DOMAIN

echo -n "SSL certificate email: "
read SSL_EMAIL

echo -n "Admin username [admin]: "
read ADMIN_USERNAME
ADMIN_USERNAME=${ADMIN_USERNAME:-admin}

echo -n "Admin password (leave empty for auto-generation): "
read -s ADMIN_PASSWORD
echo ""

if [ -z "$ADMIN_PASSWORD" ]; then
    ADMIN_PASSWORD=$(openssl rand -base64 12)
    echo "Auto-generated password: $ADMIN_PASSWORD"
fi

echo -n "Enable user registration? (y/N): "
read ENABLE_REG
if [[ "$ENABLE_REG" =~ ^[Yy]$ ]]; then
    ENABLE_REGISTRATION="true"
else
    ENABLE_REGISTRATION="false"
fi

echo -n "System user to create [zerokaine]: "
read CREATE_USER
CREATE_USER=${CREATE_USER:-zerokaine}

echo ""
echo "Configuration Summary:"
echo "======================"
echo "Matrix Domain: $MATRIX_DOMAIN"
echo "Homeserver: $HOMESERVER_DOMAIN"
echo "SSL Email: $SSL_EMAIL"
echo "Admin User: $ADMIN_USERNAME"
echo "Registration: $ENABLE_REGISTRATION"
echo "System User: $CREATE_USER"
echo ""

echo -n "Proceed with deployment? (y/N): "
read CONFIRM

if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Creating configuration files..."

    # Create inventory directory
    mkdir -p "inventory/production"

    # Generate hosts.yml
    cat > "inventory/production/hosts.yml" << EOF
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

    # Create group_vars directory
    mkdir -p "inventory/production/group_vars/all"

    # Generate all.yml
    cat > "inventory/production/group_vars/all.yml" << EOF
---
# Matrix Server Configuration
matrix_domain: "$MATRIX_DOMAIN"
matrix_homeserver_name: "$HOMESERVER_DOMAIN"
ssl_email: "{{ vault_ssl_email }}"

# Security settings
ssh_port: 2222
fail2ban_enabled: true
ufw_enabled: true

# Matrix settings
matrix_registration_enabled: $ENABLE_REGISTRATION

# Admin user configuration
admin_username: "{{ vault_admin_username }}"
create_user: "$CREATE_USER"

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

    # Generate secrets
    echo "Generating secrets..."
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
    echo "Creating encrypted vault file..."

    # Simple approach - create vault file directly
    cat > "/tmp/vault_secrets.yml" << EOF
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

    # Create vault file with ansible-vault
    if ansible-vault create "inventory/production/group_vars/all/vault.yml" --vault-password-file .vault_pass < "/tmp/vault_secrets.yml" 2>/dev/null; then
        echo "✅ Vault file created successfully"
    else
        echo "Warning: ansible-vault create failed, trying alternative method..."
        # Alternative: encrypt the file after creation
        cp "/tmp/vault_secrets.yml" "inventory/production/group_vars/all/vault.yml"
        ansible-vault encrypt "inventory/production/group_vars/all/vault.yml" --vault-password-file .vault_pass 2>/dev/null || {
            echo "❌ Failed to create vault file"
            rm -f "/tmp/vault_secrets.yml"
            exit 1
        }
        echo "✅ Vault file created with fallback method"
    fi

    # Clean up
    rm -f "/tmp/vault_secrets.yml"

    echo "✅ Configuration files created!"
    echo ""
    echo "🚀 Starting deployment..."

    # Deploy
    if [ -f "./smart-deploy.sh" ]; then
        ./smart-deploy.sh production site-fixed true
    else
        ./deploy-matrix.sh production site-fixed
    fi

    echo ""
    echo "🎉 Matrix server deployment complete!"
    echo ""
    echo "Admin credentials:"
    echo "Username: $ADMIN_USERNAME"
    echo "Password: $ADMIN_PASSWORD"
    echo ""
    echo "Configure DNS:"
    echo "$MATRIX_DOMAIN → $(hostname -I | awk '{print $1}')"
    echo "$HOMESERVER_DOMAIN → $(hostname -I | awk '{print $1}')"
    echo ""
    echo "Test at: https://$MATRIX_DOMAIN"

else
    echo "Configuration cancelled."
fi