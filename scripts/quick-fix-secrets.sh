#!/bin/bash
# Quick Fix for Secret Generation on Debian Server
# Run this on your Debian 12 server to resolve secret generation issues

set -euo pipefail

echo "Matrix Server Secret Generation Quick Fix"
echo "========================================"
echo ""

# Check if we're in the right directory
if [ ! -f "scripts/deploy.sh" ]; then
    echo "ERROR: Run this from the matrix-server-ansible directory"
    echo "Usage: cd /root/matrix-server-ansible && bash scripts/quick-fix-secrets.sh"
    exit 1
fi

ENVIRONMENT="${1:-production}"
VAULT_FILE="inventory/$ENVIRONMENT/group_vars/all/vault.yml"

echo "Environment: $ENVIRONMENT"
echo "Vault file: $VAULT_FILE"
echo ""

# Install dependencies if missing
echo "Checking and installing dependencies..."
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

# Generate secrets using direct OpenSSL
echo "Generating secrets..."
DB_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/\n" | head -c 32)
FORM_SECRET=$(openssl rand -base64 64 | tr -d "=+/\n" | head -c 64)
MACAROON_SECRET=$(openssl rand -base64 64 | tr -d "=+/\n" | head -c 64)
REGISTRATION_SECRET=$(openssl rand -base64 32 | tr -d "=+/\n" | head -c 32)
COTURN_SECRET=$(openssl rand -base64 32 | tr -d "=+/\n" | head -c 32)
ADMIN_PASSWORD=$(openssl rand -base64 16 | tr -d "=+/\n" | head -c 16)

echo "✓ Secrets generated"
echo ""

# Get user input
echo -n "Enter admin username (default: admin): "
read ADMIN_USER
ADMIN_USER="${ADMIN_USER:-admin}"

echo -n "Enter your domain for Element web (e.g. chat.yourdomain.com): "
read MATRIX_DOMAIN

echo -n "Enter your Matrix homeserver domain (e.g. matrix.yourdomain.com): "
read MATRIX_HOMESERVER

echo -n "Enter SSL/admin email: "
read SSL_EMAIL

while [ -z "$SSL_EMAIL" ]; do
    echo "SSL email is required for Let's Encrypt certificates"
    echo -n "Enter SSL/admin email: "
    read SSL_EMAIL
done

# Create directory
mkdir -p "$(dirname "$VAULT_FILE")"

# Create vault content
cat > "$VAULT_FILE.tmp" <<EOF
---
# Matrix Server Secrets - $ENVIRONMENT
# Generated on $(date '+%Y-%m-%d %H:%M:%S')

# PostgreSQL Database
vault_matrix_database_password: "$DB_PASSWORD"

# Matrix Synapse Secrets
vault_form_secret: "$FORM_SECRET"
vault_macaroon_secret_key: "$MACAROON_SECRET"
vault_registration_secret: "$REGISTRATION_SECRET"

# Coturn (TURN server) Secret
vault_coturn_secret: "$COTURN_SECRET"

# Initial Admin User
vault_admin_username: "$ADMIN_USER"
vault_admin_password: "$ADMIN_PASSWORD"

# SSL and Contact Information
vault_ssl_email: "$SSL_EMAIL"
EOF

# Get vault password and encrypt
echo ""
echo "Enter a strong vault password to encrypt the secrets:"
echo "(This password will be used to decrypt secrets during deployment)"
ansible-vault encrypt "$VAULT_FILE.tmp" --output "$VAULT_FILE"
rm -f "$VAULT_FILE.tmp"

# Update inventory with domains
echo ""
echo "Updating inventory with your domains..."

# Update production inventory
if [ "$ENVIRONMENT" = "production" ]; then
    # Update all.yml with domains
    sed -i "s/chat\.example\.com/$MATRIX_DOMAIN/g" "inventory/production/group_vars/all.yml" 2>/dev/null || true
    sed -i "s/matrix\.example\.com/$MATRIX_HOMESERVER/g" "inventory/production/group_vars/all.yml" 2>/dev/null || true
fi

echo "✓ Inventory updated"
echo ""

echo "SUCCESS: Vault file created at $VAULT_FILE"
echo ""
echo "Generated admin credentials:"
echo "  Username: $ADMIN_USER"
echo "  Password: $ADMIN_PASSWORD"
echo "  Matrix Domain: $MATRIX_DOMAIN"
echo "  Homeserver: $MATRIX_HOMESERVER"
echo "  Email: $SSL_EMAIL"
echo ""
echo "🔒 SAVE THESE CREDENTIALS SECURELY!"
echo ""

# Create vault password hint file
cat > ".vault_pass.template" <<EOF
# Add your vault password here, then rename to .vault_pass
# chmod 600 .vault_pass
# your_vault_password_here
EOF

echo "Next steps:"
echo "  1. Save your vault password to .vault_pass file (optional)"
echo "  2. Update your server IP in: nano inventory/$ENVIRONMENT/hosts.yml"
echo "  3. Deploy: ./scripts/deploy.sh"
echo ""
echo "To view vault: ansible-vault view $VAULT_FILE"
echo "To edit vault: ansible-vault edit $VAULT_FILE"
echo ""
echo "✅ Secret generation completed successfully!"