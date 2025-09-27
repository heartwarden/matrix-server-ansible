#!/bin/bash
# Ultra Simple Matrix Server - No Python package issues
# Uses only system packages

set -e

echo "🚀 Ultra Simple Matrix Server"
echo "============================="
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "❌ Please run as root: sudo $0"
    exit 1
fi

# Get configuration
read -p "Matrix domain (like chat.example.com): " MATRIX_DOMAIN
read -p "Homeserver domain (like matrix.example.com): " HOMESERVER_DOMAIN
read -p "SSL email: " SSL_EMAIL
read -p "Admin username [zerokaine]: " ADMIN_USERNAME
ADMIN_USERNAME=${ADMIN_USERNAME:-zerokaine}

echo -n "Admin password (leave empty for auto-gen): "
read -s ADMIN_PASSWORD
echo ""

if [ -z "$ADMIN_PASSWORD" ]; then
    ADMIN_PASSWORD=$(openssl rand -base64 12)
    echo "Generated password: $ADMIN_PASSWORD"
fi

read -p "Enable user registration? (y/N): " ENABLE_REG

echo ""
echo "Configuration:"
echo "Matrix Domain: $MATRIX_DOMAIN"
echo "Homeserver: $HOMESERVER_DOMAIN"
echo "Admin User: $ADMIN_USERNAME"
echo ""

read -p "Deploy now? (y/N): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    exit 0
fi

echo ""
echo "🔧 Installing Matrix server..."

# Update system
apt update
apt upgrade -y

# Install from Debian repos only
apt install -y postgresql postgresql-contrib redis-server curl gnupg lsb-release

# Install Caddy
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
apt update
apt install -y caddy

# Install Matrix Synapse from system packages
apt install -y matrix-synapse

# Generate secrets
echo "🔐 Generating secrets..."
DB_PASSWORD=$(openssl rand -hex 16)
MACAROON_SECRET=$(openssl rand -hex 32)
FORM_SECRET=$(openssl rand -hex 32)
REGISTRATION_SECRET=$(openssl rand -hex 16)

# Configure PostgreSQL
echo "🗄️ Setting up database..."
sudo -u postgres createuser synapse_user || true
sudo -u postgres createdb --encoding=UTF8 --locale=C --template=template0 --owner=synapse_user synapse || true
sudo -u postgres psql -c "ALTER USER synapse_user PASSWORD '$DB_PASSWORD';" || true

# Configure Synapse
echo "⚙️ Configuring Synapse..."

# Stop synapse
systemctl stop matrix-synapse 2>/dev/null || true

# Backup existing config
if [ -f "/etc/matrix-synapse/homeserver.yaml" ]; then
    cp /etc/matrix-synapse/homeserver.yaml /etc/matrix-synapse/homeserver.yaml.backup
fi

# Create new config
cat > /etc/matrix-synapse/homeserver.yaml << EOF
server_name: "$HOMESERVER_DOMAIN"
public_baseurl: "https://$HOMESERVER_DOMAIN"

listeners:
  - port: 8008
    tls: false
    type: http
    x_forwarded: true
    bind_addresses: ['127.0.0.1']
    resources:
      - names: [client, federation]
        compress: false

database:
  name: psycopg2
  args:
    user: synapse_user
    password: $DB_PASSWORD
    database: synapse
    host: localhost
    cp_min: 5
    cp_max: 10

log_config: "/etc/matrix-synapse/log.yaml"
media_store_path: "/var/lib/matrix-synapse/media"
uploads_path: "/var/lib/matrix-synapse/uploads"

registration_shared_secret: "$REGISTRATION_SECRET"
macaroon_secret_key: "$MACAROON_SECRET"
form_secret: "$FORM_SECRET"

signing_key_path: "/etc/matrix-synapse/signing.key"

trusted_key_servers:
  - server_name: "matrix.org"

# Privacy settings
enable_registration: $([ "$ENABLE_REG" = "y" ] && echo "true" || echo "false")
registration_requires_token: false
enable_registration_captcha: false
registration_requires_email: false

# No IP logging
suppress_key_server_warning: true

# Admin contact
admin_contact: "$SSL_EMAIL"

# Rate limiting
rc_message:
  per_second: 0.2
  burst_count: 10.0

# Media retention
media_retention:
  local_media_lifetime: 90d
  remote_media_lifetime: 90d

# Security
bcrypt_rounds: 12

# Presence
presence:
  enabled: true
EOF

# Generate signing key if it doesn't exist
if [ ! -f "/etc/matrix-synapse/signing.key" ]; then
    openssl genpkey -algorithm ed25519 -out /etc/matrix-synapse/signing.key
fi

# Create log config
cat > /etc/matrix-synapse/log.yaml << EOF
version: 1

formatters:
  precise:
    format: '%(asctime)s - %(name)s - %(lineno)d - %(levelname)s - %(message)s'

handlers:
  file:
    class: logging.handlers.RotatingFileHandler
    formatter: precise
    filename: /var/log/matrix-synapse/homeserver.log
    maxBytes: 104857600
    backupCount: 10
    encoding: utf8

