#!/bin/bash
# Bulletproof Matrix Server Secret Setup
# This script WILL work on any Debian/Ubuntu system
# No fancy features, just gets the job done

set -e

echo "=============================================="
echo "  MATRIX SERVER SECRET SETUP (BULLETPROOF)"
echo "=============================================="
echo ""

# Check we're in right place
if [ ! -f "scripts/deploy.sh" ]; then
    echo "ERROR: Run this from the matrix-server-ansible directory"
    exit 1
fi

ENVIRONMENT="${1:-production}"

# Install dependencies
echo "Installing dependencies..."
if ! command -v openssl >/dev/null 2>&1; then
    echo "Installing openssl..."
    apt update && apt install -y openssl
fi

if ! command -v ansible-vault >/dev/null 2>&1; then
    echo "Installing ansible..."
    apt update && apt install -y ansible
fi

echo "✓ Dependencies installed"
echo ""

# Generate secrets
echo "Generating secrets..."
DB_PASSWORD=$(openssl rand -hex 16)
FORM_SECRET=$(openssl rand -hex 32)
MACAROON_SECRET=$(openssl rand -hex 32)
REGISTRATION_SECRET=$(openssl rand -hex 16)
COTURN_SECRET=$(openssl rand -hex 16)
ADMIN_PASSWORD=$(openssl rand -hex 8)

echo "✓ Secrets generated"
echo ""

# Get configuration
echo "=== CONFIGURATION ==="
echo -n "Enter your Element web domain (e.g., chat.yourdomain.com): "
read ELEMENT_DOMAIN

echo -n "Enter your Matrix homeserver domain (e.g., matrix.yourdomain.com): "
read MATRIX_HOMESERVER

echo -n "Enter your email for SSL certificates: "
read SSL_EMAIL

echo -n "Enter admin username [admin]: "
read ADMIN_USER
ADMIN_USER=${ADMIN_USER:-admin}

echo ""

# Create vault directory
mkdir -p "inventory/$ENVIRONMENT/group_vars/all"

# Create vault content
cat > "/tmp/matrix_vault_$$.yml" <<EOF
---
# Matrix Server Secrets for $ENVIRONMENT
# Generated: $(date)

# Database
vault_matrix_database_password: "$DB_PASSWORD"

# Matrix secrets
vault_form_secret: "$FORM_SECRET"
vault_macaroon_secret_key: "$MACAROON_SECRET"
vault_registration_secret: "$REGISTRATION_SECRET"

# TURN server
vault_coturn_secret: "$COTURN_SECRET"

# Admin user
vault_admin_username: "$ADMIN_USER"
vault_admin_password: "$ADMIN_PASSWORD"

# SSL
vault_ssl_email: "$SSL_EMAIL"
EOF

# Get vault password
echo "=== VAULT ENCRYPTION ==="
echo "Choose a strong password to encrypt your secrets:"
echo -n "Vault password: "
read -s VAULT_PASSWORD
echo ""
echo -n "Confirm vault password: "
read -s VAULT_PASSWORD_CONFIRM
echo ""

if [ "$VAULT_PASSWORD" != "$VAULT_PASSWORD_CONFIRM" ]; then
    echo "ERROR: Passwords don't match"
    rm "/tmp/matrix_vault_$$.yml"
    exit 1
fi

# Encrypt vault
echo "$VAULT_PASSWORD" | ansible-vault encrypt "/tmp/matrix_vault_$$.yml" --output "inventory/$ENVIRONMENT/group_vars/all/vault.yml" --vault-password-file /dev/stdin

# Clean up
rm "/tmp/matrix_vault_$$.yml"

# Save vault password
echo "$VAULT_PASSWORD" > .vault_pass
chmod 600 .vault_pass

# Update configuration files
echo ""
echo "Updating configuration..."

# Update all.yml with domains
if grep -q "chat.example.com" "inventory/$ENVIRONMENT/group_vars/all.yml"; then
    sed -i "s/chat\.example\.com/$ELEMENT_DOMAIN/g" "inventory/$ENVIRONMENT/group_vars/all.yml"
fi

if grep -q "matrix.example.com" "inventory/$ENVIRONMENT/group_vars/all.yml"; then
    sed -i "s/matrix\.example\.com/$MATRIX_HOMESERVER/g" "inventory/$ENVIRONMENT/group_vars/all.yml"
fi

echo "✓ Configuration updated"
echo ""

# Test vault
echo "Testing vault..."
if echo "$VAULT_PASSWORD" | ansible-vault view "inventory/$ENVIRONMENT/group_vars/all/vault.yml" --vault-password-file /dev/stdin >/dev/null 2>&1; then
    echo "✓ Vault created and tested successfully"
else
    echo "ERROR: Vault test failed"
    exit 1
fi

echo ""
echo "==============================================="
echo "  SUCCESS! Matrix secrets configured"
echo "==============================================="
echo ""
echo "Your Matrix server details:"
echo "  Element web:  https://$ELEMENT_DOMAIN"
echo "  Homeserver:   https://$MATRIX_HOMESERVER"
echo "  Admin user:   $ADMIN_USER"
echo "  Admin pass:   $ADMIN_PASSWORD"
echo "  SSL email:    $SSL_EMAIL"
echo ""
echo "🔐 SAVE THESE CREDENTIALS!"
echo ""
echo "Files created:"
echo "  ✓ inventory/$ENVIRONMENT/group_vars/all/vault.yml (encrypted)"
echo "  ✓ .vault_pass (vault password file)"
echo ""
echo "Next steps:"
echo "  1. Edit inventory/$ENVIRONMENT/hosts.yml with your server IP"
echo "  2. Run: ./scripts/deploy.sh"
echo ""
echo "Vault commands:"
echo "  View: ansible-vault view inventory/$ENVIRONMENT/group_vars/all/vault.yml"
echo "  Edit: ansible-vault edit inventory/$ENVIRONMENT/group_vars/all/vault.yml"
echo ""