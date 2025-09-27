#!/bin/bash
# Matrix Deployment Without Vault Encryption
# Simple deployment that stores secrets in plain text (for testing/development)

set -e

echo "🚀 Matrix Server Quick Deploy (No Vault)"
echo "========================================"
echo ""
echo "⚠️  WARNING: This stores secrets in plain text!"
echo "    Only use for testing or if vault issues persist."
echo ""

# Check if we're root
if [ "$EUID" -ne 0 ]; then
    echo "❌ Please run as root: sudo $0"
    exit 1
fi

# Get current directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Simple prompts
read -p "Matrix domain (where Element web will be hosted): " MATRIX_DOMAIN
read -p "Homeserver domain (Matrix federation domain): " HOMESERVER_DOMAIN
read -p "SSL certificate email: " SSL_EMAIL
read -p "Admin username [zerokaine]: " ADMIN_USERNAME
ADMIN_USERNAME=${ADMIN_USERNAME:-zerokaine}

echo -n "Admin password (leave empty for auto-generation): "
read -s ADMIN_PASSWORD
echo ""

if [ -z "$ADMIN_PASSWORD" ]; then
    ADMIN_PASSWORD=$(openssl rand -base64 12)
    echo "Auto-generated password: $ADMIN_PASSWORD"
fi

read -p "Enable user registration? (y/N): " ENABLE_REG
if [[ "$ENABLE_REG" =~ ^[Yy]$ ]]; then
    ENABLE_REGISTRATION="true"
else
    ENABLE_REGISTRATION="false"
fi

echo ""
echo "Configuration:"
echo "=============="
echo "Matrix Domain: $MATRIX_DOMAIN"
echo "Homeserver: $HOMESERVER_DOMAIN"
echo "SSL Email: $SSL_EMAIL"
echo "Admin User: $ADMIN_USERNAME"
echo "Registration: $ENABLE_REGISTRATION"
echo ""

read -p "Proceed with deployment? (y/N): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Deployment cancelled."
    exit 0
fi

echo ""
echo "🔧 Creating configuration..."

# Generate secrets
echo "🔐 Generating secrets..."
DB_PASSWORD=$(openssl rand -hex 16)
FORM_SECRET=$(openssl rand -hex 32)
MACAROON_SECRET=$(openssl rand -hex 32)
REGISTRATION_SECRET=$(openssl rand -hex 16)
COTURN_SECRET=$(openssl rand -hex 16)

# Create directories
mkdir -p inventory/production/group_vars/all

# Create hosts.yml
cat > inventory/production/hosts.yml << EOF
---
all:
  children:
    matrix_servers:
      hosts:
        localhost:
          ansible_connection: local
          ansible_python_interpreter: /usr/bin/python3
          matrix_domain: "$MATRIX_DOMAIN"
          matrix_homeserver_name: "$HOMESERVER_DOMAIN"
      vars:
        ansible_become: yes
        ansible_become_method: sudo
        gather_facts: yes
        host_key_checking: false
EOF

# Create all.yml with embedded secrets (no vault)
cat > inventory/production/group_vars/all.yml << EOF
---
matrix_domain: "$MATRIX_DOMAIN"
matrix_homeserver_name: "$HOMESERVER_DOMAIN"
ssl_email: "$SSL_EMAIL"

# Security settings
ssh_port: 2222
fail2ban_enabled: true
ufw_enabled: true

# Matrix settings
matrix_registration_enabled: $ENABLE_REGISTRATION

# Admin user
admin_username: "$ADMIN_USERNAME"
admin_user_password: "$ADMIN_PASSWORD"
create_user: "zerokaine"

# Database and secrets (plain text - no vault)
matrix_database_password: "$DB_PASSWORD"
form_secret: "$FORM_SECRET"
macaroon_secret_key: "$MACAROON_SECRET"
registration_secret: "$REGISTRATION_SECRET"
coturn_secret: "$COTURN_SECRET"

