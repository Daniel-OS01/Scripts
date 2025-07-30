#!/bin/bash
# ==============================================================================
# Coolify Management: Manage Application State
# ==============================================================================
#
# Description:
#   This script interacts with the Coolify API to manage the state of a
#   specific application. It can be used to trigger restarts, redeployments,
#   or fetch the current deployment status, which is useful for automation
#   and integration with CI/CD pipelines.
#
# Usage:
#   ./manage-application.sh <application_uuid> <action>
#
# Actions:
#   status        - Get the current status of the application.
#   restart       - Trigger a restart of the application.
#   redeploy      - Trigger a fresh deployment (rebuilds and redeploys).
#
# Examples:
#   - Get application status:
#     ./manage-application.sh a1b2c3d4-e5f6-7890-gh12-ijklmnopqrst status
#
#   - Restart the application:
#     ./manage-application.sh a1b2c3d4-e5f6-7890-gh12-ijklmnopqrst restart
#
# Variables from config.env:
#   - COOLIFY_API_ENDPOINT
#   - COOLIFY_API_KEY
#
# Prerequisites:
#   - `curl` must be installed for API communication.
#   - `jq` is highly recommended for parsing and displaying the JSON responses neatly.
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
if ! command -v curl &> /dev/null; then
    echo "Error: 'curl' is not installed. Please install it to use this script." >&2
    exit 1
fi

# --- Script Parameters ---
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <application_uuid> <action>"
    echo "Valid actions: status, restart, redeploy"
    exit 1
fi

APP_UUID="$1"
ACTION="$2"
# Ensure the API endpoint does not have a trailing slash
API_BASE_URL="${COOLIFY_API_ENDPOINT%/}/api/v1"

# --- Functions ---

# Helper function for making authenticated API calls to Coolify
# Takes two arguments: the HTTP method and the API endpoint path
api_call() {
    local method="$1"
    local endpoint="$2"
    local response

    echo "Executing ${method} request to ${API_BASE_URL}${endpoint}..."

    response=$(curl -s -w "%{http_code}" -X "$method" "${API_BASE_URL}${endpoint}" \
         -H "Authorization: Bearer ${COOLIFY_API_KEY}" \
         -H "Content-Type: application/json")

    local http_code="${response: -3}"
    local body="${response:0:${#response}-3}"

    if [ "$http_code" -ge 400 ]; then
        echo "Error: API call failed with status code $http_code." >&2
        echo "Response: $body" >&2
        return 1
    fi

    echo "$body"
}

# Get application status
get_status() {
    echo "Fetching status for application: $APP_UUID"
    local response
    response=$(api_call "GET" "/applications/${APP_UUID}")

    if command -v jq &> /dev/null; then
        echo "Application Status:"
        echo "$response" | jq '.application | {name, fqdn, status, build_pack}'
    else
        echo "Warning: 'jq' not found. Displaying raw JSON response."
        echo "$response"
    fi
}

# Restart an application
restart_app() {
    echo "Sending RESTART command to application: $APP_UUID"
    api_call "POST" "/applications/${APP_UUID}/restart" > /dev/null
    echo "Restart command issued successfully."
}

# Redeploy an application
redeploy_app() {
    echo "Sending REDEPLOY command to application: $APP_UUID"
    read -p "This will trigger a fresh build and deployment. This cannot be undone. Are you sure? (y/n): " confirm
    if [[ "$confirm" == "y" ]]; then
        api_call "POST" "/applications/${APP_UUID}/deployments" > /dev/null
        echo "Redeployment triggered successfully. Check the Coolify UI for progress."
    else
        echo "Operation cancelled."
    fi
}

# --- Main Logic ---

case $ACTION in
    status)
        get_status
        ;;
    restart)
        restart_app
        ;;
    redeploy)
        redeploy_app
        ;;
    *)
        echo "Error: Invalid action '$ACTION'." >&2
        echo "Valid actions are: status, restart, redeploy"
        exit 1
        ;;
esac
