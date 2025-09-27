#!/bin/bash
# Simple Matrix Deployment Script
# No fancy features, just deploys the Matrix server

set -e

echo "=========================================="
echo "  MATRIX SERVER DEPLOYMENT"
echo "=========================================="
echo ""

# Check we're in the right place
if [ ! -f "scripts/deploy.sh" ]; then
    echo "ERROR: Run this from the matrix-server-ansible directory"
    exit 1
fi

ENVIRONMENT="${1:-production}"
PLAYBOOK="${2:-site}"

echo "Environment: $ENVIRONMENT"
echo "Playbook: $PLAYBOOK"
echo ""

# Check inventory exists
INVENTORY="inventory/$ENVIRONMENT/hosts.yml"
if [ ! -f "$INVENTORY" ]; then
    echo "ERROR: Inventory file not found: $INVENTORY"
    echo ""
    echo "Create it by copying the example:"
    echo "  cp inventory/$ENVIRONMENT/hosts.yml.example $INVENTORY"
    echo "  nano $INVENTORY"
    exit 1
fi

# Check vault exists
VAULT_FILE="inventory/$ENVIRONMENT/group_vars/all/vault.yml"
if [ ! -f "$VAULT_FILE" ]; then
    echo "ERROR: Vault file not found: $VAULT_FILE"
    echo ""
    echo "Generate secrets first:"
    echo "  ./setup-matrix-secrets.sh"
    exit 1
fi

# Check vault password
if [ -f ".vault_pass" ]; then
    VAULT_OPTS="--vault-password-file .vault_pass"
    echo "✓ Using vault password file: .vault_pass"
else
    VAULT_OPTS="--ask-vault-pass"
    echo "! No .vault_pass file found, will prompt for password"
fi

# Check ansible
if ! command -v ansible-playbook >/dev/null 2>&1; then
    echo "ERROR: ansible-playbook not found"
    echo "Install with: apt install ansible"
    exit 1
fi

echo ""

# Test connectivity
echo "Testing server connectivity..."
if ansible all -i "$INVENTORY" -m ping $VAULT_OPTS >/dev/null 2>&1; then
    echo "✓ Server connectivity OK"
else
    echo "WARNING: Server connectivity test failed"
    echo "This might be normal if the server isn't fully configured yet"
fi

echo ""

# Show what will be deployed
echo "Deployment details:"
echo "  Inventory: $INVENTORY"
echo "  Playbook:  playbooks/$PLAYBOOK.yml"
echo "  Vault:     $VAULT_FILE"
echo ""

# Confirm
echo -n "Proceed with deployment? (y/N): "
read CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Deployment cancelled"
    exit 0
fi

echo ""
echo "Starting deployment..."
echo "======================"

# Run deployment
START_TIME=$(date +%s)

if ansible-playbook \
    -i "$INVENTORY" \
    "playbooks/$PLAYBOOK.yml" \
    $VAULT_OPTS \
    -v; then

    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))

    echo ""
    echo "=========================================="
    echo "  DEPLOYMENT COMPLETED SUCCESSFULLY!"
    echo "=========================================="
    echo ""
    echo "Deployment time: ${DURATION} seconds"
    echo ""

    # Show Matrix info
    echo "Your Matrix server should now be running!"
    echo ""
    echo "Next steps:"
    echo "  1. Check services: systemctl status matrix-synapse"
    echo "  2. Create admin user: sudo /usr/local/bin/create-matrix-admin.sh admin password"
    echo "  3. Test at: https://$(grep matrix_domain inventory/$ENVIRONMENT/group_vars/all.yml | cut -d'"' -f2 2>/dev/null || echo 'your-domain')"
    echo ""

else
    echo ""
    echo "=========================================="
    echo "  DEPLOYMENT FAILED"
    echo "=========================================="
    echo ""
    echo "Check the output above for errors."
    echo ""
    echo "Common issues:"
    echo "  - Server not accessible via SSH"
    echo "  - Incorrect vault password"
    echo "  - Domain DNS not configured"
    echo "  - Firewall blocking connections"
    echo ""
    exit 1
fi