# Privacy settings
matrix_presence_enabled: true
matrix_redaction_retention_period: 300
matrix_media_retention_days: 90
matrix_log_filter_ips: true
matrix_registration_requires_email: false
matrix_registration_requires_captcha: false

# System hardening
disable_ipv6: false
kernel_hardening_enabled: true
sysctl_hardening_enabled: true
unattended_upgrades_enabled: true
auto_reboot_if_required: true
auto_reboot_time: "03:00"
monitoring_enabled: true
log_retention_days: 30
EOF

echo "✅ Configuration created!"

# Create a simple playbook that doesn't expect vault variables
cat > playbooks/site-no-vault.yml << EOF
---
- name: Deploy Matrix server (no vault)
  hosts: matrix_servers
  become: yes
  gather_facts: yes

  pre_tasks:
    - name: Display deployment info
      debug:
        msg: |
          =====================================
          MATRIX SERVER DEPLOYMENT STARTING
          =====================================
          Target: {{ inventory_hostname }}
          Matrix domain: {{ matrix_domain }}
          Homeserver: {{ matrix_homeserver_name }}
          SSL email: {{ ssl_email }}

    - name: Validate required variables are set
      assert:
        that:
          - matrix_domain is defined and matrix_domain != ""
          - matrix_homeserver_name is defined and matrix_homeserver_name != ""
          - ssl_email is defined and ssl_email != ""
        fail_msg: |
          Required variables missing. Check your configuration.

  roles:
    - role: user_management
      tags: ['users', 'ssh', 'security']

    - role: debian_hardening
      tags: ['hardening', 'security']

    - role: firewall
      tags: ['firewall', 'security']

    - role: ssl_certificates
      vars:
        ssl_domains:
          - "{{ matrix_domain }}"
          - "{{ matrix_homeserver_name }}"
      tags: ['ssl', 'certificates']

    - role: monitoring
      tags: ['monitoring', 'metrics']

    - role: caddy
      tags: ['webserver', 'proxy']

    - role: matrix_server
      tags: ['matrix', 'synapse', 'element']

  post_tasks:
    - name: Display deployment results
      debug:
        msg: |
          =====================================
          MATRIX SERVER DEPLOYMENT COMPLETE
          =====================================

          🏠 Homeserver: {{ matrix_homeserver_name }}
          🌐 Domain: {{ matrix_domain }}
          📧 SSL Email: {{ ssl_email }}
          🆔 Admin User: {{ admin_username }}

          🔗 URLs:
          📱 Element Web: https://{{ matrix_domain }}
          🔧 Admin Panel: https://{{ matrix_homeserver_name }}/_synapse/admin/

          📋 Next Steps:
          1. Configure DNS records
          2. Test Element: https://{{ matrix_domain }}
          3. Create users: sudo /usr/local/bin/create-matrix-admin.sh username password
EOF

echo ""
echo "🚀 Starting deployment..."

# Deploy using the no-vault playbook
ansible-playbook -i inventory/production/hosts.yml playbooks/site-no-vault.yml -v

echo ""
echo "🎉 Matrix server deployment complete!"
echo ""
echo "Admin credentials:"
echo "Username: $ADMIN_USERNAME"
echo "Password: $ADMIN_PASSWORD"
echo ""
echo "⚠️  IMPORTANT: Your secrets are stored in plain text in:"
echo "   inventory/production/group_vars/all.yml"
echo "   Consider encrypting this file manually later."
echo ""
echo "Next steps:"
echo "1. Configure DNS:"
echo "   $MATRIX_DOMAIN → $(hostname -I | awk '{print $1}')"
echo "   $HOMESERVER_DOMAIN → $(hostname -I | awk '{print $1}')"
echo ""
echo "2. Test at: https://$MATRIX_DOMAIN"
echo ""
echo "3. Create more users:"
echo "   sudo /usr/local/bin/create-matrix-admin.sh username password"
echo ""
echo "4. Monitor services:"
echo "   systemctl status matrix-synapse caddy postgresql redis-server"
echo ""