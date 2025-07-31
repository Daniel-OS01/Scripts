#!/bin/bash
# ==============================================================================
#                 Remote Script Injector Orchestrator
# ==============================================================================
#
# Description:
#   This script provides a menu to run a suite of automation scripts remotely.
#   It fetches a central configuration file and the chosen script from a
#   private GitHub repository, injects the configuration into the script at
#   runtime, and then executes it. This allows for centralized management
#   of both scripts and configuration.
#
# Usage:
#   sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/Daniel-OS01/Scripts/refs/heads/main/main.sh)"
#
# ==============================================================================

set -e
set -u
set -o pipefail

# --- Configuration ---
# The base URL of the GitHub repository where the scripts are hosted.
readonly GITHUB_BASE_URL="https://raw.githubusercontent.com/Daniel-OS01/Scripts/refs/heads/main"

# --- Style Definitions ---
readonly COLOR_BLUE='\033[1;34m'
readonly COLOR_GREEN='\033[1;32m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_RED='\033[1;31m'
readonly COLOR_RESET='\033[0m'

# --- Bootstrap ---
echo -e "${COLOR_BLUE}Initializing orchestrator and fetching remote configuration...${COLOR_RESET}"
CONFIG_CONTENT=$(curl -fsSL "${GITHUB_BASE_URL}/config.env")
if [ -z "$CONFIG_CONTENT" ]; then
    echo -e "${COLOR_RED}Fatal: Could not fetch 'config.env' from the repository. Aborting.${COLOR_RESET}" >&2
    echo -e "${COLOR_RED}Please ensure the repository is correct and you have access.${COLOR_RESET}" >&2
    exit 1
fi
echo -e "${COLOR_GREEN}Configuration loaded successfully.${COLOR_RESET}"


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
    echo "    [3] Add Port (iptables & OCI)"
    echo "    [4] OCI Manager v2 (Interactive)"
    echo "    [5] OCI Manager v2.5 (Interactive)"
    echo "    [6] Dokploy/Traefik Doctor"
    echo "    [7] Manage Instance State (Start/Stop/Reboot)"
    echo "    [8] VPS Comprehensive Diagnostics"
    echo
    echo -e "  ${COLOR_YELLOW}Docker Advanced${COLOR_RESET}"
    echo "    [9] Selective Resource Cleanup"
    echo "    [10] Inspect Resource Usage"
    echo "    [11] Image Vulnerability Scan (Trivy)"
    echo "    [12] Docker Cleanup & Management (Menu)"
    echo "    [13] Simple Docker Cleanup"
    echo
    echo -e "  ${COLOR_YELLOW}Coolify Management${COLOR_RESET}"
    echo "    [14] Manage Application State"
    echo
    echo -e "  ${COLOR_YELLOW}Network Automation${COLOR_RESET}"
    echo "    [15] Manage DNS Records (Cloudflare)"
    echo "    [16] Check SSL Certificate Expiry"
    echo
    echo -e "  ${COLOR_YELLOW}Security & Hardening${COLOR_RESET}"
    echo "    [17] Get Let's Encrypt SSL Certificate"
    echo "    [18] Install & Configure Fail2Ban"
    echo
    echo -e "  ${COLOR_YELLOW}Backup & Recovery${COLOR_RESET}"
    echo "    [19] Perform Encrypted S3 Backup"
    echo
    echo -e "  ${COLOR_YELLOW}Monitoring & Alerting${COLOR_RESET}"
    echo "    [20] Send a Custom Alert (Interactive)"
    echo
    echo -e "  ${COLOR_YELLOW}Maintenance & Optimization${COLOR_RESET}"
    echo "    [21] Run System Update & Health Check"
    echo "    [22] Shared Hosting Diagnostics"
    echo
    echo "  --------------------------------------"
    echo -e "  [0] ${COLOR_RED}Exit${COLOR_RESET}"
    echo -e "${COLOR_BLUE}========================================${COLOR_RESET}"
}

