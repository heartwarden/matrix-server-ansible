# 🚀 Simple Matrix Server Deployment

**Tired of complex scripts? This is the bulletproof method.**

## Quick Start (3 Steps)

### 1. Generate Secrets
```bash
# On your server
cd /root/matrix-server-ansible
./setup-matrix-secrets.sh
```

### 2. Configure Server
```bash
# Edit server details
nano inventory/production/hosts.yml
```

Update with your server IP:
```yaml
matrix_servers:
  hosts:
    your-domain.com:
      ansible_host: YOUR_SERVER_IP
      ansible_user: root
```

### 3. Deploy
```bash
./deploy-matrix.sh
```

That's it! 🎉

## What Each Script Does

### `setup-matrix-secrets.sh`
- Generates all required secrets securely
- Creates encrypted vault file
- Updates domain configuration
- Tests everything works

**No complex options, just works.**

### `deploy-matrix.sh`
- Simple deployment script
- Clear error messages
- Tests connectivity first
- Shows progress

**No fancy features, just deploys.**

## If Something Goes Wrong

### Secrets not working?
```bash
# Clean start
rm -rf inventory/production/group_vars/all/vault.yml
rm -f .vault_pass
./setup-matrix-secrets.sh
```

### Deployment failing?
```bash
# Check connectivity
ansible all -i inventory/production/hosts.yml -m ping --ask-vault-pass

# Deploy specific part
./deploy-matrix.sh production hardening  # Just hardening
./deploy-matrix.sh production matrix     # Just Matrix
```

### Need to see what's happening?
```bash
# Add debug output
ansible-playbook -i inventory/production/hosts.yml playbooks/site.yml --ask-vault-pass -vvv
```

## File Structure

```
inventory/production/
├── hosts.yml                    # Your server details
└── group_vars/
    └── all/
        ├── vault.yml            # Encrypted secrets
        └── all.yml              # Configuration

.vault_pass                      # Vault password (optional)
setup-matrix-secrets.sh          # Generate secrets
deploy-matrix.sh                 # Deploy Matrix
```

## Troubleshooting

**"vault file not found"**
→ Run `./setup-matrix-secrets.sh`

**"server not reachable"**
→ Check `inventory/production/hosts.yml`

**"vault password wrong"**
→ Check `.vault_pass` file or use `--ask-vault-pass`

**"domain not working"**
→ Configure DNS: your-domain → your-server-IP

## Advanced Usage

```bash
# Different environment
./setup-matrix-secrets.sh staging
./deploy-matrix.sh staging

# Specific playbook
./deploy-matrix.sh production hardening
./deploy-matrix.sh production matrix
./deploy-matrix.sh production maintenance

# Manual deployment
ansible-playbook -i inventory/production/hosts.yml playbooks/site.yml --vault-password-file .vault_pass
```

## Security

- All secrets are randomly generated
- Vault file is encrypted with AES-256
- No secrets stored in plain text
- Vault password can be in `.vault_pass` or entered manually

---

**This method works. No complexity, no fancy features, just deploys your Matrix server.** 🛡️