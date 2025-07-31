#!/bin/bash
# ==============================================================================
# Network Automation: Check SSL Certificate Expiration
# ==============================================================================
#
# Description:
#   This script checks the expiration date of the SSL certificate for a given
#   domain. It can be used for monitoring to ensure certificates are renewed
#   on time. It can optionally send a warning alert if the certificate is
#   expiring within a specified number of days.
#
# Usage:
#   ./check-ssl-expiry.sh <domain.name> [--warn-days <days>]
#
# Example:
#   - Check the expiry date for a domain:
#     ./check-ssl-expiry.sh example.com
#
#   - Check and send a CRITICAL alert if expiring in the next 14 days:
#     ./check-ssl-expiry.sh example.com --warn-days 14
#
# Prerequisites:
#   - `openssl` must be installed.
#
# ==============================================================================

set -e
set -u
set -o pipefail

# --- Script Parameters ---
if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <domain.name> [--warn-days <days>]" >&2
    exit 1
fi

DOMAIN="$1"
shift
WARN_DAYS=""

# Argument Parsing
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --warn-days) WARN_DAYS="$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

# --- Main Logic ---

echo "Checking SSL certificate for domain: $DOMAIN"

# Get the certificate's expiration date using openssl
# The 's_client' connects, and the 'x509' command parses the output.
# We use </dev/null to prevent s_client from waiting for input.
EXPIRY_DATE_STR=$(openssl s_client -servername "$DOMAIN" -connect "$DOMAIN:443" </dev/null 2>/dev/null |
                  openssl x509 -noout -enddate |
                  cut -d= -f2)

if [ -z "$EXPIRY_DATE_STR" ]; then
    echo "Error: Could not retrieve SSL certificate for '$DOMAIN'. Check the domain name and connectivity." >&2
    # Optionally send a failure alert
    if [ -f "$(dirname "$0")/../monitoring-alerts/send-alert.sh" ]; then
        bash "$(dirname "$0")/../monitoring-alerts/send-alert.sh" \
            --title "SSL Check FAILED" \
            --message "Could not retrieve SSL certificate for domain: $DOMAIN" \
            --level "CRITICAL"
    fi
    exit 1
fi

echo "Certificate expires on: $EXPIRY_DATE_STR"

# Convert the expiration date to seconds since epoch
EXPIRY_DATE_EPOCH=$(date -d "$EXPIRY_DATE_STR" +%s)
CURRENT_DATE_EPOCH=$(date +%s)

# Calculate days remaining
SECONDS_REMAINING=$((EXPIRY_DATE_EPOCH - CURRENT_DATE_EPOCH))
DAYS_REMAINING=$((SECONDS_REMAINING / 86400))

echo "Days remaining: $DAYS_REMAINING"

# Send a warning if within the threshold
if [ -n "$WARN_DAYS" ]; then
    if [ "$DAYS_REMAINING" -le "$WARN_DAYS" ]; then
        echo "WARNING: Certificate is expiring in $DAYS_REMAINING days, which is within the $WARN_DAYS day threshold."
        ALERT_SCRIPT_PATH="$(dirname "$0")/../monitoring-alerts/send-alert.sh"
        if [ -f "$ALERT_SCRIPT_PATH" ]; then
            echo "Sending expiration warning alert..."
            bash "$ALERT_SCRIPT_PATH" \
                --title "SSL Certificate Expiration WARNING" \
                --message "The SSL certificate for '$DOMAIN' expires in $DAYS_REMAINING days (on $EXPIRY_DATE_STR)." \
                --level "WARNING"
        else
            echo "Warning: 'send-alert.sh' not found. Cannot send alert." >&2
        fi
    else
        echo "Certificate expiration is outside the warning threshold."
    fi
fi

echo "SSL check complete."
