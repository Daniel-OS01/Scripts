#!/bin/bash

# ==============================================================================
#
#               Centralized Script Distribution System Orchestrator
#
#   Author: Daniel-OS01 (and Jules, the AI assistant)
#   Repository: https://github.com/Daniel-OS01/scripts
#
#   Description:
#   This script acts as a menu-driven interface to a collection of complex
#   automation scripts for Oracle Cloud, Docker, and Coolify management.
#   It securely fetches scripts from a GitHub repository and uses a template
#   system to inject secrets from environment variables at runtime.
#
#   Execution Method:
#   sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/Daniel-OS01/scripts/refs/heads/main/main.sh)"
#
# ==============================================================================

# --- Configuration ---
# The base URL of the GitHub repository where the scripts are hosted.
# This ensures that all script fetching is centralized and easy to update.
readonly GITHUB_BASE_URL="https://raw.githubusercontent.com/Daniel-OS01/scripts/refs/heads/main"

# --- Style Definitions (for fancy output) ---
readonly COLOR_BLUE='\033[1;34m'
readonly COLOR_GREEN='\033[1;32m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_RED='\033[1;31m'
readonly COLOR_RESET='\033[0m'

# --- Bootstrap ---
# Dynamically fetches and sources the core secrets-handling library from the repo.
# This allows the main script to use the `process_script` function without
# needing the library to be present on the host machine beforehand.
echo -e "${COLOR_BLUE}Initializing orchestrator...${COLOR_RESET}"
SECRETS_LIB_URL="$GITHUB_BASE_URL/scripts/lib/secrets.sh"
source <(curl -fsSL "$SECRETS_LIB_URL") || { echo -e "${COLOR_RED}Fatal: Could not load the secrets library. Aborting.${COLOR_RESET}"; exit 1; }
echo -e "${COLOR_GREEN}Initialization complete.${COLOR_RESET}"


# --- Core Functions ---

# Function: show_menu()
# Description: Displays the main menu of available script categories.
show_menu() {
    echo -e "${COLOR_BLUE}========================================${COLOR_RESET}"
    echo -e "      ${COLOR_GREEN}Automation Script Orchestrator${COLOR_RESET}"
    echo -e "${COLOR_BLUE}========================================${COLOR_RESET}"
    echo "Please select a script to run:"
    echo
    echo -e "  ${COLOR_YELLOW}Oracle Cloud${COLOR_RESET}"
    echo "    [1] Configure Network Security"
    echo
    echo -e "  ${COLOR_YELLOW}Docker Management${COLOR_RESET}"
    echo "    [2] Advanced Container Management"
    echo
    echo -e "  ${COLOR_YELLOW}Coolify Platform${COLOR_RESET}"
    echo "    [3] Trigger Application Deployment"
    echo
    echo "  --------------------------------------"
    echo -e "  [0] ${COLOR_RED}Exit${COLOR_RESET}"
    echo -e "${COLOR_BLUE}========================================${COLOR_RESET}"
}

# Function: run_script()
# Description:
#   Handles the entire lifecycle of running a remote script: confirmation,
#   fetching, secret processing, and execution.
# Arguments:
#   $1 - The relative path of the script in the GitHub repository.
run_script() {
    local script_path="$1"
    local script_url="$GITHUB_BASE_URL/$script_path"

    echo # Newline for readability
    read -p "$(echo -e ${COLOR_YELLOW}"You are about to run '${script_path}'. Are you sure? (y/n): "${COLOR_RESET})" confirm
    if [[ "${confirm}" != "y" ]]; then
        echo -e "${COLOR_RED}Operation cancelled by user.${COLOR_RESET}"
        return
    fi

    echo -e "\n${COLOR_BLUE}Fetching script...${COLOR_RESET}"
    local script_content
    script_content=$(curl -fsSL "$script_url")
    if [[ $? -ne 0 ]]; then
        echo -e "${COLOR_RED}Error: Failed to fetch script from '$script_url'.\nPlease check the repository path or your network connection.${COLOR_RESET}" >&2
        return
    fi

    echo -e "${COLOR_BLUE}Processing script and validating required secrets...${COLOR_RESET}"
    local processed_script
    processed_script=$(process_script "$script_content")
    if [[ $? -ne 0 ]]; then
        # The process_script function already printed a specific error to stderr.
        echo -e "${COLOR_RED}Halting execution due to missing secrets. Please set the required environment variables.${COLOR_RESET}" >&2
        return
    fi

    echo -e "${COLOR_GREEN}Execution starting now...${COLOR_RESET}"
    echo "------------------------------------------------------------"
    # Execute the processed script in a subshell for safety.
    bash -c "$processed_script"
    echo "------------------------------------------------------------"
    echo -e "${COLOR_GREEN}Script execution finished.${COLOR_RESET}"
}


# --- Main Execution Loop ---
# The main loop of the script. It shows the menu, waits for user input,
# and calls the appropriate functions.
while true; do
    show_menu
    read -p "$(echo -e ${COLOR_GREEN}"Enter your choice [0-3]: "${COLOR_RESET})" choice

    case $choice in
        1)
            run_script "scripts/oracle/configure-network.sh"
            ;;
        2)
            run_script "scripts/docker/advanced-container-management.sh"
            ;;
        3)
            run_script "scripts/coolify/deployment.sh"
            ;;
        0)
            echo -e "\n${COLOR_YELLOW}Exiting orchestrator. Goodbye!${COLOR_RESET}"
            break
            ;;
        *)
            echo -e "\n${COLOR_RED}Invalid option '$choice'. Please select a valid number from the menu.${COLOR_RESET}"
            ;;
    esac

    echo
    read -p "Press [Enter] to return to the menu..."
done
