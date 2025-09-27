#!/bin/bash
# One-Shot Matrix Deployment
# Single command to configure and deploy Matrix server

set -e

# Check if TUI configuration exists
if [ "$1" = "--configure" ] || [ ! -f "inventory/production/hosts.yml" ]; then
    echo "🚀 Starting TUI configuration..."
    ./configure-matrix.sh
else
    echo "🚀 Using existing configuration, deploying Matrix server..."

    # Quick validation
    if [ ! -f ".vault_pass" ]; then
        echo "❌ No vault password found. Run with --configure first."
        exit 1
    fi

    if [ ! -f "inventory/production/group_vars/all/vault.yml" ]; then
        echo "❌ No vault file found. Run with --configure first."
        exit 1
    fi

    # Deploy using smart deployment
    if [ -f "./smart-deploy.sh" ]; then
        ./smart-deploy.sh production site-fixed true
    else
        ./deploy-matrix.sh production site-fixed
    fi

    echo ""
    echo "✅ Matrix server deployment complete!"
    echo "🌐 Check your domain configuration and test Element web client"
fi