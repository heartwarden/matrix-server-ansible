# 🚀 Matrix Server Deployment Guide

Complete guide for deploying a secure, privacy-focused Matrix server with automated secret management.

## 📋 Prerequisites

### Local Machine (macOS/Linux)
- **Ansible**: `brew install ansible` (macOS) or `sudo apt install ansible` (Linux)
- **Git**: For repository management
- **SSH key**: For server access
- **OpenSSL**: For secret generation (usually pre-installed)

### Target Server (Debian 12)
- **Fresh Debian 12 installation**
- **Root or sudo access**
- **SSH access configured**
- **Domain name** pointing to server IP
- **Ports 80, 443, 8448** accessible from internet

## 🔧 Quick Start (5 Minutes)

### 1. Clone and Setup
```bash
# Clone the repository
git clone https://github.com/heartwarden/matrix-server-ansible.git
cd matrix-server-ansible

# Generate all secrets automatically
./scripts/generate-secrets.sh
```

### 2. Configure Your Domains
```bash
# Edit production inventory
nano inventory/production/group_vars/all.yml

# Update these lines with your actual domains:
matrix_domain: "chat.yourdomain.com"           # Where Element web will be
matrix_homeserver_name: "matrix.yourdomain.com" # Your Matrix homeserver
```

### 3. Configure Server Details
```bash
# Edit hosts file
nano inventory/production/hosts.yml

# Update with your server IP and SSH details
```

### 4. Deploy Everything
```bash
# One-command deployment
./scripts/deploy.sh
```

## 📖 Detailed Deployment Steps

### Step 1: Repository Setup

```bash
# Clone the repository
git clone https://github.com/heartwarden/matrix-server-ansible.git
cd matrix-server-ansible

# Verify scripts are executable
ls -la scripts/
```

### Step 2: Generate Secure Secrets

The deployment uses Ansible Vault to encrypt all sensitive information:

```bash
# Generate all required secrets
./scripts/generate-secrets.sh production

# This will prompt for:
# - Vault password (store this securely!)
# - Admin username (default: admin)
# - Admin password (or auto-generate)
# - SSL/admin email address
```

**What gets generated:**
- PostgreSQL database password (32 chars)
- Matrix application secrets (64 chars each)
- Coturn TURN server secret (32 chars)
- Admin user credentials
- All secrets are cryptographically secure

### Step 3: Configure Your Environment

#### Production Configuration
```bash
# Edit global settings
nano inventory/production/group_vars/all.yml
```

**Required changes:**
```yaml
# Update these with your actual domains
matrix_domain: "chat.yourdomain.com"
matrix_homeserver_name: "matrix.yourdomain.com"
```

#### Server Inventory
```bash
# Edit server details
nano inventory/production/hosts.yml
```

**Example configuration:**
```yaml
matrix_servers:
  hosts:
    matrix.yourdomain.com:
      ansible_host: 1.2.3.4          # Your server IP
      ansible_user: root              # or your sudo user
      ansible_ssh_private_key_file: ~/.ssh/id_rsa  # Your SSH key
```

### Step 4: Pre-Deployment Verification

Test your configuration before deploying:

```bash
# Dry run - test without making changes
./scripts/deploy.sh --dry-run

# Verbose dry run for detailed output
./scripts/deploy.sh --dry-run --verbose

# Test only specific components
./scripts/deploy.sh -p playbooks/matrix.yml --dry-run
```

### Step 5: Full Deployment

```bash
# Complete deployment (recommended for first time)
./scripts/deploy.sh

# Or with secret generation (if you haven't generated them)
./scripts/deploy.sh --generate-secrets

# Auto mode (no prompts, generate secrets if missing)
./scripts/deploy.sh --auto
```

**What gets deployed:**
1. **System Hardening**: SSH security, firewall, fail2ban
2. **PostgreSQL**: Secure database with Matrix user
3. **Redis**: Caching and session storage
4. **Matrix Synapse**: Homeserver with privacy settings
5. **Caddy**: Reverse proxy with automatic HTTPS
6. **Element Web**: Browser-based Matrix client
7. **Coturn**: TURN server for VoIP calls
8. **Monitoring**: System and service monitoring

