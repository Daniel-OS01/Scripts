#!/bin/bash
# ==============================================================================
# Oracle Cloud: Manage Network Security Group (NSG) Rules
# ==============================================================================
#
# Description:
#   This script adds, removes, or lists rules in a specified OCI Network
#   Security Group. It's a powerful tool for dynamically managing firewall
#   rules for your VPS instances.
#
# Usage:
#   ./manage-nsg-rules.sh <nsg_ocid> <action> [options]
#
# Actions:
#   list                                  List all rules in the NSG.
#   add [options]                         Add a new rule.
#   remove --rule-id <rule_ocid>          Remove an existing rule by its OCID.
#
# Examples:
#   - List rules:
#     ./manage-nsg-rules.sh ocid1.nsg.oc1..xxxxxxxx list
#
#   - Add an SSH rule from a specific IP:
#     ./manage-nsg-rules.sh ocid1.nsg.oc1..xxxxxxxx add --protocol 6 --port 22 --source 1.2.3.4/32
#
#   - Remove a rule by its ID:
#     ./manage-nsg-rules.sh ocid1.nsg.oc1..xxxxxxxx remove --rule-id ocid1.nsgrule.oc1..xxxxx
#
# Variables from config.env:
#   - OCI_REGION
#   - OCI_TENANCY_OCID
#   - OCI_USER_OCID
#   - OCI_KEY_FINGERPRINT
#   - OCI_PRIVATE_KEY_PATH
#
# ==============================================================================

# Exit immediately if a command exits with a non-zero status.
set -e
# Treat unset variables as an error when substituting.
set -u
# Pipelines fail if any command fails, not just the last one.
set -o pipefail

# --- Load Configuration ---
# Source the centralized config file. The `dirname` command ensures the path is
# correct, even if the script is called from a different directory.
if ! source "$(dirname "$0")/../config.env"; then
    echo "Error: Could not load configuration file 'config.env'." >&2
    echo "Please ensure it exists and is readable." >&2
    exit 1
fi

# --- Functions ---

# Function to print usage information
print_usage() {
    echo "Usage: $0 <nsg_ocid> <action> [options]"
    echo "Actions:"
    echo "  list                                  List all rules in the NSG."
    echo "  add [options]                         Add a new rule."
    echo "  remove --rule-id <rule_ocid>          Remove an existing rule by its OCID."
    echo
    echo "Options for 'add':"
    echo "  --direction <INGRESS|EGRESS>          (Default: INGRESS)"
    echo "  --protocol <6|17|1|all>               (6=TCP, 17=UDP, 1=ICMP, Default: 6)"
    echo "  --source <cidr_block>                 (Default: 0.0.0.0/0)"
    echo "  --port <port_number>                  (For TCP/UDP only)"
    echo "  --description <text>                  (Optional description for the rule)"
}

# Function to list NSG rules
list_rules() {
    local nsg_id="$1"
    echo "Fetching rules for NSG: $nsg_id..."
    oci network nsg rules list --nsg-id "$nsg_id" --all --output table
}

# Function to add an NSG rule
add_rule() {
    local nsg_id="$1"; shift
    # Defaults
    local direction="INGRESS"
    local protocol="6" # TCP
    local source="0.0.0.0/0"
    local port_option=""
    local description="Rule added by script on $(date)"

    # Parse named arguments
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --direction) direction="$2"; shift ;;
            --protocol) protocol="$2"; shift ;;
            --source) source="$2"; shift ;;
            --port)
                if [ "$protocol" = "6" ]; then # TCP
                    port_option="--tcp-options '{\"destinationPortRange\": {\"min\": $2, \"max\": $2}}'"
                elif [ "$protocol" = "17" ]; then # UDP
                    port_option="--udp-options '{\"destinationPortRange\": {\"min\": $2, \"max\": $2}}'"
                fi
                shift
                ;;
            --description) description="$2"; shift ;;
            *) echo "Unknown parameter passed: $1"; print_usage; exit 1 ;;
        esac
        shift
    done

    echo "Adding rule to NSG '$nsg_id'..."
    echo "  - Direction: $direction"
    echo "  - Protocol: $protocol"
    echo "  - Source: $source"
    echo "  - Description: $description"

    # Construct the command safely
    local cmd="oci network nsg rules add --nsg-id \"$nsg_id\" --direction \"$direction\" --protocol \"$protocol\" --source \"$source\" --description \"$description\" $port_option"

    echo "Executing command..."
    # Using eval is necessary here to correctly handle the quoted port_option string
    eval "$cmd"
    echo "Rule added successfully."
}

# Function to remove an NSG rule
remove_rule() {
    local nsg_id="$1"; shift
    local rule_id=""

    # Parse named arguments
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --rule-id) rule_id="$2"; shift ;;
            *) echo "Unknown parameter passed: $1"; print_usage; exit 1 ;;
        esac
        shift
    done

    if [ -z "$rule_id" ]; then
        echo "Error: --rule-id is required for the 'remove' action." >&2
        print_usage
        exit 1
    fi

    echo "Preparing to remove rule '$rule_id' from NSG '$nsg_id'..."
    read -p "Are you sure you want to delete this rule permanently? (y/n): " confirm
    if [[ "$confirm" == "y" ]]; then
        oci network nsg rules remove --nsg-id "$nsg_id" --rule-id "$rule_id" --force
        echo "Rule removed."
    else
        echo "Operation cancelled."
    fi
}


# --- Main Logic ---

if [ "$#" -lt 2 ]; then
    print_usage
    exit 1
fi

NSG_OCID="$1"
ACTION="$2"

case $ACTION in
    list)
        list_rules "$NSG_OCID"
        ;;
    add)
        add_rule "$NSG_OCID" "${@:3}"
        ;;
    remove)
        remove_rule "$NSG_OCID" "${@:3}"
        ;;
    *)
        echo "Error: Invalid action '$ACTION'" >&2
        print_usage
        exit 1
        ;;
esac
