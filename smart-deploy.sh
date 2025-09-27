#!/bin/bash
# Smart Matrix Deployment Script
# Automatically detects existing configurations and deploys safely

set -e

echo "==========================================="
echo "  SMART MATRIX DEPLOYMENT"
echo "==========================================="
echo ""

ENVIRONMENT="${1:-production}"
PLAYBOOK="${2:-site-fixed}"
SKIP_CHECKS="${3:-false}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

error() { echo -e "${RED}ERROR: $1${NC}"; }
warn() { echo -e "${YELLOW}WARNING: $1${NC}"; }
success() { echo -e "${GREEN}SUCCESS: $1${NC}"; }
info() { echo -e "${BLUE}INFO: $1${NC}"; }

# Check we're in the right place
if [ ! -f "deploy-matrix.sh" ] && [ ! -f "scripts/deploy.sh" ]; then
    error "Run this from the matrix-server-ansible directory"
    exit 1
fi

INVENTORY="inventory/$ENVIRONMENT/hosts.yml"
VAULT_FILE="inventory/$ENVIRONMENT/group_vars/all/vault.yml"

info "Environment: $ENVIRONMENT"
info "Playbook: $PLAYBOOK"
echo ""

# Pre-flight check unless skipped
if [ "$SKIP_CHECKS" != "true" ]; then
    info "Running pre-flight checks..."
    if [ -f "./pre-flight-check.sh" ]; then
        if ./pre-flight-check.sh "$ENVIRONMENT"; then
            success "Pre-flight checks passed"
        else
            warn "Pre-flight checks found issues"
            echo -n "Continue anyway? (y/N): "
            read CONTINUE
            if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
                info "Deployment cancelled"
                exit 0
            fi
        fi
    else
        warn "Pre-flight check script not found, proceeding anyway"
    fi
    echo ""
fi

# Check if this is a fresh install or update
DEPLOYMENT_TYPE="fresh"
if systemctl list-units --type=service | grep -q "matrix-synapse"; then
    DEPLOYMENT_TYPE="update"
    warn "Existing Matrix installation detected"
    info "Will perform update/reconfiguration deployment"
elif [ -d "/etc/matrix-synapse" ] || [ -d "/var/lib/matrix-synapse" ]; then
    DEPLOYMENT_TYPE="recovery"
    warn "Matrix files found but service not running"
    info "Will perform recovery deployment"
else
    success "Fresh installation detected"
    info "Will perform complete setup"
fi

echo ""

# Backup existing configurations if updating
if [ "$DEPLOYMENT_TYPE" != "fresh" ]; then
    info "Creating backup of existing configuration..."
    BACKUP_DIR="/root/matrix-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"

    # Backup important files
    for file in "/etc/matrix-synapse/homeserver.yaml" "/etc/caddy/Caddyfile" "/var/lib/matrix-synapse/signing.key"; do
        if [ -f "$file" ]; then
            cp "$file" "$BACKUP_DIR/" 2>/dev/null || true
            info "Backed up: $file"
        fi
    done

    # Backup database
    if systemctl is-active --quiet postgresql; then
        info "Backing up PostgreSQL database..."
        sudo -u postgres pg_dump synapse > "$BACKUP_DIR/synapse_backup.sql" 2>/dev/null || warn "Database backup failed (may not exist yet)"
    fi

    success "Backup created: $BACKUP_DIR"
    echo ""
fi

# Check vault file exists
if [ ! -f "$VAULT_FILE" ]; then
    warn "Vault file not found: $VAULT_FILE"
    info "Attempting to generate secrets..."

    if [ -f "./setup-matrix-secrets.sh" ]; then
        ./setup-matrix-secrets.sh "$ENVIRONMENT"
    else
        error "Cannot generate secrets - setup-matrix-secrets.sh not found"
        exit 1
    fi
fi

# Determine vault password method
if [ -f ".vault_pass" ]; then
    VAULT_OPTS="--vault-password-file .vault_pass"
    success "Using vault password file: .vault_pass"
else
    VAULT_OPTS="--ask-vault-pass"
    warn "No .vault_pass file found, will prompt for password"
fi

# Test connectivity
info "Testing server connectivity..."
if ansible all -i "$INVENTORY" -m ping $VAULT_OPTS >/dev/null 2>&1; then
    success "Server connectivity OK"
else
    warn "Server connectivity test failed"
    info "This might be normal if services aren't configured yet"
fi

echo ""

# Show deployment plan
echo "==========================================="
echo "  DEPLOYMENT PLAN"
echo "==========================================="
echo "Type: $DEPLOYMENT_TYPE"
echo "Inventory: $INVENTORY"
echo "Playbook: playbooks/$PLAYBOOK.yml"
echo "Vault: $VAULT_FILE"
if [ "$DEPLOYMENT_TYPE" != "fresh" ]; then
    echo "Backup: $BACKUP_DIR"
fi
echo ""

