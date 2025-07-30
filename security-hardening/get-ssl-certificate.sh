#!/bin/bash
# ==============================================================================
# Security Hardening: Obtain Let's Encrypt SSL Certificate
# ==============================================================================
#
# Description:
#   This script automates the process of obtaining a free SSL certificate from
#   Let's Encrypt using Certbot. It uses the 'standalone' authenticator, which
#   requires port 80 to be free on the machine. The script checks for this
#   condition and provides clear instructions. It also configures the automatic
#   renewal that Certbot provides.
#
# Usage:
#   sudo ./get-ssl-certificate.sh <domain.name>
#
# Example:
#   sudo ./get-ssl-certificate.sh my-app.example.com
#
# Notes:
#   - This script must be run with sudo because Certbot needs root privileges
#     to bind to port 80 and write to the /etc/letsencrypt directory.
#
# Variables from config.env:
#   - LETSENCRYPT_EMAIL  (The email address for registration and recovery notices)
#
# Prerequisites:
#   - `certbot` must be installed. (e.g., `sudo apt install certbot`)
#   - Port 80 must be temporarily available on the machine running this script.
#
# ==============================================================================

set -e
set -u
set -o pipefail

# --- Load Configuration ---
if ! source "$(dirname "$0")/../config.env"; then
    echo "Error: Could not load configuration file 'config.env'." >&2
    exit 1
fi

# --- Check Prerequisites ---
if ! command -v certbot &> /dev/null; then
    echo "Error: 'certbot' command not found." >&2
    echo "Please install it first. On Debian/Ubuntu: 'sudo apt update && sudo apt install certbot'" >&2
    exit 1
fi

# --- Script Parameters ---
if [ "$#" -ne 1 ]; then
    echo "Usage: sudo $0 <domain.name>"
    exit 1
fi

DOMAIN="$1"

# --- Main Logic ---

echo "Starting SSL certificate acquisition for domain: $DOMAIN"
echo "Using registration email from config: $LETSENCRYPT_EMAIL"
echo

# Check if the script is run as root
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run with sudo privileges." >&2
    exit 1
fi

# Check if port 80 is in use by another process
echo "Checking if port 80 is available..."
if lsof -i:80 -sTCP:LISTEN -t >/dev/null ; then
    echo "Error: Port 80 is currently in use by another process." >&2
    echo "The Certbot standalone authenticator requires port 80 to be free." >&2
    echo "Please stop any running web server (e.g., 'sudo systemctl stop nginx') before running this script." >&2
    exit 1
fi
echo "Port 80 is free. Proceeding with Certbot."
echo

read -p "This will request a new certificate for '$DOMAIN'. Continue? (y/n): " confirm
if [[ "$confirm" != "y" ]]; then
    echo "Operation cancelled by user."
    exit 0
fi

echo "Running Certbot..."
# Execute certbot with non-interactive flags
certbot certonly \
    --standalone \
    --non-interactive \
    --agree-tos \
    --email "$LETSENCRYPT_EMAIL" \
    --domain "$DOMAIN"

echo
echo "-----------------------------------------------------------------"
echo "SUCCESS! The SSL certificate has been obtained."
echo
echo "Your certificate and chain have been saved at:"
echo "  /etc/letsencrypt/live/$DOMAIN/fullchain.pem"
echo
echo "Your private key has been saved at:"
echo "  /etc/letsencrypt/live/$DOMAIN/privkey.pem"
echo
echo "Certbot has also configured automatic renewal, which will run periodically."
echo "You can test the renewal process with: 'sudo certbot renew --dry-run'"
echo "-----------------------------------------------------------------"
