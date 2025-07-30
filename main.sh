#!/bin/bash
# ==============================================================================
#                 Main Automation Script Orchestrator
# ==============================================================================
#
# Description:
#   This script provides a centralized, menu-driven interface to access and
#   run all the automation scripts in this repository. It sources the main
#   config file and provides a user-friendly way to execute complex tasks.
#
# Usage:
#   ./main.sh
#
# ==============================================================================

set -e
set -u
set -o pipefail

# --- Load Configuration ---
# Source the config file to make all variables available to this script
# and any sub-scripts it calls.
CONFIG_PATH="$(dirname "$0")/config.env"
if ! source "$CONFIG_PATH"; then
    echo "Error: Could not load configuration file '$CONFIG_PATH'." >&2
    echo "Please ensure it exists and is correctly configured." >&2
    exit 1
fi

# --- Style Definitions ---
readonly COLOR_BLUE='\033[1;34m'
readonly COLOR_GREEN='\033[1;32m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_RED='\033[1;31m'
readonly COLOR_RESET='\033[0m'

# --- Functions ---

# Function to display the main menu
show_menu() {
    clear
    echo -e "${COLOR_BLUE}========================================${COLOR_RESET}"
    echo -e "      ${COLOR_GREEN}Automation Script Orchestrator${COLOR_RESET}"
    echo -e "${COLOR_BLUE}========================================${COLOR_RESET}"
    echo
    echo -e "  ${COLOR_YELLOW}Oracle Cloud${COLOR_RESET}"
    echo "    [1] Manage NSG Rules"
    echo "    [2] Manage Block Volumes"
    echo
    echo -e "  ${COLOR_YELLOW}Docker Advanced${COLOR_RESET}"
    echo "    [3] Selective Resource Cleanup"
    echo "    [4] Inspect Resource Usage"
    echo
    echo -e "  ${COLOR_YELLOW}Coolify Management${COLOR_RESET}"
    echo "    [5] Manage Application State"
    echo
    echo -e "  ${COLOR_YELLOW}Network Automation${COLOR_RESET}"
    echo "    [6] Manage DNS Records (Cloudflare)"
    echo
    echo -e "  ${COLOR_YELLOW}Security & Hardening${COLOR_RESET}"
    echo "    [7] Get Let's Encrypt SSL Certificate"
    echo
    echo -e "  ${COLOR_YELLOW}Backup & Recovery${COLOR_RESET}"
    echo "    [8] Perform Encrypted S3 Backup"
    echo
    echo -e "  ${COLOR_YELLOW}Monitoring & Alerting${COLOR_RESET}"
    echo "    [9] Send a Custom Alert"
    echo
    echo -e "  ${COLOR_YELLOW}Maintenance & Optimization${COLOR_RESET}"
    echo "    [10] Run System Update & Health Check"
    echo
    echo "  --------------------------------------"
    echo -e "  [0] ${COLOR_RED}Exit${COLOR_RESET}"
    echo -e "${COLOR_BLUE}========================================${COLOR_RESET}"
}

# Function to execute a script
# Arg 1: Script Path, Args 2+: Arguments for the script
run_script() {
    local script_path="$1"
    shift

    local script_dir
    script_dir=$(dirname "$0")
    local full_script_path="${script_dir}/${script_path}"

    echo -e "${COLOR_GREEN}Executing: ${full_script_path} $@ ${COLOR_RESET}"
    echo "------------------------------------------------------------"

    # Ensure the script is executable
    if [ ! -x "$full_script_path" ]; then
        echo "Warning: Script not executable. Adding execute permission."
        chmod +x "$full_script_path"
    fi

    # Execute the script, passing all remaining arguments to it
    # We use `bash` to ensure consistent execution environment
    bash "$full_script_path" "$@"

    echo "------------------------------------------------------------"
    echo -e "${COLOR_GREEN}Execution finished.${COLOR_RESET}"
}


# --- Main Loop ---
while true; do
    show_menu
    read -p "Enter your choice [0-10]: " choice

    # Default to empty args
    args=()
    # For choices that need arguments, prompt the user
    if [[ "$choice" -ge 1 && "$choice" -le 8 ]] || [[ "$choice" -eq 10 ]]; then
        echo "Enter all arguments for the script on one line (e.g., list --all), or press Enter for none:"
        # Use read -r to handle backslashes correctly
        read -r -a args
    fi

    case $choice in
        1) run_script "oracle-cloud/manage-nsg-rules.sh" "${args[@]}" ;;
        2) run_script "oracle-cloud/manage-block-volumes.sh" "${args[@]}" ;;
        3) run_script "docker-advanced/selective-cleanup.sh" "${args[@]}" ;;
        4) run_script "docker-advanced/inspect-resource-usage.sh" "${args[@]}" ;;
        5) run_script "coolify-management/manage-application.sh" "${args[@]}" ;;
        6) run_script "network-automation/manage-dns-records.sh" "${args[@]}" ;;
        7) run_script "security-hardening/get-ssl-certificate.sh" "${args[@]}" ;;
        8) run_script "backup-recovery/perform-s3-backup.sh" "${args[@]}" ;;
        9)
            # Special interactive handling for the alert script to make it more user-friendly
            echo "Enter alert title:"
            read -r title
            echo "Enter alert message:"
            read -r message
            echo "Enter alert level (INFO, WARNING, CRITICAL):"
            read -r level
            run_script "monitoring-alerts/send-alert.sh" --title "$title" --message "$message" --level "$level"
            ;;
        10) run_script "maintenance-optimization/system-update-and-health-check.sh" "${args[@]}" ;;
        0)
            echo "Exiting orchestrator."
            break
            ;;
        *)
            echo -e "\n${COLOR_RED}Invalid option '$choice'. Please try again.${COLOR_RESET}"
            ;;
    esac

    echo
    read -p "Press [Enter] to return to the menu..."
done
