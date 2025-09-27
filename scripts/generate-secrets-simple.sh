#!/bin/bash
# Simple Matrix Server Secret Generation Script
# Fallback version with minimal dependencies
# Usage: ./scripts/generate-secrets-simple.sh [environment]

set -euo pipefail

ENVIRONMENT="${1:-production}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VAULT_FILE="$PROJECT_ROOT/inventory/$ENVIRONMENT/group_vars/all/vault.yml"
VAULT_DIR="$(dirname "$VAULT_FILE")"

echo "Simple Matrix Server Secret Generation"
echo "====================================="
echo ""
echo "Environment: $ENVIRONMENT"
echo "Vault file: $VAULT_FILE"
echo ""

# Check dependencies
if ! command -v openssl >/dev/null 2>&1; then
    echo "ERROR: openssl not found. Install with: sudo apt install openssl"
    exit 1
fi

if ! command -v ansible-vault >/dev/null 2>&1; then
    echo "ERROR: ansible-vault not found. Install with: sudo apt install ansible"
    exit 1
fi

# Generate secrets using only openssl
echo "Generating secrets..."
DB_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/\n" | cut -c1-32)
FORM_SECRET=$(openssl rand -base64 64 | tr -d "=+/\n" | cut -c1-64)
MACAROON_SECRET=$(openssl rand -base64 64 | tr -d "=+/\n" | cut -c1-64)
REGISTRATION_SECRET=$(openssl rand -base64 32 | tr -d "=+/\n" | cut -c1-32)
COTURN_SECRET=$(openssl rand -base64 32 | tr -d "=+/\n" | cut -c1-32)
ADMIN_PASSWORD=$(openssl rand -base64 16 | tr -d "=+/\n" | cut -c1-16)

# Get user input
echo -n "Enter admin username (default: admin): "
read ADMIN_USER
ADMIN_USER="${ADMIN_USER:-admin}"

echo -n "Enter SSL/admin email: "
read SSL_EMAIL

while [ -z "$SSL_EMAIL" ]; do
    echo "SSL email is required for Let's Encrypt certificates"
    echo -n "Enter SSL/admin email: "
    read SSL_EMAIL
done

# Create directory
mkdir -p "$VAULT_DIR"

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

# Get vault password
echo ""
echo "Enter vault password to encrypt the secrets:"
ansible-vault encrypt "$VAULT_FILE.tmp" --output "$VAULT_FILE"
rm -f "$VAULT_FILE.tmp"

# Create .vault_pass template
cat > "$PROJECT_ROOT/.vault_pass.template" <<EOF
# Ansible Vault Password File
#
# 1. Add your vault password to this file (single line)
# 2. Rename to .vault_pass
# 3. Set permissions: chmod 600 .vault_pass
#
# Example:
# your_vault_password_here
EOF

echo ""
echo "SUCCESS: Vault file created at $VAULT_FILE"
echo ""
echo "Generated admin credentials:"
echo "  Username: $ADMIN_USER"
echo "  Password: $ADMIN_PASSWORD"
echo "  Email: $SSL_EMAIL"
echo ""
echo "SAVE THESE CREDENTIALS SECURELY!"
echo ""
echo "Next steps:"
echo "  1. Edit your inventory: nano inventory/$ENVIRONMENT/hosts.yml"
echo "  2. Update domains in: nano inventory/$ENVIRONMENT/group_vars/all.yml"
echo "  3. Deploy: ./scripts/deploy.sh"
echo ""
echo "To view vault: ansible-vault view $VAULT_FILE"
echo "To edit vault: ansible-vault edit $VAULT_FILE"