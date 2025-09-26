#!/bin/bash
# Matrix Server Setup Script for macOS/Linux
# Prepares local environment for Matrix server deployment via GitHub

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Configuration
ANSIBLE_VERSION="core>=2.12,<2.16"
PYTHON_MIN_VERSION="3.8"

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

detect_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo "linux"
    else
        echo "unknown"
    fi
}

check_requirements() {
    log "Checking system requirements..."

    local os=$(detect_os)
    info "Detected OS: $os"

    # Check Python version
    if command -v python3 &> /dev/null; then
        PYTHON_VERSION=$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:2])))')
        info "Python version: $PYTHON_VERSION"

        if ! python3 -c "import sys; exit(0 if sys.version_info >= (3, 8) else 1)"; then
            error "Python 3.8 or higher is required. Found: $PYTHON_VERSION"

            if [[ "$os" == "macos" ]]; then
                echo "Install with: brew install python@3.11"
            elif [[ "$os" == "linux" ]]; then
                echo "Install with: sudo apt update && sudo apt install python3.11"
            fi
            exit 1
        fi
    else
        error "Python 3 is not installed"
        exit 1
    fi

    # Check if pip is installed
    if ! command -v pip3 &> /dev/null; then
        error "pip3 is not installed"

        if [[ "$os" == "macos" ]]; then
            echo "Install with: python3 -m ensurepip --upgrade"
        elif [[ "$os" == "linux" ]]; then
            echo "Install with: sudo apt install python3-pip"
        fi
        exit 1
    fi

    # Check for whiptail (required for TUI)
    if ! command -v whiptail &> /dev/null; then
        warn "whiptail not found - required for TUI configuration"

        if [[ "$os" == "macos" ]]; then
            info "Install with: brew install newt"
        elif [[ "$os" == "linux" ]]; then
            info "Install with: sudo apt install whiptail"
        fi

        echo
        read -p "Install whiptail automatically? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            install_whiptail "$os"
        else
            warn "TUI configuration will not be available without whiptail"
        fi
    fi

    # Check if git is installed
    if ! command -v git &> /dev/null; then
        error "Git is not installed"
        exit 1
    fi

    # Check if SSH is available
    if ! command -v ssh &> /dev/null; then
        error "SSH client is not installed"
        exit 1
    fi

    log "System requirements check completed"
}

install_whiptail() {
    local os=$1

    info "Installing whiptail..."

    if [[ "$os" == "macos" ]]; then
        if command -v brew &> /dev/null; then
            brew install newt
        else
            error "Homebrew not found. Please install Homebrew first: https://brew.sh/"
            exit 1
        fi
    elif [[ "$os" == "linux" ]]; then
        if command -v apt &> /dev/null; then
            sudo apt update && sudo apt install -y whiptail
        elif command -v yum &> /dev/null; then
            sudo yum install -y newt
        elif command -v dnf &> /dev/null; then
            sudo dnf install -y newt
        else
            error "Package manager not supported. Please install whiptail manually."
            exit 1
        fi
    fi

    success "whiptail installed successfully"
}

create_virtual_environment() {
    log "Setting up Python virtual environment..."

    # Create virtual environment if it doesn't exist
    if [ ! -d "$PROJECT_DIR/venv" ]; then
        info "Creating Python virtual environment..."
        python3 -m venv "$PROJECT_DIR/venv"
    fi

    # Activate virtual environment
    source "$PROJECT_DIR/venv/bin/activate"

    # Upgrade pip
    pip install --upgrade pip

    success "Virtual environment ready"
}

install_ansible() {
    log "Installing Ansible and dependencies..."

    # Ensure we're in virtual environment
    if [ -z "${VIRTUAL_ENV:-}" ]; then
        source "$PROJECT_DIR/venv/bin/activate"
    fi

    # Install Ansible
    info "Installing Ansible $ANSIBLE_VERSION..."
    pip install "ansible-core$ANSIBLE_VERSION"
    pip install ansible

    # Install additional Python packages
    pip install jmespath  # Required for JSON queries in Ansible

    # Install Ansible collections
    info "Installing Ansible collections..."
    ansible-galaxy collection install community.general
    ansible-galaxy collection install ansible.posix
    ansible-galaxy collection install community.crypto

    success "Ansible installation completed"
}

