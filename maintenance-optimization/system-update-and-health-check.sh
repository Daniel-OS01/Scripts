#!/bin/bash
# ==============================================================================
# Maintenance & Optimization: System Update and Health Check
# ==============================================================================
#
# Description:
#   This script performs routine system maintenance tasks. It is designed to be
#   run non-interactively, making it ideal for automation via cron.
#   1. Detects the system's package manager (APT for Debian/Ubuntu, YUM for RHEL/CentOS).
#   2. Updates all system packages to their latest versions.
#   3. Cleans up unused packages, dependencies, and cached files.
#   4. Gathers a concise system health report (disk, memory, CPU load).
#   5. Sends this health report as a notification using the 'send-alert.sh' script.
#
# Usage:
#   sudo ./system-update-and-health-check.sh
#
# Notes:
#   - This script must be run with sudo to perform package management.
#
# Variables from config.env:
#   - None directly, but it calls 'send-alert.sh' which uses NOTIFICATION_WEBHOOK_URL.
#
# Prerequisites:
#   - `send-alert.sh` must be present in the `monitoring-alerts` directory.
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

# --- Check for Sudo ---
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run with sudo privileges to manage system packages." >&2
    exit 1
fi

# --- Functions ---

update_system_apt() {
    echo "Updating system using APT..."
    # Ensure non-interactive frontend to prevent prompts
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -q
    apt-get upgrade -y -q
    apt-get autoremove -y -q
    apt-get clean
}

update_system_yum() {
    echo "Updating system using YUM..."
    yum update -y
    yum autoremove -y
    yum clean all
}

gather_health_report() {
    echo "Gathering system health report..."
    # Use 'tr' to replace spaces with underscores for better formatting in backticks
    DISK_USAGE=$(df -h / | tail -n 1 | awk '{print "Total: " $2 ", Used: " $3 " (" $5 ")" }')
    MEM_USAGE=$(free -h | grep Mem | awk '{print "Total: " $2 ", Used: " $3 " (" sprintf("%.2f%%", $3/$2 * 100) ")" }')
    LOAD_AVG=$(uptime | awk -F'load average: ' '{print $2}')

    HEALTH_REPORT="**Disk Usage (Root):** \`$DISK_USAGE\`
**Memory Usage:** \`$MEM_USAGE\`
**Load Average:** \`$LOAD_AVG\`"
}


# --- Main Logic ---

echo "Starting system maintenance script..."
echo "-------------------------------------"

# 1. Detect package manager and update system
if command -v apt-get &> /dev/null; then
    update_system_apt
elif command -v yum &> /dev/null; then
    update_system_yum
else
    echo "Error: Could not find a supported package manager (apt or yum)." >&2
    # Call the alert script to notify of this failure
    bash "$(dirname "$0")/../monitoring-alerts/send-alert.sh" \
        --title "Maintenance Script FAILED on $(hostname)" \
        --message "Could not find a supported package manager (apt or yum)." \
        --level "CRITICAL"
    exit 1
fi
echo "System update and cleanup complete."
echo

# 2. Gather health report
gather_health_report
echo "System health report generated."
echo

# 3. Send notification
ALERT_SCRIPT_PATH="$(dirname "$0")/../monitoring-alerts/send-alert.sh"
if [ -f "$ALERT_SCRIPT_PATH" ]; then
    echo "Sending health report via notification webhook..."
    bash "$ALERT_SCRIPT_PATH" \
        --title "System Maintenance & Health Report for $(hostname)" \
        --message "$HEALTH_REPORT" \
        --level "INFO"
    echo "Report sent."
else
    echo "Warning: 'send-alert.sh' not found. Skipping notification." >&2
    echo "--- Health Report ---"
    echo -e "$HEALTH_REPORT"
    echo "---------------------"
fi

echo
echo "--- System maintenance script finished successfully. ---"