root:
  level: INFO
  handlers: [file]

loggers:
  synapse.access:
    level: ERROR
  synapse.http.server:
    level: WARNING

disable_existing_loggers: false
EOF

# Set permissions
mkdir -p /var/log/matrix-synapse
chown -R matrix-synapse:matrix-synapse /etc/matrix-synapse /var/lib/matrix-synapse /var/log/matrix-synapse

# Configure Caddy
echo "🌐 Setting up Caddy..."
cat > /etc/caddy/Caddyfile << EOF
# Matrix Synapse
$HOMESERVER_DOMAIN {
    reverse_proxy /_matrix/* localhost:8008
    reverse_proxy /_synapse/* localhost:8008

    header {
        X-Content-Type-Options nosniff
        X-Frame-Options DENY
        Referrer-Policy strict-origin-when-cross-origin
    }
}

# Element Web
$MATRIX_DOMAIN {
    root * /var/www/element
    file_server

    header {
        X-Content-Type-Options nosniff
        X-Frame-Options DENY
        Referrer-Policy strict-origin-when-cross-origin
    }
}
EOF

# Install Element Web
echo "🌍 Installing Element Web..."
mkdir -p /var/www/element
cd /tmp
ELEMENT_VERSION="v1.11.50"
wget -q https://github.com/vector-im/element-web/releases/download/$ELEMENT_VERSION/element-$ELEMENT_VERSION.tar.gz
tar -xzf element-$ELEMENT_VERSION.tar.gz
cp -r element-$ELEMENT_VERSION/* /var/www/element/

# Configure Element
cat > /var/www/element/config.json << EOF
{
    "default_server_config": {
        "m.homeserver": {
            "base_url": "https://$HOMESERVER_DOMAIN",
            "server_name": "$HOMESERVER_DOMAIN"
        }
    },
    "brand": "Element",
    "showLabsSettings": false,
    "roomDirectory": {
        "servers": ["$HOMESERVER_DOMAIN", "matrix.org"]
    },
    "enable_presence_by_hs_url": {
        "https://$HOMESERVER_DOMAIN": true
    },
    "setting_defaults": {
        "breadcrumbs": true
    }
}
EOF

chown -R www-data:www-data /var/www/element

# Create admin script
cat > /usr/local/bin/create-matrix-admin.sh << 'EOF'
#!/bin/bash
if [ $# -ne 2 ]; then
    echo "Usage: $0 <username> <password>"
    exit 1
fi

USERNAME="$1"
PASSWORD="$2"
HOMESERVER=$(grep "server_name:" /etc/matrix-synapse/homeserver.yaml | cut -d'"' -f2 | head -n1)

# Try register_new_matrix_user
if command -v register_new_matrix_user >/dev/null 2>&1; then
    register_new_matrix_user -u "$USERNAME" -p "$PASSWORD" -a -c /etc/matrix-synapse/homeserver.yaml http://localhost:8008
else
    echo "❌ register_new_matrix_user not found"
    echo "Create user manually via Element web or another Matrix client"
fi
EOF

chmod +x /usr/local/bin/create-matrix-admin.sh

# Start services
echo "🚀 Starting services..."
systemctl enable redis-server postgresql caddy matrix-synapse
systemctl start redis-server postgresql
systemctl start matrix-synapse
sleep 5
systemctl start caddy

# Create admin user
echo "👤 Creating admin user..."
sleep 5
if command -v register_new_matrix_user >/dev/null 2>&1; then
    register_new_matrix_user -u "$ADMIN_USERNAME" -p "$ADMIN_PASSWORD" -a -c /etc/matrix-synapse/homeserver.yaml http://localhost:8008 || {
        echo "⚠️  Admin user creation failed - create manually after setup"
        echo "Command: sudo /usr/local/bin/create-matrix-admin.sh $ADMIN_USERNAME $ADMIN_PASSWORD"
    }
else
    echo "⚠️  register_new_matrix_user not available - create admin user manually"
    echo "Use Element web interface or another Matrix client"
fi

echo ""
echo "🎉 Matrix server setup complete!"
echo ""
echo "Admin credentials:"
echo "Username: $ADMIN_USERNAME"
echo "Password: $ADMIN_PASSWORD"
echo ""
echo "URLs:"
echo "Element Web: https://$MATRIX_DOMAIN"
echo "Homeserver: https://$HOMESERVER_DOMAIN"
echo ""
echo "Configure DNS:"
echo "$MATRIX_DOMAIN → $(hostname -I | awk '{print $1}')"
echo "$HOMESERVER_DOMAIN → $(hostname -I | awk '{print $1}')"
echo ""
echo "Service status:"
systemctl status matrix-synapse caddy postgresql redis-server --no-pager -l
echo ""
echo "Create more users:"
echo "sudo /usr/local/bin/create-matrix-admin.sh username password"
echo ""
echo "If admin user creation failed, create it manually via Element web interface"
echo ""