create_directories() {
    log "Creating project directories..."

    # Create required directories
    mkdir -p "$PROJECT_DIR/server-configs"
    mkdir -p "$PROJECT_DIR/logs"
    mkdir -p "$PROJECT_DIR/backups"

    # Create .gitkeep files for empty directories
    touch "$PROJECT_DIR/server-configs/.gitkeep"
    touch "$PROJECT_DIR/logs/.gitkeep"
    touch "$PROJECT_DIR/backups/.gitkeep"

    success "Directories created"
}

create_activation_script() {
    log "Creating environment activation script..."

    cat > "$PROJECT_DIR/activate" << 'EOF'
#!/bin/bash
# Activate the Matrix Server Ansible environment

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Activate virtual environment
if [ -f "$SCRIPT_DIR/venv/bin/activate" ]; then
    source "$SCRIPT_DIR/venv/bin/activate"
    echo -e "${GREEN}Matrix Server Ansible environment activated${NC}"
else
    echo -e "${YELLOW}Virtual environment not found. Run ./scripts/setup.sh first.${NC}"
    exit 1
fi

echo
echo -e "${BLUE}Available commands:${NC}"
echo "  ./scripts/configure-server.sh           # Configure new server (TUI)"
echo "  ansible-playbook playbooks/site.yml     # Deploy complete setup"
echo "  ansible-playbook playbooks/hardening.yml# Security hardening only"
echo "  ansible-playbook playbooks/matrix.yml   # Matrix server only"
echo "  ansible-playbook playbooks/maintenance.yml # System maintenance"
echo
echo -e "${BLUE}Configuration files in:${NC} server-configs/"
echo -e "${BLUE}Documentation:${NC} README.md"
echo
EOF

    chmod +x "$PROJECT_DIR/activate"

    success "Activation script created"
}

