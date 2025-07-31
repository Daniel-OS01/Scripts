#!/bin/bash
# ==============================================================================
# Network Automation: Manage DNS Records (Cloudflare)
# ==============================================================================
#
# Description:
#   This script automates the management of DNS records for a domain hosted
#   on Cloudflare. It can list, create, and delete A, AAAA, and CNAME records,
#   which is essential for provisioning new services and servers automatically.
#
# Usage:
#   ./manage-dns-records.sh <action> [options]
#
# Actions:
#   list                          - List all DNS records for the zone.
#   add <type> <name> <content>   - Add a new DNS record.
#   delete <type> <name>          - Delete an existing DNS record by its name.
#
# Examples:
#   - List all records for the configured domain:
#     ./manage-dns-records.sh list
#
#   - Add an A record for 'new-server.your-domain.com':
#     ./manage-dns-records.sh add A new-server 192.168.1.100
#
#   - Delete the CNAME record for 'www':
#     ./manage-dns-records.sh delete CNAME www
#
# Variables from config.env:
#   - DNS_PROVIDER_API_KEY  (Your Cloudflare API Token)
#   - DNS_ZONE_ID           (The Zone ID of your domain in Cloudflare)
#   - DOMAIN_NAME           (The root domain name, e.g., 'example.com')
#
# Prerequisites:
#   - `curl` and `jq` must be installed.
#
# ==============================================================================

set -e
set -u
set -o pipefail

# --- Configuration ---
# This script assumes that all necessary variables (DNS_PROVIDER_API_KEY, etc.)
# have been exported into the environment by the main.sh orchestrator.

# --- Check Prerequisites ---
if ! command -v curl &> /dev/null || ! command -v jq &> /dev/null; then
    echo "Error: 'curl' and 'jq' are required for this script. Please install them." >&2
    exit 1
fi

# --- Cloudflare API Configuration ---
API_BASE_URL="https://api.cloudflare.com/client/v4"

# --- Functions ---

# Helper function for making authenticated API calls to Cloudflare
# Arg 1: HTTP Method (GET, POST, DELETE)
# Arg 2: API Endpoint Path
# Arg 3: JSON Data Payload (optional, for POST)
cf_api_call() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}" # Default to empty string if not provided

    curl -s -X "$method" "${API_BASE_URL}/zones/${DNS_ZONE_ID}/${endpoint}" \
         -H "Authorization: Bearer ${DNS_PROVIDER_API_KEY}" \
         -H "Content-Type: application/json" \
         --data "$data"
}

# Function to list all DNS records
list_records() {
    echo "Fetching DNS records for zone ${DOMAIN_NAME}..."
    local response
    response=$(cf_api_call "GET" "dns_records")

    if echo "$response" | jq -e '.success' > /dev/null; then
        echo "Displaying records:"
        echo "$response" | jq -r '.result[] | "\(.type | @sh) \(.name | @sh) \(.content | @sh) (ID: \(.id))"' | column -t
    else
        echo "Error fetching records:" >&2
        echo "$response" | jq '.errors' >&2
        return 1
    fi
}

# Function to add a DNS record
add_record() {
    local type="$1" name="$2" content="$3"
    # For root domain records, name can be the same as DOMAIN_NAME
    local full_name
    if [ "$name" == "@" ] || [ "$name" == "$DOMAIN_NAME" ]; then
        full_name="$DOMAIN_NAME"
    else
        full_name="${name}.${DOMAIN_NAME}"
    fi

    echo "Adding ${type} record for ${full_name} -> ${content}..."

    # Construct JSON payload using jq
    local data
    data=$(jq -n --arg type "$type" --arg name "$full_name" --arg content "$content" \
           '{type: $type, name: $name, content: $content, ttl: 120, proxied: false}')

    local response
    response=$(cf_api_call "POST" "dns_records" "$data")

    if echo "$response" | jq -e '.success' > /dev/null; then
        echo "Successfully added DNS record."
    else
        echo "Error adding record:" >&2
        echo "$response" | jq '.errors' >&2
        return 1
    fi
}

# Function to delete a DNS record
delete_record() {
    local type="$1" name="$2"
    local full_name
    if [ "$name" == "@" ] || [ "$name" == "$DOMAIN_NAME" ]; then
        full_name="$DOMAIN_NAME"
    else
        full_name="${name}.${DOMAIN_NAME}"
    fi

    echo "Attempting to delete ${type} record for ${full_name}..."

    # First, find the record ID using the API's filtering
    echo "Finding record ID..."
    local record_id
    record_id=$(cf_api_call "GET" "dns_records?type=${type}&name=${full_name}" | jq -r '.result[0].id')

    if [ -z "$record_id" ] || [ "$record_id" == "null" ]; then
        echo "Error: Could not find a ${type} record with the name ${full_name}." >&2
        return 1
    fi

    echo "Found record with ID: ${record_id}. Proceeding with deletion."
    read -p "Are you sure you want to permanently delete this DNS record? (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then
        echo "Operation cancelled."
        return
    fi

    local response
    response=$(cf_api_call "DELETE" "dns_records/${record_id}")

    if echo "$response" | jq -e '.success' > /dev/null; then
        echo "Successfully deleted record."
    else
        echo "Error deleting record:" >&2
        echo "$response" | jq '.errors' >&2
        return 1
    fi
}

# --- Main Logic ---
ACTION="${1:-}"
if [ -z "$ACTION" ]; then
    echo "Error: No action specified." >&2
    echo "Usage: $0 <list|add|delete> [options]" >&2
    exit 1
fi

case $ACTION in
    list)
        list_records
        ;;
    add)
        if [ "$#" -ne 4 ]; then echo "Usage: $0 add <type> <name> <content>"; exit 1; fi
        add_record "$2" "$3" "$4"
        ;;
    delete)
        if [ "$#" -ne 3 ]; then echo "Usage: $0 delete <type> <name>"; exit 1; fi
        delete_record "$2" "$3"
        ;;
    *)
        echo "Error: Invalid action '$ACTION'." >&2
        exit 1
        ;;
esac
