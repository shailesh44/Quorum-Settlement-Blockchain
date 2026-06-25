#!/bin/bash

# ============================================================
# VittaGems Development Environment Setup Script
# Target: Ubuntu 22.04 LTS
# Installs: Docker, Docker Compose Plugin, Go 1.22
# Prerequisites: Node.js / nvm (already installed)
# ============================================================

set -e  # Exit on any error

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

print_step() {
    echo -e "\n${GREEN}[STEP]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_done() {
    echo -e "${GREEN}[DONE]${NC} $1"
}

echo "============================================================"
echo "  VittaGems â Development Environment Setup"
echo "  Ubuntu 22.04 | Docker + Docker Compose + Go"
echo "============================================================"

# --------------------------------------------------
# Pre-flight checks
# --------------------------------------------------
print_step "Running pre-flight checks..."

if [ "$(id -u)" -eq 0 ]; then
    print_error "Do not run this script as root. Run as your normal user â it will use sudo when needed."
    exit 1
fi

if ! grep -qi "ubuntu" /etc/os-release 2>/dev/null; then
    print_warn "This script is designed for Ubuntu. Proceed at your own risk on other distros."
fi

# --------------------------------------------------
# 1. System Update
# --------------------------------------------------
print_step "Updating system packages..."
sudo apt update && sudo apt upgrade -y

print_step "Installing essential tools..."
sudo apt install -y \
    curl \
    wget \
    git \
    build-essential \
    software-properties-common \
    jq \
    tree \
    apt-transport-https \
    ca-certificates \
    gnupg \
    lsb-release

# --------------------------------------------------
# 2. Docker Installation
# --------------------------------------------------
print_step "Checking for existing Docker installation..."

if command -v docker &>/dev/null; then
    DOCKER_VERSION=$(docker --version 2>/dev/null)
    print_warn "Docker is already installed: $DOCKER_VERSION"
    read -p "Do you want to reinstall Docker? (y/N): " REINSTALL_DOCKER
    if [[ "$REINSTALL_DOCKER" != "y" && "$REINSTALL_DOCKER" != "Y" ]]; then
        echo "Skipping Docker installation."
        SKIP_DOCKER=true
    fi
fi

if [ "$SKIP_DOCKER" != "true" ]; then
    print_step "Removing old Docker versions (if any)..."
    sudo apt remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

    print_step "Adding Docker official GPG key and repository..."
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    print_step "Installing Docker Engine and Docker Compose plugin..."
    sudo apt update
    sudo apt install -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin

    print_step "Adding current user to docker group..."
    sudo usermod -aG docker "$USER"

    print_done "Docker installed successfully."
fi

# --------------------------------------------------
# 3. Go Installation
# --------------------------------------------------
GO_VERSION="1.22.4"
GO_TAR="go${GO_VERSION}.linux-amd64.tar.gz"
GO_URL="https://go.dev/dl/${GO_TAR}"

print_step "Checking for existing Go installation..."

if command -v go &>/dev/null; then
    CURRENT_GO=$(go version 2>/dev/null)
    print_warn "Go is already installed: $CURRENT_GO"
    read -p "Do you want to reinstall Go ${GO_VERSION}? (y/N): " REINSTALL_GO
    if [[ "$REINSTALL_GO" != "y" && "$REINSTALL_GO" != "Y" ]]; then
        echo "Skipping Go installation."
        SKIP_GO=true
    fi
fi

if [ "$SKIP_GO" != "true" ]; then
    print_step "Downloading Go ${GO_VERSION}..."
    cd /tmp
    wget -q --show-progress "${GO_URL}"

    print_step "Installing Go to /usr/local/go..."
    sudo rm -rf /usr/local/go
    sudo tar -C /usr/local -xzf "${GO_TAR}"
    rm -f "${GO_TAR}"

    # Add Go to PATH in .bashrc if not already present
    GO_EXPORTS='
# Go language
export PATH=$PATH:/usr/local/go/bin
export GOPATH=$HOME/go
export PATH=$PATH:$GOPATH/bin'

    if ! grep -q "/usr/local/go/bin" "$HOME/.bashrc"; then
        print_step "Adding Go to PATH in ~/.bashrc..."
        echo "$GO_EXPORTS" >> "$HOME/.bashrc"
    else
        print_warn "Go PATH entries already exist in ~/.bashrc. Skipping."
    fi

    # Make Go available in current script
    export PATH=$PATH:/usr/local/go/bin
    export GOPATH=$HOME/go
    export PATH=$PATH:$GOPATH/bin

    mkdir -p "$GOPATH"

    print_done "Go ${GO_VERSION} installed successfully."
