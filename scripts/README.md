# Matrix Server Deployment Scripts

This directory contains automated scripts for deploying and managing a secure Matrix server with comprehensive privacy features.

## 🚀 Quick Start

### 1. Generate Secrets (First Time)
```bash
# Generate all required secrets securely
./scripts/generate-secrets.sh

# Or for staging environment
./scripts/generate-secrets.sh staging
```

### 2. Deploy Matrix Server
```bash
# Full deployment with secret generation
./scripts/deploy.sh --generate-secrets

# Or just deploy (if secrets exist)
./scripts/deploy.sh
```

## 📁 Available Scripts

### Core Deployment Scripts

#### `generate-secrets.sh` - 🔐 Secure Secret Generation
Generates all required secrets and creates encrypted Ansible Vault files.

**Usage:**
```bash
./scripts/generate-secrets.sh [environment]
```

**Features:**
- Generates cryptographically secure secrets using OpenSSL
- Creates encrypted Ansible Vault files
- Prompts for admin user and SSL email
- Updates .gitignore for security
- Provides clear security instructions

**Generated Secrets:**
- PostgreSQL database password
- Matrix application secrets (form, macaroon, registration)
- Coturn TURN server secret
- Admin user credentials
- SSL/TLS configuration

#### `deploy.sh` - 🚀 Enhanced Deployment Manager
Comprehensive deployment script with secret management integration.

**Usage:**
```bash
./scripts/deploy.sh [OPTIONS]
```

**Options:**
- `-e, --environment ENV` - Target environment (production|staging)
- `-p, --playbook BOOK` - Playbook to run (site|hardening|matrix|maintenance)
- `-g, --generate-secrets` - Generate new secrets before deployment
- `-a, --auto` - Auto mode (generate secrets if missing, no prompts)
- `-d, --dry-run` - Perform a dry run (check mode)
- `-s, --skip-checks` - Skip pre-flight checks
- `--verbose` - Enable verbose output

**Examples:**
```bash
./scripts/deploy.sh                           # Full deployment
./scripts/deploy.sh -g                        # Generate secrets and deploy
./scripts/deploy.sh -e staging -p matrix      # Deploy Matrix to staging
./scripts/deploy.sh -d --verbose              # Dry run with verbose output
./scripts/deploy.sh -a                        # Auto mode (no prompts)
```

#### `setup-vault.sh` - 🔐 Vault Management
Comprehensive Ansible Vault management and operations.

**Usage:**
```bash
./scripts/setup-vault.sh [OPTIONS] [ACTION]
```

**Actions:**
- `setup` - Setup vault for environment (default)
- `view` - View vault contents
- `edit` - Edit vault contents
- `rekey` - Change vault password
- `validate` - Validate vault file
- `backup` - Backup vault file

**Examples:**
```bash
./scripts/setup-vault.sh                      # Setup production vault
./scripts/setup-vault.sh -e staging setup     # Setup staging vault
./scripts/setup-vault.sh view                 # View production vault
./scripts/setup-vault.sh edit                 # Edit production vault
./scripts/setup-vault.sh backup               # Backup production vault
```

### Legacy Scripts

These scripts provide additional functionality and are maintained for compatibility:

- `setup.sh` - Initial environment setup
- `configure-server.sh` - Server configuration wizard
- `github-deploy.sh` - GitHub integration
- `verify-ssh-access.sh` - SSH connectivity testing
- `test-vault.sh` - Vault testing utilities

## 🔐 Security Features

### Automatic Secret Generation
- **Cryptographically Secure**: Uses OpenSSL for random generation
- **Proper Length**: 32+ character secrets for maximum security
- **No Defaults**: Validates that no default/template values remain
- **Unique Secrets**: Each deployment gets unique secrets

### Ansible Vault Integration
- **Encrypted Storage**: All secrets stored in encrypted vault files
- **Multiple Environments**: Separate vaults for production/staging
- **Password Management**: Flexible vault password file support
- **Backup System**: Automatic vault backups with rotation

### Git Security
- **Comprehensive .gitignore**: Prevents accidental secret commits
- **Multiple Patterns**: Covers all possible secret file patterns
- **Backup Protection**: Excludes vault backups from git
- **Clear Warnings**: Scripts warn about security best practices

## 📋 Deployment Workflows

