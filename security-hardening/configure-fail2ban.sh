#!/bin/bash
# ==============================================================================
# Security Hardening: Install and Configure Fail2Ban
# ==============================================================================
#
# Description:
#   This script automates the installation and basic configuration of Fail2Ban,
#   a crucial tool for preventing brute-force attacks. It enables protection
#   for SSH by default.
#
# Usage:
#   sudo ./configure-fail2ban.sh
#
# Notes:
#   - This script must be run with sudo privileges.
#   - It creates a 'jail.local' file, which is the correct way to override
#     Fail2Ban's default settings.
#
# ==============================================================================

set -e
set -u
set -o pipefail

# --- Check for Sudo ---
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run with sudo privileges." >&2
    exit 1
fi

# --- Main Logic ---

echo "--- Fail2Ban Setup ---"

# 1. Install Fail2Ban if not present
if ! command -v fail2ban-client &> /dev/null; then
    echo "Fail2Ban not found. Attempting to install..."
    if command -v apt-get &> /dev/null; then
        apt-get update -q
        apt-get install -y fail2ban
    elif command -v yum &> /dev/null; then
        yum install -y epel-release
        yum install -y fail2ban
    else
        echo "Error: Could not find supported package manager (apt or yum)." >&2
        exit 1
    fi
    echo "Fail2Ban installed successfully."
else
    echo "Fail2Ban is already installed."
fi

# 2. Create the local configuration file
JAIL_LOCAL_FILE="/etc/fail2ban/jail.local"
echo "Configuring jail.local at: $JAIL_LOCAL_FILE"

if [ -f "$JAIL_LOCAL_FILE" ]; then
    echo "Warning: $JAIL_LOCAL_FILE already exists. A backup will be created."
    cp "$JAIL_LOCAL_FILE" "${JAIL_LOCAL_FILE}.bak_$(date +%F_%T)"
fi

# Create a simple but effective local jail configuration
cat > "$JAIL_LOCAL_FILE" <<EOF
[DEFAULT]
# Ban hosts for 1 hour
bantime = 1h

# An IP is banned if it has generated "maxretry" during the last "findtime"
findtime = 10m
maxretry = 5

# Whitelist local IPs
ignoreip = 127.0.0.1/8 ::1

[sshd]
# SSH jail, which is turned on by default in jail.conf
enabled = true
port = ssh
logpath = %(sshd_log)s
backend = %(sshd_backend)s
EOF

echo "jail.local created with SSH protection enabled."

# 3. Restart and enable the Fail2Ban service
echo "Restarting and enabling the Fail2Ban service..."
systemctl restart fail2ban
systemctl enable fail2ban

# 4. Check status
sleep 2 # Give the service a moment to start
echo "--- Current Fail2Ban Status ---"
fail2ban-client status
echo "--------------------------------"
fail2ban-client status sshd

echo
echo "--- Fail2Ban setup complete. ---"
