#!/bin/bash
# Pre-flight check script for Matrix server deployment
# Checks existing server state and prepares for safe deployment

set -e

echo "==========================================="
echo "  MATRIX DEPLOYMENT PRE-FLIGHT CHECK"
echo "==========================================="
echo ""

ENVIRONMENT="${1:-production}"
INVENTORY="inventory/$ENVIRONMENT/hosts.yml"
VAULT_FILE="inventory/$ENVIRONMENT/group_vars/all/vault.yml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

error() { echo -e "${RED}ERROR: $1${NC}"; }
warn() { echo -e "${YELLOW}WARNING: $1${NC}"; }
success() { echo -e "${GREEN}SUCCESS: $1${NC}"; }
info() { echo "INFO: $1"; }

ISSUES_FOUND=0

# Check if we're in the right directory
if [ ! -f "scripts/deploy.sh" ] && [ ! -f "deploy-matrix.sh" ]; then
    error "Run this from the matrix-server-ansible directory"
    exit 1
fi

info "Environment: $ENVIRONMENT"
echo ""

# Check critical files exist
echo "=== File Structure Check ==="

if [ ! -f "$INVENTORY" ]; then
    error "Inventory file missing: $INVENTORY"
    info "Use: cp $INVENTORY.example $INVENTORY"
    ((ISSUES_FOUND++))
else
    success "Inventory file found: $INVENTORY"
fi

if [ ! -f "$VAULT_FILE" ]; then
    error "Vault file missing: $VAULT_FILE"
    info "Run: ./setup-matrix-secrets.sh"
    ((ISSUES_FOUND++))
else
    success "Vault file found: $VAULT_FILE"
fi

# Check vault password
if [ -f ".vault_pass" ]; then
    success "Vault password file found: .vault_pass"
else
    warn "No .vault_pass file found - will prompt for password"
fi

echo ""

# Check Ansible installation
echo "=== Ansible Check ==="
if command -v ansible-playbook >/dev/null 2>&1; then
    ANSIBLE_VERSION=$(ansible-playbook --version | head -n1 | cut -d' ' -f3)
    success "Ansible found: version $ANSIBLE_VERSION"

    # Check for required collections
    if ansible-galaxy collection list | grep -q "community.general"; then
        success "Required collection found: community.general"
    else
        warn "Missing collection: community.general"
        info "Install with: ansible-galaxy collection install community.general"
        ((ISSUES_FOUND++))
    fi
else
    error "ansible-playbook not found"
    info "Install with: apt install ansible"
    ((ISSUES_FOUND++))
fi

echo ""

# Check existing services
echo "=== Existing Service Check ==="

check_service() {
    local service=$1
    if systemctl list-units --type=service | grep -q "$service"; then
        if systemctl is-active --quiet "$service"; then
            warn "Service $service is already running"
            info "Deployment will reconfigure this service"
        else
            warn "Service $service exists but is not running"
        fi
        return 0
    else
        info "Service $service not found (will be installed)"
        return 1
    fi
}

EXISTING_SERVICES=0

services=("matrix-synapse" "postgresql" "redis-server" "caddy" "nginx")
for service in "${services[@]}"; do
    if check_service "$service"; then
        ((EXISTING_SERVICES++))
    fi
done

if [ $EXISTING_SERVICES -gt 0 ]; then
    warn "Found $EXISTING_SERVICES existing services"
    info "Deployment will safely reconfigure existing services"
fi

echo ""

# Check ports
echo "=== Port Check ==="

check_port() {
    local port=$1
    local service=$2
    if netstat -tuln 2>/dev/null | grep -q ":$port " || ss -tuln 2>/dev/null | grep -q ":$port "; then
        warn "Port $port is already in use (expected for $service)"
        return 0
    else
        info "Port $port is available for $service"
        return 1
    fi
}

ports=("80:HTTP" "443:HTTPS" "8008:Matrix" "5432:PostgreSQL" "6379:Redis" "2222:SSH")
PORTS_IN_USE=0