create_helper_scripts() {
    log "Creating helper scripts..."

    # Create quick deploy script
    cat > "$PROJECT_DIR/scripts/quick-deploy.sh" << 'EOF'
#!/bin/bash
# Quick deployment script for existing configurations

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_DIR="$PROJECT_DIR/server-configs"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

if [ ! -d "$CONFIG_DIR" ] || [ -z "$(ls -A $CONFIG_DIR 2>/dev/null)" ]; then
    echo -e "${RED}No server configurations found.${NC}"
    echo -e "${BLUE}Run ./scripts/configure-server.sh first.${NC}"
    exit 1
fi

echo -e "${BLUE}Available server configurations:${NC}"
ls -1 "$CONFIG_DIR"/*.yml 2>/dev/null | sed 's/.*\///' | sed 's/-config.yml//' | nl

echo
read -p "Enter server number to deploy: " server_num

servers=($(ls -1 "$CONFIG_DIR"/*-config.yml 2>/dev/null | sed 's/.*\///' | sed 's/-config.yml//'))
if [ "$server_num" -lt 1 ] || [ "$server_num" -gt "${#servers[@]}" ]; then
    echo -e "${RED}Invalid selection${NC}"
    exit 1
fi

server_name="${servers[$((server_num-1))]}"
deploy_script="$CONFIG_DIR/${server_name}-deploy.sh"

if [ -f "$deploy_script" ]; then
    echo -e "${GREEN}Deploying $server_name...${NC}"
    cd "$CONFIG_DIR"
    "./${server_name}-deploy.sh"
else
    echo -e "${RED}Deploy script not found: $deploy_script${NC}"
    exit 1
fi
EOF

    chmod +x "$PROJECT_DIR/scripts/quick-deploy.sh"

    # Create status check script
    cat > "$PROJECT_DIR/scripts/check-servers.sh" << 'EOF'
#!/bin/bash
# Check status of all configured servers

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_DIR="$PROJECT_DIR/server-configs"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ ! -d "$CONFIG_DIR" ]; then
    echo -e "${RED}No server configurations found.${NC}"
    exit 1
fi

echo -e "${BLUE}Checking configured servers...${NC}"
echo

for inventory in "$CONFIG_DIR"/*-inventory.yml; do
    if [ -f "$inventory" ]; then
        server_name=$(basename "$inventory" -inventory.yml)
        echo -e "${BLUE}Checking $server_name:${NC}"

        if ansible all -i "$inventory" -m ping --one-line 2>/dev/null; then
            echo -e "${GREEN}✓ $server_name is reachable${NC}"
        else
            echo -e "${RED}✗ $server_name is unreachable${NC}"
        fi
        echo
    fi
done
EOF

    chmod +x "$PROJECT_DIR/scripts/check-servers.sh"

    success "Helper scripts created"
}

setup_git_hooks() {
    log "Setting up Git configuration..."

    # Create .github directory for workflow templates
    mkdir -p "$PROJECT_DIR/.github/workflows"

    # Create a GitHub Actions workflow template
    cat > "$PROJECT_DIR/.github/workflows/ansible-lint.yml" << 'EOF'
name: Ansible Lint

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  lint:
    runs-on: ubuntu-latest

    steps:
    - uses: actions/checkout@v3

    - name: Set up Python
      uses: actions/setup-python@v4
      with:
        python-version: '3.11'

    - name: Install dependencies
      run: |
        python -m pip install --upgrade pip
        pip install ansible-lint ansible-core
        ansible-galaxy collection install community.general ansible.posix community.crypto

    - name: Run ansible-lint
      run: |
        ansible-lint playbooks/ roles/
EOF

    success "Git hooks and workflows configured"
}

display_summary() {
    log "Setup completed successfully!"
    echo
    success "Matrix Server Ansible is ready!"
    echo
    info "Next steps:"
    echo "1. Activate environment:    source activate"
    echo "2. Configure server:       ./scripts/configure-server.sh"
    echo "3. Deploy server:          (generated deploy script in server-configs/)"
    echo
    info "Quick commands:"
    echo "• Check servers:           ./scripts/check-servers.sh"
    echo "• Quick deploy:            ./scripts/quick-deploy.sh"
    echo "• Documentation:           cat README.md"
    echo
    warn "Important files:"
    echo "• Virtual environment:     venv/"
    echo "• Server configs:          server-configs/ (not in git)"
    echo "• Deployment logs:         logs/"
    echo
    info "For GitHub workflow:"
    echo "1. Create repository and push this code"
    echo "2. Clone on deployment machine: git clone <your-repo>"
    echo "3. Run setup: ./scripts/setup.sh"
    echo "4. Configure: ./scripts/configure-server.sh"
    echo
    success "Happy Matrix deployment! 🚀"
}

show_banner() {
    clear
    echo -e "${CYAN}"
    cat << 'EOF'
    ███╗   ███╗ █████╗ ████████╗██████╗ ██╗██╗  ██╗
    ████╗ ████║██╔══██╗╚══██╔══╝██╔══██╗██║╚██╗██╔╝
    ██╔████╔██║███████║   ██║   ██████╔╝██║ ╚███╔╝
    ██║╚██╔╝██║██╔══██║   ██║   ██╔══██╗██║ ██╔██╗
    ██║ ╚═╝ ██║██║  ██║   ██║   ██║  ██║██║██╔╝ ██╗
    ╚═╝     ╚═╝╚═╝  ╚═╝   ╚═╝   ╚═╝  ╚═╝╚═╝╚═╝  ╚═╝

    Secure Matrix Server Ansible Setup
    GitHub-Ready Deployment System
EOF
    echo -e "${NC}"
    echo
}

main() {
    show_banner

    check_requirements
    create_virtual_environment
    install_ansible
    create_directories
    create_activation_script
    create_helper_scripts
    setup_git_hooks

    display_summary
}

# Run main function
main "$@"