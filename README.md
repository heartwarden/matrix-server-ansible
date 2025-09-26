# Secure Matrix Server Ansible

Comprehensive Ansible automation for deploying secure Matrix (Synapse) servers on Debian 12 with enterprise-grade security hardening.

## 🚀 Quick Start

### Prerequisites
- **Server**: Debian 12 with root access and public IP
- **Local Machine**: macOS/Linux with Python 3.8+
- **Domain**: DNS configured for your Matrix domains
- **Dependencies**: `git`, `python3`, `pip3`, `whiptail`

### 1. Clone and Setup

```bash
# Clone the repository
git clone https://github.com/yourusername/matrix-server-ansible.git
cd matrix-server-ansible

# Run the setup script
./scripts/setup.sh
```

### 2. Configure Your Server

```bash
# Interactive TUI configuration
./scripts/configure-server.sh
```

The TUI will guide you through:
- Server identification and domain configuration
- Security settings (SSH port, timezone)
- SSL email for Let's Encrypt
- SSH key generation/selection
- Password generation

### 3. Deploy

```bash
# Navigate to your server configuration
cd server-configs

# Run the generated deployment script
./your-server-name-deploy.sh
```

## 🔧 Features

### 🔒 Security Hardening
- **User Management**: Creates `zerokaine` user, disables root login
- **SSH Hardening**: Key-only auth, custom port, rate limiting
- **Firewall**: UFW with strict rules and fail2ban integration
- **System Hardening**: Kernel parameters, file permissions, audit logging
- **Automatic Updates**: Unattended security updates

### 🏠 Matrix Server
- **Synapse Homeserver**: Latest stable version with PostgreSQL
- **Element Web Client**: Modern Matrix web interface
- **Caddy Web Server**: Automatic HTTPS with Let's Encrypt
- **Coturn TURN Server**: For VoIP and video calls
- **Federation**: Full Matrix federation support

### 📊 Monitoring & Maintenance
- **System Monitoring**: CPU, memory, disk, network metrics
- **Service Health Checks**: Automated service monitoring
- **Log Management**: Centralized logging with rotation
- **Backup System**: Automated backups with retention
- **Security Monitoring**: Intrusion detection and alerting

### 🌐 Caddy Integration
- **Automatic HTTPS**: Let's Encrypt integration
- **Security Headers**: HSTS, CSP, and security headers
- **Rate Limiting**: Request rate limiting and DDoS protection
- **Health Checks**: Built-in health monitoring endpoints

## 📁 Directory Structure

```
server-ansible/
├── scripts/
│   ├── setup.sh              # Environment setup
│   ├── configure-server.sh   # TUI configuration wizard
│   └── deploy.sh             # Deployment script
├── server-configs/           # Generated server configurations
├── playbooks/               # Ansible playbooks
│   ├── site.yml            # Complete deployment
│   ├── hardening.yml       # Security hardening only
│   ├── matrix.yml          # Matrix server only
│   └── maintenance.yml     # System maintenance
├── roles/                   # Ansible roles
│   ├── user_management/    # zerokaine user setup
│   ├── debian_hardening/   # System security
│   ├── firewall/           # UFW configuration
│   ├── caddy/              # Caddy web server
│   ├── ssl_certificates/   # Let's Encrypt SSL
│   ├── monitoring/         # System monitoring
│   └── matrix_server/      # Matrix/Synapse
├── inventory/              # Example inventories
└── group_vars/             # Ansible variables
```

## 🔑 User Management

The system creates a `zerokaine` user with:
- **sudo access** with or without password
- **SSH key authentication** only
- **Custom scripts** for Matrix management
- **Bash customization** with aliases and functions

### Management Scripts
After deployment, the `zerokaine` user has access to:
```bash
matrix-status    # Check Matrix server status
matrix-logs      # View Matrix server logs
matrix-restart   # Restart Matrix services
matrix-backup    # Create system backup
system-info      # Display system information
```

## 🌍 DNS Configuration

Before deployment, configure these DNS records:

