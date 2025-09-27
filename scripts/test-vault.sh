#!/bin/bash
# Test script to verify ansible-vault functionality

set -euo pipefail

# Create test directory
TEST_DIR="/tmp/vault-test-$$"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

echo "Testing ansible-vault functionality..."

# Create test password file
echo "test-password-123" > vault-pass

# Create test content
cat > test-content.yml << 'EOF'
---
test_secret: "this is a secret"
test_password: "super-secure-password"
EOF

echo "1. Testing vault encrypt with --output..."
if ansible-vault encrypt test-content.yml --vault-password-file=vault-pass --output=test-vault.yml 2>/dev/null; then
    echo "✅ Method 1 works: ansible-vault encrypt --output"
    METHOD1_SUCCESS=true
else
    echo "❌ Method 1 failed"
    METHOD1_SUCCESS=false
fi

# Reset for next test
cp test-content.yml test-content2.yml

echo "2. Testing vault encrypt with --encrypt-vault-id..."
if ansible-vault encrypt test-content2.yml --vault-password-file=vault-pass --encrypt-vault-id=default --output=test-vault2.yml 2>/dev/null; then
    echo "✅ Method 2 works: ansible-vault encrypt --encrypt-vault-id"
    METHOD2_SUCCESS=true
else
    echo "❌ Method 2 failed"
    METHOD2_SUCCESS=false
fi

# Reset for next test
cp test-content.yml test-content3.yml

echo "3. Testing vault encrypt in-place..."
if ansible-vault encrypt test-content3.yml --vault-password-file=vault-pass 2>/dev/null; then
    echo "✅ Method 3 works: ansible-vault encrypt (in-place)"
    METHOD3_SUCCESS=true
else
    echo "❌ Method 3 failed"
    METHOD3_SUCCESS=false
fi

echo
echo "Results:"
echo "Method 1 (--output): $($METHOD1_SUCCESS && echo "✅ SUCCESS" || echo "❌ FAILED")"
echo "Method 2 (--encrypt-vault-id): $($METHOD2_SUCCESS && echo "✅ SUCCESS" || echo "❌ FAILED")"
echo "Method 3 (in-place): $($METHOD3_SUCCESS && echo "✅ SUCCESS" || echo "❌ FAILED")"

# Test decryption
echo
echo "Testing decryption..."
if [ -f test-vault.yml ]; then
    if ansible-vault view test-vault.yml --vault-password-file=vault-pass >/dev/null 2>&1; then
        echo "✅ Decryption works"
    else
        echo "❌ Decryption failed"
    fi
fi

# Cleanup
cd /
rm -rf "$TEST_DIR"

echo "Vault test completed!"