# 🚀 Matrix Server - TUI Configuration & One-Shot Deployment

**Configure everything through an interactive TUI, then deploy with a single command.**

## Quick Start (Choose Your Style)

### Option 1: Quick Configuration (Recommended)
```bash
./one-shot-deploy.sh --quick
```
Simple prompts, no complex TUI - just enter your domains and deploy!

### Option 2: Full TUI Configuration
```bash
./one-shot-deploy.sh
```
Complete interactive TUI with validation and advanced options.

### Option 3: Quick Configure Only
```bash
./quick-configure.sh
```
Just the configuration prompts with immediate deployment.

## What It Does

1. **TUI Configuration** - Interactive setup for all settings
2. **Automatic Secret Generation** - All passwords and keys generated securely
3. **One-Shot Deployment** - Complete deployment in a single run
4. **Smart Error Handling** - Detects and recovers from issues
5. **Existing Server Compatibility** - Works with partial/existing configs

## 🎛️ TUI Features

### Interactive Configuration
- **Deployment Type**: Fresh/Update/Recovery
- **Environment**: Production/Staging
- **Domains**: Matrix domain + homeserver domain
- **Server**: Local or remote deployment
- **Admin Account**: Username + auto-generated password
- **Security**: All privacy settings pre-configured

### Auto-Generated
- Database passwords
- Matrix secrets (form, macaroon, registration, TURN)
- Vault encryption
- SSL configuration
- Privacy settings (no IP logging, 5min redaction, etc.)

## 📋 Commands

| Command | Purpose |
|---------|---------|
| `./one-shot-deploy.sh --quick` | **Quick prompts + deployment (RECOMMENDED)** |
| `./quick-configure.sh` | Simple configuration prompts only |
| `./one-shot-deploy.sh` | Full TUI configuration + deployment |
| `./configure-matrix.sh` | Advanced TUI configuration only |
| `./smart-deploy.sh` | Smart deployment (advanced) |
| `./deploy-matrix.sh` | Simple deployment |
| `./pre-flight-check.sh` | System readiness check |

## 🛡️ Security & Privacy (Pre-Configured)

✅ **No IP logging** - Synapse configured to not log IPs
✅ **No email/CAPTCHA** - Registration without requirements
✅ **Presence enabled** - User status indicators
✅ **5-minute redaction** - Message deletion window
✅ **90-day media cleanup** - Automatic file removal
✅ **Admin privacy** - Cannot access encrypted messages
✅ **SSH hardening** - Custom port, fail2ban, firewall
✅ **Auto SSL** - Let's Encrypt with auto-renewal

## 🔧 Deployment Types

### Fresh Installation
- Clean Debian 12 server setup
- Complete Matrix server installation
- User creation and SSH hardening

### Update Deployment
- Updates existing Matrix server
- Preserves data and configurations
- Applies security updates

### Recovery Deployment
- Fixes broken installations
- Restores from backups
- Repairs configuration issues

## 📁 What Gets Created

```
inventory/production/
├── hosts.yml                    # Server connection details
└── group_vars/
    └── all/
        ├── all.yml              # Configuration variables
        └── vault.yml            # Encrypted secrets

.vault_pass                      # Vault password (keep secure)
```

## 🌐 After Deployment

1. **Configure DNS:**
   ```
   chat.yourdomain.com → YOUR_SERVER_IP
   matrix.yourdomain.com → YOUR_SERVER_IP
   ```

2. **Test Element:** `https://chat.yourdomain.com`

3. **Create Users:**
   ```bash
   sudo /usr/local/bin/create-matrix-admin.sh username password
   ```

4. **Monitor Services:**
   ```bash
   systemctl status matrix-synapse caddy postgresql redis-server
   journalctl -u matrix-synapse -f
   ```

## 🔍 Troubleshooting

**Configuration issues:**
```bash
./configure-matrix.sh  # Re-run TUI
```

**Deployment failures:**
```bash
./pre-flight-check.sh  # Check system
./smart-deploy.sh production site-fixed  # Retry with smart recovery
```

**Service problems:**
```bash
systemctl restart matrix-synapse caddy
journalctl -u matrix-synapse -n 50
```

## 🎯 Perfect For

- **Fresh servers** - Complete setup from scratch
- **Existing servers** - Safe updates and reconfigurations
- **Quick deployments** - Everything configured through TUI
- **Privacy-focused** - All privacy settings optimized
- **Security-hardened** - Production-ready security

---

**One command. Full configuration. Complete deployment.** 🚀