# Confirm deployment
echo -n "Proceed with deployment? (y/N): "
read CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    info "Deployment cancelled"
    exit 0
fi

echo ""
echo "==========================================="
echo "  STARTING DEPLOYMENT"
echo "==========================================="

# Record start time
START_TIME=$(date +%s)

# Run deployment with smart error handling
DEPLOYMENT_SUCCESS=false
RETRY_COUNT=0
MAX_RETRIES=2

while [ $RETRY_COUNT -le $MAX_RETRIES ] && [ "$DEPLOYMENT_SUCCESS" = "false" ]; do
    if [ $RETRY_COUNT -gt 0 ]; then
        warn "Retry attempt $RETRY_COUNT of $MAX_RETRIES"
    fi

    info "Running Ansible playbook..."

    if ansible-playbook \
        -i "$INVENTORY" \
        "playbooks/$PLAYBOOK.yml" \
        $VAULT_OPTS \
        -v; then

        DEPLOYMENT_SUCCESS=true

    else
        RETRY_COUNT=$((RETRY_COUNT + 1))

        if [ $RETRY_COUNT -le $MAX_RETRIES ]; then
            warn "Deployment failed, analyzing errors..."

            # Check common issues and try to fix them
            info "Checking for common issues..."

            # Fix permissions
            if [ -d "/etc/matrix-synapse" ]; then
                chown -R matrix-synapse:matrix-synapse /etc/matrix-synapse /var/lib/matrix-synapse 2>/dev/null || true
            fi

            # Restart services if they exist
            for service in postgresql redis-server; do
                if systemctl list-units --type=service | grep -q "$service"; then
                    systemctl restart "$service" 2>/dev/null || true
                fi
            done

            warn "Retrying deployment in 10 seconds..."
            sleep 10
        fi
    fi
done

# Calculate deployment time
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo ""

if [ "$DEPLOYMENT_SUCCESS" = "true" ]; then
    echo "==========================================="
    echo "  DEPLOYMENT COMPLETED SUCCESSFULLY!"
    echo "==========================================="
    echo ""
    success "Deployment time: ${DURATION} seconds"
    success "Type: $DEPLOYMENT_TYPE deployment"

    # Post-deployment verification
    info "Running post-deployment verification..."

    # Check critical services
    SERVICES_OK=true
    for service in matrix-synapse postgresql redis-server caddy; do
        if systemctl is-active --quiet "$service"; then
            success "Service $service: Running"
        else
            error "Service $service: Not running"
            SERVICES_OK=false
        fi
    done

    # Test Matrix API
    if curl -s http://localhost:8008/_matrix/client/versions >/dev/null; then
        success "Matrix API: Responding"
    else
        warn "Matrix API: Not responding (may need time to start)"
    fi

    echo ""
    echo "==========================================="
    echo "  NEXT STEPS"
    echo "==========================================="

    # Get domains from inventory
    MATRIX_DOMAIN=$(grep "matrix_domain:" "$INVENTORY" | head -n1 | cut -d'"' -f2 | cut -d"'" -f2 2>/dev/null || echo "your-domain")
    HOMESERVER_NAME=$(grep "matrix_homeserver_name:" "$INVENTORY" | head -n1 | cut -d'"' -f2 | cut -d"'" -f2 2>/dev/null || echo "matrix.your-domain")

    echo "1. Create admin user:"
    echo "   sudo /usr/local/bin/create-matrix-admin.sh admin your-password"
    echo ""
    echo "2. Test Element web client:"
    echo "   https://$MATRIX_DOMAIN"
    echo ""
    echo "3. Test Matrix federation:"
    echo "   https://federationtester.matrix.org/"
    echo ""
    echo "4. Monitor services:"
    echo "   systemctl status matrix-synapse"
    echo "   journalctl -u matrix-synapse -f"
    echo ""

    if [ "$DEPLOYMENT_TYPE" != "fresh" ]; then
        echo "5. Restore backup if needed:"
        echo "   Backup location: $BACKUP_DIR"
        echo ""
    fi

    if [ ! "$SERVICES_OK" = "true" ]; then
        warn "Some services are not running properly"
        info "Check logs and restart services if needed"
    fi

else
    echo "==========================================="
    echo "  DEPLOYMENT FAILED"
    echo "==========================================="
    error "Deployment failed after $MAX_RETRIES retries"
    echo ""
    info "Common troubleshooting steps:"
    echo "1. Check the error output above"
    echo "2. Verify vault password is correct"
    echo "3. Ensure server has internet connectivity"
    echo "4. Check disk space: df -h"
    echo "5. Check memory: free -h"
    echo "6. Manual deployment: ansible-playbook -i $INVENTORY playbooks/$PLAYBOOK.yml $VAULT_OPTS -vvv"
    echo ""

    if [ "$DEPLOYMENT_TYPE" != "fresh" ] && [ -n "$BACKUP_DIR" ]; then
        info "Restore backup if needed: $BACKUP_DIR"
    fi

    exit 1
fi