## 🔐 Post-Deployment Setup

### Step 1: Create Admin User

```bash
# SSH to your server
ssh user@your-server-ip

# Create Matrix admin user
sudo /usr/local/bin/create-matrix-admin.sh admin your_secure_password
```

### Step 2: DNS Configuration

Configure DNS records for your domains:

```dns
# A records
chat.yourdomain.com     A    1.2.3.4
matrix.yourdomain.com   A    1.2.3.4

# SRV record for federation (optional but recommended)
_matrix._tcp.yourdomain.com  SRV  10 0 8448 matrix.yourdomain.com
```

### Step 3: Test Your Installation

#### Web Interface
- Visit: `https://chat.yourdomain.com`
- Login with your admin credentials
- Homeserver: `matrix.yourdomain.com`

#### Federation Test
- Visit: https://federationtester.matrix.org/
- Test your domain: `yourdomain.com`

#### Service Status
```bash
# Check all services
sudo systemctl status matrix-synapse caddy postgresql redis-server

# View Matrix logs
sudo journalctl -u matrix-synapse -f

# Check Caddy logs
sudo tail -f /var/log/caddy/access.log
```

## 🔄 Common Operations

### Update Matrix Server
```bash
# Update only Matrix components
./scripts/deploy.sh -p playbooks/matrix.yml

# Update with new secrets
./scripts/deploy.sh -p playbooks/matrix.yml --generate-secrets
```

### System Maintenance
```bash
# Run maintenance tasks
./scripts/deploy.sh -p playbooks/maintenance.yml

# Security hardening only
./scripts/deploy.sh -p playbooks/hardening.yml
```

### Environment Management
```bash
# Deploy to staging
./scripts/deploy.sh -e staging

# Generate staging secrets
./scripts/generate-secrets.sh staging
```

### Vault Management
```bash
# View secrets (encrypted)
./scripts/setup-vault.sh view

# Edit secrets
./scripts/setup-vault.sh edit

# Backup vault
./scripts/setup-vault.sh backup

# Change vault password
./scripts/setup-vault.sh rekey
```

## 🛡️ Security Features

### Privacy Protection
- ✅ **No email/CAPTCHA required** for registration
- ✅ **No IP address logging** in Matrix logs
- ✅ **5-minute message redaction window**
- ✅ **Admin cannot access encrypted messages**
- ✅ **Presence indicators enabled**
- ✅ **90-day automatic media cleanup**

