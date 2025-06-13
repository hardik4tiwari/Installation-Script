#!/bin/bash

set -e # Exit on error

# Color codes
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_message() { echo -e "${CYAN}$1${NC}"; }
print_success() { echo -e "${GREEN}$1${NC}"; }
print_warning() { echo -e "${YELLOW}$1${NC}"; }
print_error() { echo -e "${RED}$1${NC}"; }

# Detect OS
if [[ "$OSTYPE" == "darwin"* ]]; then
    OS_TYPE="macos"
    print_message "Detected macOS system"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS_TYPE="linux"
    print_message "Detected Linux system"
else
    print_error "Unsupported operating system: $OSTYPE"
    exit 1
fi

print_message "Starting Godspeed Full Installation..."

# Homebrew for macOS
if [[ "$OS_TYPE" == "macos" ]]; then
    print_message "Checking for Homebrew..."
    if ! command -v brew &> /dev/null; then
        print_message "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    else
        print_message "Homebrew is already installed. Updating..."
        brew update
    fi
fi

# Setup NVM
print_message "Setting up NVM (Node Version Manager)..."

if ! command -v nvm &> /dev/null; then
    if [[ "$OS_TYPE" == "macos" ]]; then
        brew install nvm
        mkdir -p ~/.nvm
        if ! grep -q "NVM_DIR" ~/.zshrc; then
            echo 'export NVM_DIR="$HOME/.nvm"' >> ~/.zshrc
            echo '[ -s "/opt/homebrew/opt/nvm/nvm.sh" ] && \. "/opt/homebrew/opt/nvm/nvm.sh"' >> ~/.zshrc
            echo '[ -s "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm" ] && \. "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm"' >> ~/.zshrc
        fi
    else
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
    fi
fi

# Load NVM for this session
export NVM_DIR="$HOME/.nvm"

if [[ "$OS_TYPE" == "macos" ]]; then
    NVM_SH="/opt/homebrew/opt/nvm/nvm.sh"
else
    NVM_SH="$NVM_DIR/nvm.sh"
fi

if [[ -s "$NVM_SH" ]]; then
    \. "$NVM_SH"
else
    print_error "Failed to load NVM. Please restart your terminal and try again."
    exit 1
fi

# Verify NVM
if ! command -v nvm &> /dev/null; then
    print_error "NVM still not detected after loading. Please restart your terminal and rerun the script."
    exit 1
fi

print_success "NVM loaded successfully."

# Install Node.js
print_message "Installing Node.js LTS via NVM..."
nvm install --lts
nvm use --lts

# Check Node.js
if ! command -v node &> /dev/null; then
    print_error "Node.js installation failed."
    exit 1
fi

print_success "Node.js version: $(node -v)"
print_success "npm version: $(npm -v)"

# Enable Corepack and pnpm
print_message "Configuring package managers..."
corepack enable
corepack prepare pnpm@latest --activate

# Git check/install
print_message "Checking for Git..."
if ! command -v git &> /dev/null; then
    print_message "Installing Git..."
    if [[ "$OS_TYPE" == "macos" ]]; then
        brew install git
    else
        sudo apt-get update && sudo apt-get install -y git
    fi
fi

print_success "Git version: $(git --version)"

# Godspeed CLI
print_message "Installing Godspeed CLI..."
npm install -g @godspeedsystems/godspeed

if ! command -v godspeed &> /dev/null; then
    print_error "Godspeed CLI installation failed."
    exit 1
fi

# Daemon Installation
print_message "Starting Daemon Installation..."

if [[ "$OS_TYPE" == "macos" ]]; then
    if [[ $(uname -m) == 'arm64' ]]; then
        DAEMON_URL="https://github.com/zero8dotdev/install-godspeed-daemon/releases/download/v1.1.2/godspeed-daemon-macos-arm64"
    else
        DAEMON_URL="https://github.com/zero8dotdev/install-godspeed-daemon/releases/download/v1.1.2/godspeed-daemon-macos"
    fi
    TARGET_DIR="$HOME/.local/bin"
else
    DAEMON_URL="https://github.com/zero8dotdev/install-godspeed-daemon/releases/download/v1.1.2/godspeed-daemon-linux"
    TARGET_DIR="/usr/local/bin"
fi

DESTINATION_PATH="$TARGET_DIR/godspeed-daemon"

if [[ "$OS_TYPE" == "macos" ]]; then
    mkdir -p "$TARGET_DIR"
    curl -L "$DAEMON_URL" -o "$DESTINATION_PATH"
    chmod +x "$DESTINATION_PATH"
else
    sudo mkdir -p "$TARGET_DIR"
    sudo curl -L "$DAEMON_URL" -o "$DESTINATION_PATH"
    # chmod +x "$DESTINATION_PATH"
fi
    

# Add to PATH if needed
if [[ "$OS_TYPE" == "macos" ]]; then
    if ! grep -q "$TARGET_DIR" ~/.zshrc; then
        echo "export PATH=\"\$PATH:$TARGET_DIR\"" >> ~/.zshrc
    fi
    export PATH="$PATH:$TARGET_DIR"
fi

# Daemon config file
mkdir -p "$HOME/.godspeed"
if [ ! -f "$HOME/.godspeed/services.json" ]; then
    echo '{ "services": [] }' > "$HOME/.godspeed/services.json"
fi

print_success "Daemon installation completed successfully!"

print_message "To use the Godspeed daemon, run:"
echo "  godspeed-daemon"

# rag-node Installation and .env Setup
print_message "Installing rag-node..."
npm install -g rag-node

# Locate global installation directory
print_message "Locating global rag-node installation directory..."
PNPM_PREFIX=$(npm prefix -g)
RAG_NODE_DIR="$PNPM_PREFIX/lib/node_modules/rag-node"

if [[ ! -d "$RAG_NODE_DIR" ]]; then
    print_error "rag-node installation directory not found at $RAG_NODE_DIR"
    exit 1
fi

# Prompt user for GOOGLE_API_KEY with masking
print_message ""
print_message "Enter your GOOGLE_API_KEY for rag-node."
print_warning "Note: This key will NOT be stored or sent to any server. It will only be written to a local .env file."

# Prompt silently like sudo password (accepts even empty input)
read -rs -p "GOOGLE_API_KEY: " GOOGLE_API_KEY
echo ""

# Write to .env file in the rag-node directory
ENV_FILE="$RAG_NODE_DIR/.env"
echo "GOOGLE_API_KEY=$GOOGLE_API_KEY" > "$ENV_FILE"

print_success ".env file created at $ENV_FILE"

# Run `pnpm install` inside rag-node
# print_message "Running 'pnpm install' inside rag-node directory..."
# pushd "$RAG_NODE_DIR" > /dev/null
# pnpm install
# popd > /dev/null
# print_success "rag-node installation completed successfully!"


print_success "Godspeed CLI version: $(godspeed --version)"
print_success "Installation complete! Please restart your terminal for all changes to apply."
