#!/bin/bash
# Matrix Deployment - Working Around Ansible Vault Issues
# Uses manual encryption method that actually works

set -e

echo "🚀 Matrix Server Deploy (Working Solution)"
echo "========================================="
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

# Create all.yml
cat > inventory/production/group_vars/all.yml << EOF
---
matrix_domain: "$MATRIX_DOMAIN"
matrix_homeserver_name: "$HOMESERVER_DOMAIN"
ssl_email: "{{ vault_ssl_email }}"

# Security settings
ssh_port: 2222
fail2ban_enabled: true
ufw_enabled: true

# Matrix settings
matrix_registration_enabled: $ENABLE_REGISTRATION

# Admin user
admin_username: "{{ vault_admin_username }}"
create_user: "zerokaine"

# Vault secrets
matrix_database_password: "{{ vault_matrix_database_password }}"
form_secret: "{{ vault_form_secret }}"
macaroon_secret_key: "{{ vault_macaroon_secret_key }}"
registration_secret: "{{ vault_registration_secret }}"
coturn_secret: "{{ vault_coturn_secret }}"

# Privacy settings
matrix_presence_enabled: true
matrix_redaction_retention_period: 300
matrix_media_retention_days: 90
matrix_log_filter_ips: true
matrix_registration_requires_email: false
matrix_registration_requires_captcha: false
EOF

echo "🔐 Generating secrets..."

# Generate secrets
DB_PASSWORD=$(openssl rand -hex 16)
FORM_SECRET=$(openssl rand -hex 32)
MACAROON_SECRET=$(openssl rand -hex 32)
REGISTRATION_SECRET=$(openssl rand -hex 16)
COTURN_SECRET=$(openssl rand -hex 16)

# Generate vault password
VAULT_PASSWORD=$(openssl rand -base64 32)
echo "$VAULT_PASSWORD" > .vault_pass
chmod 600 .vault_pass

echo "🔐 Creating encrypted vault file using working method..."

# Create the vault content first
cat > /tmp/vault_content << EOF
---
vault_ssl_email: "$SSL_EMAIL"
vault_admin_username: "$ADMIN_USERNAME"
vault_admin_password: "$ADMIN_PASSWORD"
vault_matrix_database_password: "$DB_PASSWORD"
vault_form_secret: "$FORM_SECRET"
vault_macaroon_secret_key: "$MACAROON_SECRET"
vault_registration_secret: "$REGISTRATION_SECRET"
vault_coturn_secret: "$COTURN_SECRET"
EOF

# Try different ansible-vault methods
echo "Attempting vault encryption..."

# Method 1: Direct create
if echo "$VAULT_PASSWORD" | ansible-vault create inventory/production/group_vars/all/vault.yml --vault-id @prompt < /tmp/vault_content 2>/dev/null; then
    echo "✅ Method 1 successful"
elif ansible-vault create inventory/production/group_vars/all/vault.yml --ask-vault-pass < /tmp/vault_content 2>/dev/null; then
    echo "✅ Method 2 successful"
else
    echo "🔧 Using Python-based encryption fallback..."

    # Python fallback method
    python3 << EOF
import base64
from cryptography.fernet import Fernet
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
import os

# Read vault password
with open('.vault_pass', 'r') as f:
    password = f.read().strip()

# Read vault content
with open('/tmp/vault_content', 'r') as f:
    content = f.read()

# Simple encryption (not ansible-vault format but encrypted)
key = base64.urlsafe_b64encode(password.encode()[:32].ljust(32, b'0'))
f = Fernet(key)
encrypted = f.encrypt(content.encode())

# Write encrypted file with header
with open('inventory/production/group_vars/all/vault.yml', 'wb') as f:
    f.write(b'# Encrypted with Python fallback\n')
    f.write(encrypted)

print("✅ Python encryption successful")
EOF

    # Create a simple decrypt script for later
    cat > decrypt_vault.py << 'EOF'
#!/usr/bin/env python3
import base64
from cryptography.fernet import Fernet
import sys

if len(sys.argv) != 2:
    print("Usage: python3 decrypt_vault.py <vault_file>")
    sys.exit(1)

with open('.vault_pass', 'r') as f:
    password = f.read().strip()

with open(sys.argv[1], 'rb') as f:
    content = f.read()
    # Skip header line
    if content.startswith(b'# Encrypted'):
        content = content.split(b'\n', 1)[1]

key = base64.urlsafe_b64encode(password.encode()[:32].ljust(32, b'0'))
f = Fernet(key)
decrypted = f.decrypt(content)
print(decrypted.decode())
EOF
    chmod +x decrypt_vault.py
    echo "📝 Created decrypt_vault.py for manual decryption if needed"
fi

# Clean up
rm -f /tmp/vault_content

echo "✅ Configuration created with encrypted secrets!"
echo ""
echo "🚀 Starting deployment..."

# Use the best available playbook
PLAYBOOK="playbooks/site.yml"
if [ -f "playbooks/site-fixed.yml" ]; then
    PLAYBOOK="playbooks/site-fixed.yml"
fi

# Check if we have standard ansible-vault format
if head -1 inventory/production/group_vars/all/vault.yml | grep -q "ANSIBLE_VAULT"; then
    echo "Using standard ansible-vault format"
    ansible-playbook -i inventory/production/hosts.yml "$PLAYBOOK" --vault-password-file .vault_pass -v
else
    echo "Using Python-encrypted format, creating temp decrypted file..."
    python3 decrypt_vault.py inventory/production/group_vars/all/vault.yml > /tmp/decrypted_vault.yml
    mv /tmp/decrypted_vault.yml inventory/production/group_vars/all/vault.yml
    ansible-playbook -i inventory/production/hosts.yml "$PLAYBOOK" -v
    echo "🔐 Re-encrypting vault file..."
    python3 << EOF
import base64
from cryptography.fernet import Fernet

with open('.vault_pass', 'r') as f:
    password = f.read().strip()

with open('inventory/production/group_vars/all/vault.yml', 'r') as f:
    content = f.read()

key = base64.urlsafe_b64encode(password.encode()[:32].ljust(32, b'0'))
f = Fernet(key)
encrypted = f.encrypt(content.encode())

with open('inventory/production/group_vars/all/vault.yml', 'wb') as f:
    f.write(b'# Encrypted with Python fallback\n')
    f.write(encrypted)
EOF
fi

echo ""
echo "🎉 Matrix server deployment complete!"
echo ""
echo "Admin credentials:"
echo "Username: $ADMIN_USERNAME"
echo "Password: $ADMIN_PASSWORD"
echo ""
echo "🔐 Vault password saved to: .vault_pass (keep this secure!)"
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