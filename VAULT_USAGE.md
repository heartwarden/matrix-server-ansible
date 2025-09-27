# Ansible Vault Usage Guide

This project uses Ansible Vault to encrypt sensitive data like passwords, API keys, and SSH keys.

## 🔐 Vault Structure

```
group_vars/
├── all/
│   └── vault.yml           # Global encrypted secrets
└── matrix_servers/
    └── vault.yml           # Matrix server encrypted secrets

server-configs/ (not in git)
├── server-name-vault.yml   # Server-specific secrets
├── server-name-vault-pass  # Server vault password
└── server-name-vault-info.txt # Vault reference
```

## 🔑 Vault Password

The main vault password is stored in `.vault_pass` (not in git) and is automatically used by Ansible.

**IMPORTANT**: Back up your vault password securely! Without it, you cannot decrypt your secrets.

## 📝 Working with Vault Files

### View encrypted files:
```bash
# Global vault
ansible-vault view group_vars/all/vault.yml

# Matrix servers vault
ansible-vault view group_vars/matrix_servers/vault.yml

# Server-specific vault
ansible-vault view server-configs/server-name-vault.yml --vault-password-file=server-configs/server-name-vault-pass
```

### Edit encrypted files:
```bash
# Global vault
ansible-vault edit group_vars/all/vault.yml

# Matrix servers vault
ansible-vault edit group_vars/matrix_servers/vault.yml

# Server-specific vault
ansible-vault edit server-configs/server-name-vault.yml --vault-password-file=server-configs/server-name-vault-pass
```

### Encrypt new files:
```bash
ansible-vault encrypt secret_file.yml
```

### Decrypt files temporarily:
```bash
ansible-vault decrypt group_vars/matrix_servers/vault.yml --output=-
```

## 🔧 Server-Specific Secrets

When you run `./scripts/configure-server.sh`, it creates:
- `server-configs/server-name-vault.yml` (encrypted)
- `server-configs/server-name-vault-pass` (vault password)
- `server-configs/server-name-vault-info.txt` (reference guide)

These files contain server-specific secrets and are excluded from git.

## 🚀 Deployment with Vault

All deployment scripts automatically use the vault:

```bash
# Automatic vault usage (recommended)
cd server-configs
./server-name-deploy.sh

# Manual deployment with vault
ansible-playbook playbooks/site.yml \
  -i server-configs/server-inventory.yml \
  --vault-password-file=server-configs/server-vault-pass \
  --extra-vars="@server-configs/server-vault.yml"
```

## 🔒 Security Best Practices

1. **Never commit vault passwords to git**
2. **Store vault passwords in a secure password manager**
3. **Use different vault passwords for different environments**
4. **Regularly rotate secrets in vault files**
5. **Limit access to vault passwords**
6. **Test vault decryption before deployment**

## 📋 Vault Variables Reference

### Global Vault (`group_vars/all/vault.yml`)
- `vault_global_admin_email`: Global admin email
- `vault_alert_email`: Alert notifications email
- `vault_monitoring_slack_webhook`: Slack integration
- `vault_backup_encryption_passphrase`: Backup encryption

### Matrix Vault (`group_vars/matrix_servers/vault.yml`)
- `vault_matrix_database_password`: Default PostgreSQL password template
- `vault_coturn_secret`: Default TURN server secret template
- `vault_registration_secret`: Default Matrix registration secret template
- `vault_macaroon_secret_key`: Default Matrix macaroon key template
- `vault_form_secret`: Default Matrix form secret template

### Server-Specific Vault (per server)
Generated automatically with unique passwords for each server:
- `vault_matrix_database_password`: Unique PostgreSQL password
- `vault_coturn_secret`: Unique TURN server secret
- `vault_registration_secret`: Unique Matrix registration secret
- `vault_macaroon_secret_key`: Unique Matrix macaroon key
- `vault_form_secret`: Unique Matrix form secret
- `vault_ssh_public_key`: SSH public key for zerokaine user
- `vault_ssl_email`: SSL certificate email
- `vault_backup_encryption_key`: Unique backup encryption key
- `vault_api_secret`: API authentication token
- `vault_webhook_secret`: Webhook verification secret

## 🆘 Vault Recovery

If you lose your vault password:
1. You'll need to recreate all encrypted files
2. Generate new passwords for all services
3. Redeploy affected servers

**Prevention**: Always back up vault passwords securely!

## 💡 Vault Tips

### Check vault status:
```bash
# Test if vault can be decrypted
ansible-vault view group_vars/matrix_servers/vault.yml --vault-password-file=.vault_pass | head -5
```

### Rekey vault (change password):
```bash
ansible-vault rekey group_vars/matrix_servers/vault.yml
```

### Create new encrypted variable:
```bash
# Interactive
ansible-vault encrypt_string 'my_secret_value' --name 'vault_my_variable'

# From file
ansible-vault encrypt_string --vault-password-file=.vault_pass 'secret_value' --name 'vault_variable'
```

### Decrypt for troubleshooting:
```bash
# Temporarily decrypt for viewing (doesn't save)
ansible-vault decrypt group_vars/matrix_servers/vault.yml --output=-
```

## 🎯 Caddy Configuration with Vault

The vault secrets are automatically used in:
- Matrix homeserver configuration
- Database connection strings
- SSL certificate email addresses
- Security tokens for APIs
- Backup encryption keys

All sensitive Caddy configuration is templated and uses vault variables for security.