# Function to execute a remote script with injected config
# Arg 1: The relative path to the script in the repository
# Args 2+: Arguments to pass to the target script
run_script() {
    local script_path="$1"
    shift
    local script_url="${GITHUB_BASE_URL}/${script_path}"

    echo -e "\n${COLOR_BLUE}Fetching remote script: ${script_path}...${COLOR_RESET}"
    local script_content
    script_content=$(curl -fsSL "$script_url")
    if [ -z "$script_content" ]; then
        echo -e "${COLOR_RED}Error: Failed to fetch script from '$script_url'.${COLOR_RESET}" >&2
        return
    fi

    # Combine the config and the script content. The config is sourced first.
    local combined_script
    combined_script="${CONFIG_CONTENT}
${script_content}"

    echo -e "${COLOR_GREEN}Executing script with injected configuration...${COLOR_RESET}"
    echo "------------------------------------------------------------"
    # Execute the combined script in a subshell, passing along any arguments.
    # The '--' is important to separate arguments for 'bash' from arguments for the script.
    bash -c "$combined_script" -- "$@"
    echo "------------------------------------------------------------"
    echo -e "${COLOR_GREEN}Execution finished.${COLOR_RESET}"
}


# --- Main Loop ---
while true; do
    show_menu
    read -p "Enter your choice [0-22]: " choice

    args=()
    # For choices that need arguments, prompt the user, except for the interactive ones.
    if [[ "$choice" -ge 1 && "$choice" -le 22 && "$choice" -ne 20 ]]; then
        echo "Enter all arguments for the script on one line (e.g., list --all), or press Enter for none:"
        read -r -a args
    fi

    case $choice in
        1) run_script "oracle-cloud/manage-nsg-rules.sh" "${args[@]}" ;;
        2) run_script "oracle-cloud/manage-block-volumes.sh" "${args[@]}" ;;
        3) run_script "oracle-cloud/oci-add-port.sh" "${args[@]}" ;;
        4) run_script "oracle-cloud/oci-manager2.sh" "${args[@]}" ;;
        5) run_script "oracle-cloud/oci-manager2.5.sh" "${args[@]}" ;;
        6) run_script "oracle-cloud/dokploy-traefik-doctor.sh" "${args[@]}" ;;
        7) run_script "oracle-cloud/manage-instance-state.sh" "${args[@]}" ;;
        8) run_script "oracle/VPS Comprehensive Diagnostics – ARM64 Ubuntu.sh" "${args[@]}" ;;
        9) run_script "docker-advanced/selective-cleanup.sh" "${args[@]}" ;;
        10) run_script "docker-advanced/inspect-resource-usage.sh" "${args[@]}" ;;
        11) run_script "docker-advanced/image-vulnerability-scan.sh" "${args[@]}" ;;
        12) run_script "docker-advanced/Docker-Cleanup-Management.sh" "${args[@]}" ;;
        13) run_script "docker-advanced/cleanup.sh" "${args[@]}" ;;
        14) run_script "coolify-management/manage-application.sh" "${args[@]}" ;;
        15) run_script "network-automation/manage-dns-records.sh" "${args[@]}" ;;
        16) run_script "network-automation/check-ssl-expiry.sh" "${args[@]}" ;;
        17) run_script "security-hardening/get-ssl-certificate.sh" "${args[@]}" ;;
        18) run_script "security-hardening/configure-fail2ban.sh" "${args[@]}" ;;
        19) run_script "backup-recovery/perform-s3-backup.sh" "${args[@]}" ;;
        20)
            echo "Enter alert title:"
            read -r title
            echo "Enter alert message:"
            read -r message
            echo "Enter alert level (INFO, WARNING, CRITICAL):"
            read -r level
            run_script "monitoring-alerts/send-alert.sh" --title "$title" --message "$message" --level "$level"
            ;;
        21) run_script "maintenance-optimization/system-update-and-health-check.sh" "${args[@]}" ;;
        22) run_script "maintenance-optimization/shared-hosting-diagnostics.sh" "${args[@]}" ;;
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
