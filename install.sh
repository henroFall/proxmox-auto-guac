#!/bin/bash

# ============================
#  Proxmox Auto-Guac Installer
# ============================
#  Author: Your Friendly AI
#  Target OS: Debian-based (Debian 12, Ubuntu, etc.)
# ============================

set -e  # Exit on error

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Fancy header
clear
echo -e "${BLUE}====================================="
echo -e "   🚀 Proxmox Auto-Guac Installer 🚀 "
echo -e "=====================================${NC}\n"

# Ensure running as root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[ERROR] This script must be run as root!${NC}\n"
    exit 1
fi

# Install required dependencies
echo -e "${YELLOW}[INFO] Installing dependencies...${NC}"
apt update && apt install -y \
    python3 python3-pip mysql-client openssh-client unattended-upgrades curl jq

# Enable automatic OS updates
echo -e "${YELLOW}[INFO] Enabling automatic OS updates...${NC}"
echo 'APT::Periodic::Update-Package-Lists "1";' > /etc/apt/apt.conf.d/20auto-upgrades
echo 'APT::Periodic::Unattended-Upgrade "1";' >> /etc/apt/apt.conf.d/20auto-upgrades

# Prompt for configuration details
echo -e "${GREEN}[SETUP] Enter connection details:${NC}\n"
read -p "Proxmox API URL: " PROXMOX_API
read -p "Proxmox API User: " PROXMOX_USER
read -s -p "Proxmox API Password: " PROXMOX_PASS

read -p "Ubiquiti SSH Host (leave blank to disable Ubiquiti integration): " UBNT_HOST
if [[ -n "$UBNT_HOST" ]]; then
    read -p "Ubiquiti SSH User: " UBNT_USER
    read -p "Ubiquiti SSH Port [default: 22]: " UBNT_PORT
    UBNT_PORT=${UBNT_PORT:-22}
fi

echo "\nGuacamole Configuration (leave blank to disable Guacamole integration)"
read -p "Guacamole API URL: " GUAC_API
if [[ -n "$GUAC_API" ]]; then
    read -p "Guacamole API User: " GUAC_USER
    read -s -p "Guacamole API Password: " GUAC_PASS
    read -p "Guacamole MySQL Host: " GUAC_DB_HOST
    read -p "Guacamole MySQL Database: " GUAC_DB_NAME
    read -p "Guacamole MySQL User: " GUAC_DB_USER
    read -s -p "Guacamole MySQL Password: " GUAC_DB_PASS
fi

# Save configuration file
echo -e "\n${YELLOW}[INFO] Writing configuration file...${NC}"
CONFIG_PATH="/etc/proxmox-auto-guac/config.ini"
mkdir -p /etc/proxmox-auto-guac
cat <<EOF > $CONFIG_PATH
[proxmox]
api_url = $PROXMOX_API
user = $PROXMOX_USER
password = $PROXMOX_PASS

[ubiquiti]
enabled = ${UBNT_HOST:+true}
host = $UBNT_HOST
user = $UBNT_USER
port = $UBNT_PORT

[guacamole]
enabled = ${GUAC_API:+true}
api_url = $GUAC_API
user = $GUAC_USER
password = $GUAC_PASS
db_host = $GUAC_DB_HOST
db_name = $GUAC_DB_NAME
db_user = $GUAC_DB_USER
db_password = $GUAC_DB_PASS
EOF
chmod 600 $CONFIG_PATH

echo -e "${GREEN}[SUCCESS] Configuration saved to $CONFIG_PATH${NC}\n"

# SSH Key Setup for Ubiquiti
if [[ -n "$UBNT_HOST" ]]; then
    echo -e "${YELLOW}[INFO] Setting up SSH key authentication for Ubiquiti...${NC}"
    if [[ ! -f ~/.ssh/id_rsa.pub ]]; then
        ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
    fi
    echo -e "\n${BLUE}📌 Add the following SSH public key to your Ubiquiti device:${NC}\n"
    cat ~/.ssh/id_rsa.pub
    echo -e "\nThen, run the following command on your Ubiquiti system:\n"
    echo -e "${GREEN}echo \"$(cat ~/.ssh/id_rsa.pub)\" >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys${NC}\n"
    read -p "Press Enter after completing the SSH key setup..."
fi

# Install systemd service
echo -e "${YELLOW}[INFO] Installing systemd service...${NC}"
cat <<EOF > /etc/systemd/system/proxmox-auto-guac.service
[Unit]
Description=Proxmox Auto-Guac Service
After=network.target

[Service]
ExecStart=/usr/bin/python3 /usr/local/bin/proxmox-auto-guac.py
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable proxmox-auto-guac.service
systemctl start proxmox-auto-guac.service

echo -e "${GREEN}[INSTALLATION COMPLETE] The Proxmox Auto-Guac service is now running.${NC}"
