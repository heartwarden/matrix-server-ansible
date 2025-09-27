#!/bin/bash
# Test script for TUI configuration

# Test the domain configuration function
source ./configure-matrix.sh

echo "Testing domain validation..."

# Test domains
test_domains=("chat.example.com" "matrix.mydomain.org" "invalid" "test..com" ".invalid.com" "valid-domain.co.uk")

for domain in "${test_domains[@]}"; do
    if validate_domain "$domain"; then
        echo "✅ Valid: $domain"
    else
        echo "❌ Invalid: $domain"
    fi
done

echo ""
echo "Testing email validation..."

# Test emails
test_emails=("admin@example.com" "test@domain.org" "invalid" "test@" "@domain.com" "user.name+tag@domain.co.uk")

for email in "${test_emails[@]}"; do
    if validate_email "$email"; then
        echo "✅ Valid: $email"
    else
        echo "❌ Invalid: $email"
    fi
done