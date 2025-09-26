# Matrix Server Quick Start Guide

Complete Matrix server deployment in under 10 minutes with automatic security hardening.

## 🚀 Overview

This setup provides:
- **Secure Matrix homeserver** with Caddy, PostgreSQL, Redis
- **Element web client** with automatic HTTPS
- **zerokaine user** with SSH key access and disabled root login
- **Comprehensive security hardening** (firewall, fail2ban, system hardening)
- **TUI configuration** for easy server setup
- **GitHub workflow** for version control and deployment

## ⚡ Quick Deployment

### 1. Initial Setup (On Your Mac)

```bash
# Clone and setup (first time only)
git clone https://github.com/your-username/matrix-server-ansible.git
cd matrix-server-ansible
./scripts/setup.sh

# Activate environment
source activate
```

### 2. Configure New Server

```bash
# Interactive TUI configuration
./scripts/configure-server.sh
```

The TUI will ask for:
- **Server name**: Identifier for this server (e.g., "matrix-prod-01")
- **Matrix domain**: Your main domain (e.g., "yourdomain.com")
- **Homeserver domain**: Matrix server domain (e.g., "matrix.yourdomain.com")
- **Server IP**: Public IP address of your server
- **SSL email**: Email for Let's Encrypt certificates
- **SSH settings**: Port and key configuration

### 3. Deploy

```bash
# Navigate to generated config
cd server-configs

# Deploy everything
./your-server-name-deploy.sh
```

### 4. Complete Setup

```bash
# SSH to your new server (after deployment)
ssh -p 2222 zerokaine@your-server-ip

# Create Matrix admin user
sudo /usr/local/bin/create-matrix-admin.sh admin secure_password123
```

## 🌐 DNS Configuration

Before deployment, configure these DNS records:

```dns
yourdomain.com.        A    YOUR_SERVER_IP
matrix.yourdomain.com. A    YOUR_SERVER_IP
```

## 📋 After Deployment

### Access Your Matrix Server
- **Element Web**: https://yourdomain.com
- **Admin**: Use the admin credentials you created
- **Federation Test**: https://federationtester.matrix.org/

### Server Management
```bash
# Check Matrix status
matrix-status

# View logs
matrix-logs

# Restart services
matrix-restart

# System information
system-info

# Create backup
matrix-backup
```

## 🔧 Management Commands

### From Your Mac

```bash
# Check all configured servers
./scripts/check-servers.sh

# Quick deploy existing configuration
./scripts/quick-deploy.sh

# View server configurations
ls server-configs/
```

### On The Server

```bash
# Matrix management (as zerokaine user)
matrix-status     # Service status
matrix-logs       # View logs
matrix-restart    # Restart services
matrix-backup     # Create backup
system-info       # System overview

# System management (with sudo)
sudo systemctl status matrix-synapse
sudo journalctl -u caddy -f
sudo ufw status verbose
```

## 🔒 Security Features

### Automatic Security Hardening
- ✅ **SSH**: Port 2222, key-only auth, rate limiting
- ✅ **Firewall**: UFW with minimal open ports
- ✅ **User Management**: zerokaine user, root disabled
- ✅ **System**: Kernel hardening, file permissions
- ✅ **Monitoring**: System metrics and health checks
- ✅ **Updates**: Automatic security updates

### What Gets Secured
- SSH configuration hardened
- Firewall configured with strict rules
- System kernel parameters hardened
- File permissions secured
- Automatic security updates enabled
- Fail2ban intrusion detection
- System monitoring and alerting

## 🚨 Important Notes

⚠️ **After deployment:**
- SSH runs on **port 2222** (not 22)
- Only **SSH key authentication** allowed
- **Root login disabled** - use `zerokaine` user
- **Passwords generated automatically** and stored securely

⚠️ **Required for deployment:**
- Debian 12 server with root access
- Domain names with DNS configured
- SSH access to server

## 🔄 GitHub Workflow

### Initial Repository Setup
```bash
# Create new GitHub repository
gh repo create matrix-server-ansible --public
git remote add origin https://github.com/your-username/matrix-server-ansible.git
git add .
git commit -m "Initial Matrix server Ansible setup"
git push -u origin main
```

### Deploy From Any Machine
```bash
# Clone repository
git clone https://github.com/your-username/matrix-server-ansible.git
cd matrix-server-ansible

# Setup environment
./scripts/setup.sh
source activate

# Configure and deploy
./scripts/configure-server.sh
cd server-configs
./server-name-deploy.sh
```

## 🆘 Troubleshooting

### Common Issues

**Can't connect via SSH after deployment**
```bash
# SSH now runs on port 2222
ssh -p 2222 zerokaine@your-server-ip
```

**Matrix not accessible**
```bash
# Check services on server
ssh -p 2222 zerokaine@your-server-ip
matrix-status
sudo systemctl status matrix-synapse caddy
```

**DNS/SSL issues**
```bash
# Test DNS resolution
nslookup yourdomain.com
nslookup matrix.yourdomain.com

# Check SSL certificates
curl -I https://yourdomain.com
```

**Federation not working**
- Verify DNS records point to your server
- Test federation: https://federationtester.matrix.org/
- Check firewall allows port 8448: `sudo ufw status`

### Log Locations
```bash
# Matrix logs
sudo journalctl -u matrix-synapse -f

# Caddy logs
sudo journalctl -u caddy -f

# System logs
sudo tail -f /var/log/syslog

# Security logs
sudo tail -f /var/log/auth.log
```

## 📞 Support

- **Matrix federation test**: https://federationtester.matrix.org/
- **Element documentation**: https://element.io/help
- **Matrix specification**: https://matrix.org/docs/

---

🎉 **You now have a secure, production-ready Matrix server!**

- Element Web: https://yourdomain.com
- Admin access with your created credentials
- Full Matrix federation support
- Enterprise-grade security hardening
- Automated monitoring and maintenance