fi

# --------------------------------------------------
# 4. Create VittaGems project directory structure
# --------------------------------------------------
print_step "Creating VittaGems project directory structure..."

VITTAGEMS_DIR="$HOME/vittagems-blockchain"
mkdir -p "${VITTAGEMS_DIR}"/{contracts,scripts,test,config,docker,docs,monitoring}

cat > "${VITTAGEMS_DIR}/README.md" << 'README'
# VittaGems Settlement Blockchain Network

Permissioned settlement network built on Quorum for B2B cross-border value transfer.

## Directory Structure

```
vittagems-blockchain/
âââ contracts/       # Solidity smart contracts
âââ scripts/         # Deployment and utility scripts
âââ test/            # Contract and network tests
âââ config/          # Quorum node configs, genesis files
âââ docker/          # Docker Compose files for network
âââ docs/            # Architecture docs, runbooks
âââ monitoring/      # Grafana dashboards, alerting configs
```

## Quick Start

```bash
# Install Hardhat dependencies
npm install

# Compile contracts
npx hardhat compile

# Run local Quorum network
cd docker && docker compose up -d
```
README

print_done "Project directory created at ${VITTAGEMS_DIR}"

# --------------------------------------------------
# 5. Verification
# --------------------------------------------------
echo ""
echo "============================================================"
echo "  INSTALLATION VERIFICATION"
echo "============================================================"

echo ""

# Docker
if command -v docker &>/dev/null; then
    echo -e "  Docker:          ${GREEN}$(docker --version)${NC}"
else
    echo -e "  Docker:          ${RED}NOT FOUND${NC}"
fi

# Docker Compose
if docker compose version &>/dev/null 2>&1; then
    echo -e "  Docker Compose:  ${GREEN}$(docker compose version)${NC}"
else
    echo -e "  Docker Compose:  ${RED}NOT FOUND${NC}"
fi

# Go
if command -v go &>/dev/null || [ -x /usr/local/go/bin/go ]; then
    echo -e "  Go:              ${GREEN}$(/usr/local/go/bin/go version 2>/dev/null || go version)${NC}"
else
    echo -e "  Go:              ${RED}NOT FOUND${NC}"
fi

# Node
if command -v node &>/dev/null; then
    echo -e "  Node.js:         ${GREEN}$(node --version)${NC} (pre-existing)"
else
    echo -e "  Node.js:         ${YELLOW}Not found in current shell (reload nvm)${NC}"
fi

# npm
if command -v npm &>/dev/null; then
    echo -e "  npm:             ${GREEN}$(npm --version)${NC} (pre-existing)"
else
    echo -e "  npm:             ${YELLOW}Not found in current shell (reload nvm)${NC}"
fi

echo ""
echo -e "  Project dir:     ${GREEN}${VITTAGEMS_DIR}${NC}"
echo ""

# --------------------------------------------------
# 6. Post-install notes
# --------------------------------------------------
echo "============================================================"
echo "  IMPORTANT â READ BEFORE CONTINUING"
echo "============================================================"
echo ""
echo "  1. Docker group change requires a new session to take effect."
echo "     Run one of these:"
echo ""
echo "       newgrp docker          # Quick fix for current terminal"
echo "       # OR log out and log back in"
echo ""
echo "  2. Go PATH is set in ~/.bashrc. To use it now:"
echo ""
echo "       source ~/.bashrc"
echo ""
echo "  3. Next steps for VittaGems:"
echo ""
echo "       cd ~/vittagems-blockchain"
echo "       npm init -y"
echo "       npm install --save-dev hardhat @nomicfoundation/hardhat-toolbox ethers"
echo "       npx hardhat init"
echo ""
echo "  4. To start the Quorum quickstart playground:"
echo ""
echo "       npx quorum-dev-quickstart"
echo ""
echo "============================================================"
echo -e "  ${GREEN}Setup complete!${NC}"
echo "============================================================"
