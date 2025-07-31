#!/bin/bash
# ==============================================================================
# Oracle Cloud: Manage Compute Instance State
# ==============================================================================
#
# Description:
#   This script provides a simple interface to manage the power state of an
#   OCI compute instance. It can be used to start, stop, reboot, or get the
#   current status of a specific virtual machine.
#
# Usage:
#   ./manage-instance-state.sh <instance_ocid> <action>
#
# Actions:
#   start         - Powers on the instance.
#   stop          - Powers off the instance (graceful shutdown).
#   reboot        - Reboots the instance.
#   status        - Gets the current lifecycle state of the instance.
#
# Variables from config.env:
#   - All OCI_* variables for authentication.
#
# Prerequisites:
#   - `oci-cli` must be installed.
#
# ==============================================================================

set -e
set -u
set -o pipefail

# --- Configuration ---
# This script assumes that all necessary OCI_* variables have been exported
# into the environment by the main.sh orchestrator.

# --- Script Parameters ---
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <instance_ocid> <start|stop|reboot|status>" >&2
    exit 1
fi

INSTANCE_ID="$1"
ACTION="$2"

# --- Main Logic ---

echo "Attempting to perform action '${ACTION}' on instance: ${INSTANCE_ID}"

case $ACTION in
    start)
        read -p "Are you sure you want to START this instance? (y/n): " confirm
        if [[ "$confirm" == "y" ]]; then
            oci compute instance action --instance-id "$INSTANCE_ID" --action START --wait-for-state RUNNING
            echo "Instance started successfully."
        else
            echo "Operation cancelled."
        fi
        ;;
    stop)
        read -p "WARNING: This will shut down the instance. Are you sure? (y/n): " confirm
        if [[ "$confirm" == "y" ]]; then
            oci compute instance action --instance-id "$INSTANCE_ID" --action STOP --wait-for-state STOPPED
            echo "Instance stopped successfully."
        else
            echo "Operation cancelled."
        fi
        ;;
    reboot)
        read -p "WARNING: This will reboot the instance. Are you sure? (y/n): " confirm
        if [[ "$confirm" == "y" ]]; then
            oci compute instance action --instance-id "$INSTANCE_ID" --action RESET --wait-for-state RUNNING
            echo "Instance rebooted successfully."
        else
            echo "Operation cancelled."
        fi
        ;;
    status)
        echo "Fetching instance status..."
        oci compute instance get --instance-id "$INSTANCE_ID" --query 'data."lifecycle-state"' --raw-output
        ;;
    *)
        echo "Error: Invalid action '$ACTION'." >&2
        echo "Valid actions are: start, stop, reboot, status"
        exit 1
        ;;
esac