### Initial Setup (First Time)
```bash
# 1. Generate secrets
./scripts/generate-secrets.sh

# 2. Configure inventory (edit your domains/IPs)
cp inventory/production/hosts.yml.example inventory/production/hosts.yml
nano inventory/production/hosts.yml

# 3. Deploy everything
./scripts/deploy.sh
```

### Regular Updates
```bash
# Update Matrix components only
./scripts/deploy.sh -p playbooks/matrix.yml

# Test changes first
./scripts/deploy.sh -d

# Update with verbose logging
./scripts/deploy.sh --verbose
```

### Environment-Specific Deployments
```bash
# Deploy to staging
./scripts/deploy.sh -e staging

# Generate staging secrets
./scripts/generate-secrets.sh staging

# Deploy Matrix to staging
./scripts/deploy.sh -e staging -p playbooks/matrix.yml
```

### Maintenance Operations
```bash
# Run system maintenance
./scripts/deploy.sh -p playbooks/maintenance.yml

# Security hardening only
./scripts/deploy.sh -p playbooks/hardening.yml

# SSL certificate renewal
./scripts/deploy.sh -t ssl
```

## 🔧 Vault Management

### Password Files
The scripts automatically look for vault passwords in this order:
1. `.vault_pass` (main password file)
2. `.vault_pass_ENVIRONMENT` (environment-specific)
3. `.ansible_vault_password` (standard location)
4. `~/.ansible_vault_password` (user home)

### Vault Security Best Practices
- **Strong Passwords**: Use 12+ character vault passwords
- **Secure Storage**: Store vault passwords in a password manager
- **Regular Rotation**: Change vault passwords periodically
- **Backup Strategy**: Keep secure backups of vault files
- **Access Control**: Limit who has vault password access

### Manual Vault Operations
```bash
# View vault contents
ansible-vault view inventory/production/group_vars/all/vault.yml

# Edit vault
ansible-vault edit inventory/production/group_vars/all/vault.yml

# Change vault password
ansible-vault rekey inventory/production/group_vars/all/vault.yml

# Decrypt vault (for backup)
ansible-vault decrypt inventory/production/group_vars/all/vault.yml
```

## 🛡️ Privacy & Security Features

### Matrix Privacy Configuration
- **No Email/CAPTCHA Required**: Registration without email verification
- **No IP Logging**: Custom log configuration prevents IP address logging
- **5-Minute Redaction Window**: Users can redact messages within 5 minutes
- **Admin Privacy**: Admins cannot access encrypted messages or media
- **Presence Indicators**: Online/offline status enabled as requested

### Database Security
- **Secure Authentication**: PostgreSQL with scram-sha-256 encryption
- **Minimal Privileges**: Database user has only necessary permissions
- **SSL/TLS Encryption**: Encrypted database connections
- **Comprehensive Logging**: Security events logged without sensitive data

### Media Management
- **90-Day Cleanup**: Automatic removal of unused media files
- **Weekly Scheduling**: Cleanup runs every Sunday at 3 AM
- **Database Optimization**: Vacuum after cleanup to reclaim space
- **Orphan File Removal**: Cleans up temporary and orphaned files

## 🔍 Troubleshooting

### Secret Generation Issues
```bash
# Check if secrets were generated
ls -la inventory/production/group_vars/all/vault.yml

# Validate vault file
./scripts/setup-vault.sh validate

# View vault contents
./scripts/setup-vault.sh view
```

### Deployment Problems
```bash
# Dry run to test configuration
./scripts/deploy.sh -d

# Verbose output for debugging
./scripts/deploy.sh --verbose

# Skip connectivity checks
./scripts/deploy.sh -s

# Check individual components
./scripts/deploy.sh -p playbooks/matrix.yml -d
```

### Vault Access Issues
```bash
# Check vault password file
ls -la .vault_pass

# Test vault access
ansible-vault view inventory/production/group_vars/all/vault.yml

# Reset vault password
./scripts/setup-vault.sh rekey
```

## 📞 Support

For issues or questions:
1. Check the troubleshooting section above
2. Review the main project README
3. Check deployment logs in the project root
4. Validate your inventory configuration
5. Ensure all required dependencies are installed

## 🔒 Security Notice

⚠️ **IMPORTANT SECURITY REMINDERS:**
- Never commit `.vault_pass` or unencrypted secrets to git
- Store vault passwords in a secure password manager
- Rotate secrets periodically for enhanced security
- Keep backup copies of vault files in secure locations
- Review and audit vault contents regularly
- Use strong, unique passwords for all components