for port_info in "${ports[@]}"; do
    port=$(echo "$port_info" | cut -d: -f1)
    service=$(echo "$port_info" | cut -d: -f2)
    if check_port "$port" "$service"; then
        ((PORTS_IN_USE++))
    fi
done

echo ""

# Check filesystem
echo "=== Filesystem Check ==="

directories=("/etc/matrix-synapse" "/var/lib/matrix-synapse" "/var/www/element" "/etc/caddy")
for dir in "${directories[@]}"; do
    if [ -d "$dir" ]; then
        warn "Directory exists: $dir (will be updated)"
    else
        info "Directory will be created: $dir"
    fi
done

# Check disk space
DISK_SPACE=$(df / | awk 'NR==2 {print $4}')
DISK_SPACE_GB=$((DISK_SPACE / 1024 / 1024))

if [ $DISK_SPACE_GB -lt 5 ]; then
    error "Insufficient disk space: ${DISK_SPACE_GB}GB available"
    info "Need at least 5GB for Matrix server"
    ((ISSUES_FOUND++))
else
    success "Sufficient disk space: ${DISK_SPACE_GB}GB available"
fi

echo ""

# Check memory
echo "=== System Resources Check ==="

MEMORY_MB=$(free -m | awk 'NR==2{print $2}')
if [ $MEMORY_MB -lt 1024 ]; then
    warn "Low memory: ${MEMORY_MB}MB (recommended: 2GB+)"
    info "Matrix server may run slowly with limited memory"
else
    success "Memory: ${MEMORY_MB}MB"
fi

echo ""

# Network connectivity check
echo "=== Network Check ==="

if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
    success "Internet connectivity: OK"
else
    error "No internet connectivity"
    info "Required for SSL certificates and package installation"
    ((ISSUES_FOUND++))
fi

# DNS check if domains are configured
if [ -f "$INVENTORY" ]; then
    MATRIX_DOMAIN=$(grep "matrix_domain:" "$INVENTORY" | head -n1 | cut -d'"' -f2 | cut -d"'" -f2)
    if [ "$MATRIX_DOMAIN" != "example.com" ] && [ -n "$MATRIX_DOMAIN" ]; then
        info "Checking DNS for: $MATRIX_DOMAIN"
        if nslookup "$MATRIX_DOMAIN" >/dev/null 2>&1; then
            success "DNS resolves: $MATRIX_DOMAIN"
        else
            warn "DNS does not resolve: $MATRIX_DOMAIN"
            info "Configure DNS before deployment for SSL certificates"
        fi
    fi
fi

echo ""

# Security check
echo "=== Security Check ==="

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    warn "Running as root"
    info "This is normal for server deployment"
else
    info "Running as user: $(whoami)"
    info "May need sudo for some operations"
fi

# Check SSH
if systemctl is-active --quiet ssh || systemctl is-active --quiet sshd; then
    success "SSH service is running"
else
    warn "SSH service not found"
    info "Ensure SSH access is available before deployment"
fi

echo ""

# Summary
echo "==========================================="
echo "  PRE-FLIGHT CHECK SUMMARY"
echo "==========================================="

if [ $ISSUES_FOUND -eq 0 ]; then
    success "All checks passed!"
    echo ""
    info "System is ready for Matrix deployment"
    info "Run: ./deploy-matrix.sh $ENVIRONMENT"
else
    error "Found $ISSUES_FOUND issues that need attention"
    echo ""
    info "Fix the issues above before deployment"
    info "Some warnings are normal for existing systems"
fi

if [ $EXISTING_SERVICES -gt 0 ]; then
    echo ""
    warn "IMPORTANT: Existing services detected"
    info "The deployment will:"
    info "  - Safely reconfigure existing services"
    info "  - Preserve data where possible"
    info "  - Update configurations to match security requirements"
    info "  - Create backups before major changes"
fi

echo ""
echo "==========================================="

exit $ISSUES_FOUND