### System Security
- ✅ **SSH hardening** (key-only auth, custom port)
- ✅ **Firewall configuration** (UFW with strict rules)
- ✅ **Fail2ban protection** against brute force
- ✅ **Automatic security updates**
- ✅ **PostgreSQL encryption** (scram-sha-256)
- ✅ **SSL/TLS everywhere** (automatic Let's Encrypt)

### Secret Management
- ✅ **Ansible Vault encryption** for all secrets
- ✅ **Cryptographically secure generation**
- ✅ **Git security** (.gitignore protection)
- ✅ **Backup system** with rotation
- ✅ **No default passwords**

## 🚨 Troubleshooting

### Deployment Failures

#### SSH Connection Issues
```bash
# Test SSH connectivity
ssh -p 2222 user@your-server

# Check SSH key
ssh-add -l

# Verify inventory configuration
cat inventory/production/hosts.yml
```

#### Vault Password Issues
```bash
# Check vault password file
ls -la .vault_pass

# Test vault access
ansible-vault view inventory/production/group_vars/all/vault.yml

# Reset vault password
./scripts/setup-vault.sh rekey
```

#### Service Failures
```bash
# Check service status
sudo systemctl status matrix-synapse

# View detailed logs
sudo journalctl -u matrix-synapse -n 50

# Test configuration
sudo -u matrix-synapse /opt/synapse/venv/bin/python -m synapse.app.homeserver --config-path /etc/matrix-synapse/homeserver.yaml
```

### Common Issues

#### "Domain not found" errors
- Check DNS configuration
- Verify domain points to correct IP
- Ensure ports 80, 443, 8448 are open

#### SSL certificate failures
- Check domain DNS propagation
- Verify email address in vault
- Review Caddy logs: `sudo journalctl -u caddy`

#### Database connection errors
- Check PostgreSQL status: `sudo systemctl status postgresql`
- Test database connection: `sudo -u postgres psql -d synapse -c "SELECT 1;"`
- Review vault database password

#### Matrix registration issues
- Check homeserver.yaml configuration
- Verify registration is enabled if needed
- Test with admin user first

## 📊 Monitoring and Maintenance

### Regular Monitoring
```bash
# System status dashboard
./scripts/matrix-status.sh

# View Matrix metrics (if enabled)
curl http://localhost:9092/metrics

# Check disk usage
df -h

# Monitor logs
sudo tail -f /var/log/matrix-synapse/homeserver.log
```

### Automated Maintenance
The deployment includes automated:
- **Security updates** (daily)
- **Log rotation** (weekly)
- **Media cleanup** (weekly, 90-day retention)
- **Database maintenance** (monthly)
- **SSL certificate renewal** (automatic)

### Manual Maintenance
```bash
# Run full maintenance
./scripts/deploy.sh -p playbooks/maintenance.yml

# Update system packages
sudo apt update && sudo apt upgrade

# Clean old logs
sudo journalctl --vacuum-time=30d

# Restart services if needed
sudo systemctl restart matrix-synapse
```

## 🔄 Backup and Recovery

### Backup Strategy
```bash
# Backup vault files
./scripts/setup-vault.sh backup

# Backup Matrix data
sudo tar -czf matrix-backup-$(date +%Y%m%d).tar.gz \
  /var/lib/matrix-synapse \
  /etc/matrix-synapse \
  /var/lib/postgresql

# Backup to remote location (recommended)
scp matrix-backup-*.tar.gz backup-server:/backups/
```

### Recovery Process
```bash
# Restore from backup
sudo systemctl stop matrix-synapse
sudo tar -xzf matrix-backup-YYYYMMDD.tar.gz -C /
sudo systemctl start matrix-synapse

# Verify restoration
sudo systemctl status matrix-synapse
```

## 🌟 Advanced Configuration

### Custom Domain Setup
For advanced users wanting custom federation domains:

```yaml
# In inventory/production/group_vars/all.yml
matrix_domain: "yourdomain.com"              # Your main domain
matrix_homeserver_name: "matrix.yourdomain.com"  # Matrix server
```

### Performance Tuning
For high-traffic servers:

```yaml
# In inventory/production/group_vars/matrix_servers.yml
postgresql_max_connections: 200
postgresql_shared_buffers: "512MB"
matrix_workers_enabled: true
```

### Multi-Environment Setup
```bash
# Production
./scripts/generate-secrets.sh production
./scripts/deploy.sh -e production

# Staging
./scripts/generate-secrets.sh staging
./scripts/deploy.sh -e staging

# Development
./scripts/generate-secrets.sh development
./scripts/deploy.sh -e development
```

## 📞 Support and Community

- **Documentation**: Check this guide and scripts/README.md
- **Issues**: Report problems via GitHub issues
- **Matrix Community**: Join #matrix:matrix.org for general Matrix support
- **Security**: For security issues, contact maintainers privately

## 🔒 Security Recommendations

1. **Vault Password**: Use a strong, unique password and store it securely
2. **Regular Updates**: Run maintenance playbook monthly
3. **Secret Rotation**: Change vault secrets every 6-12 months
4. **Monitoring**: Set up external monitoring for critical services
5. **Backups**: Implement automated offsite backups
6. **Access Control**: Limit who has deployment access
7. **Network Security**: Use VPN for administrative access when possible

Your Matrix server is now ready to provide secure, private communication! 🎉