```
example.com.        A     YOUR_SERVER_IP
matrix.example.com. A     YOUR_SERVER_IP
```

For subdomains (optional):
```
chat.example.com.   A     YOUR_SERVER_IP  # If using chat subdomain
```

## 🔐 Security Features

### SSH Security
- Custom SSH port (default: 2222)
- Key-only authentication
- Rate limiting and fail2ban protection
- Root login disabled

### System Security
- Kernel hardening parameters
- File system permissions locked down
- Automatic security updates
- Audit logging enabled
- File integrity monitoring (AIDE)

### Network Security
- UFW firewall with minimal open ports
- Rate limiting on all services
- DDoS protection with Caddy
- Intrusion detection with fail2ban

### Application Security
- Matrix rate limiting
- Admin API access restrictions
- Secure SSL/TLS configuration
- Security headers on all endpoints

## 📊 Monitoring

### System Metrics
- Node Exporter for Prometheus metrics
- System resource monitoring
- Service health checks
- Log aggregation and rotation

### Alerting
- Email notifications for critical events
- Service failure detection
- Security incident alerting
- Disk space and resource warnings

## 🔄 Maintenance

### Regular Updates
```bash
# Run system maintenance
ansible-playbook playbooks/maintenance.yml -i server-configs/your-server-inventory.yml
```

### Backup Operations
```bash
# Create backup
ssh -p 2222 zerokaine@your-server
matrix-backup
```

### Service Management
```bash
# Check Matrix status
matrix-status

# View logs
matrix-logs

# Restart services if needed
matrix-restart
```

## 🎯 Deployment Options

### Full Deployment
```bash
./scripts/configure-server.sh  # Configure
./server-configs/server-deploy.sh  # Deploy everything
```

### Hardening Only
```bash
ansible-playbook playbooks/hardening.yml -i inventory/production/hosts.yml
```

### Matrix Only
```bash
ansible-playbook playbooks/matrix.yml -i inventory/production/hosts.yml
```

## 🔗 Post-Deployment

### 1. Create Admin User
```bash
ssh -p 2222 zerokaine@your-server
sudo /usr/local/bin/create-matrix-admin.sh admin secure_password
```

### 2. Test Your Server
- **Element Web**: https://your-domain.com
- **Federation Test**: https://federationtester.matrix.org/
- **Health Check**: https://your-domain.com/health

### 3. Client Configuration
- **Homeserver**: `https://matrix.your-domain.com`
- **Username**: Your admin username
- **Password**: Your admin password

## 🚨 Troubleshooting

### Common Issues

**SSH Connection Failed**
```bash
# Check if SSH service is running on the new port
nmap -p 2222 your-server-ip

# Connect with verbose output
ssh -vvv -p 2222 zerokaine@your-server-ip
```

**Matrix Federation Issues**
```bash
# Test federation endpoint
curl https://matrix.your-domain.com/_matrix/federation/v1/version

# Check DNS resolution
nslookup matrix.your-domain.com
```

**SSL Certificate Problems**
```bash
# Check Caddy logs
ssh -p 2222 zerokaine@your-server
sudo journalctl -u caddy -f
```

### Log Locations
- **Caddy**: `/var/log/caddy/`
- **Matrix**: `/var/log/matrix-synapse/`
- **System**: `/var/log/syslog`
- **Security**: `/var/log/auth.log`

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Test your changes
4. Submit a pull request

## 📄 License

MIT License - see [LICENSE](LICENSE) file for details.

## ⚠️ Security Notice

This setup creates a hardened server environment. Keep these important notes in mind:

- **SSH runs on port 2222** after deployment
- **Root login is disabled** - use `zerokaine` user
- **Only SSH key authentication** is allowed
- **Firewall is strict** - only necessary ports are open
- **All passwords are randomly generated** and stored in encrypted vaults

## 📞 Support

For issues and questions:
- Check the troubleshooting section above
- Review log files for error messages
- Test individual components
- Create an issue on GitHub

---

Made with ❤️ for secure Matrix deployments