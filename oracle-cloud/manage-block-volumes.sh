#!/bin/bash
# ==============================================================================
# Oracle Cloud: Manage Block Volumes
# ==============================================================================
#
# Description:
#   This script provides a command-line interface to manage the lifecycle of
#   OCI Block Volumes, including creation, attachment to an instance,
#   detachment, and deletion. This is crucial for managing persistent storage
#   for virtual machines.
#
# Usage:
#   ./manage-block-volumes.sh <action> [options]
#
# Actions & Options:
#   list
#       List all block volumes in the compartment.
#
#   create --name <display_name> --size <gigabytes>
#       Create a new block volume.
#
#   attach --volume-id <volume_ocid> --instance-id <instance_ocid>
#       Attach a volume to a compute instance.
#
#   detach --attachment-id <attachment_ocid>
#       Detach a volume from its instance using the attachment OCID.
#
#   delete --volume-id <volume_ocid>
#       Permanently delete a block volume.
#
# Variables from config.env:
#   - OCI_DEFAULT_COMPARTMENT_OCID
#   - OCI_TENANCY_OCID (used to find a valid Availability Domain)
#   - Other OCI credentials for authentication.
#
# Prerequisites:
#   - `oci-cli` and `jq` must be installed.
#
# ==============================================================================

set -e
set -u
set -o pipefail

# --- Configuration ---
# This script assumes that all necessary OCI_* variables have been exported
# into the environment by the main.sh orchestrator.

# --- Check Prerequisites ---
if ! command -v oci &> /dev/null || ! command -v jq &> /dev/null; then
    echo "Error: 'oci-cli' and 'jq' are required. Please install them." >&2
    exit 1
fi

# --- Functions ---

print_usage() {
    echo "Usage: $0 <action> [options]"
    echo "Actions & Options:"
    echo "  list"
    echo "  create --name <display_name> --size <gigabytes>"
    echo "  attach --volume-id <volume_ocid> --instance-id <instance_ocid>"
    echo "  detach --attachment-id <attachment_ocid>"
    echo "  delete --volume-id <volume_ocid>"
}

# --- Main Logic ---
ACTION="${1:-}"
shift || true # Shift even if there are no arguments, do not error

# Parse named arguments into variables
# Initialize variables to prevent unbound variable errors with `set -u`
DISPLAY_NAME=""
SIZE_IN_GBS=""
VOLUME_ID=""
INSTANCE_ID=""
ATTACHMENT_ID=""

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --name)          DISPLAY_NAME="$2"; shift ;;
        --size)          SIZE_IN_GBS="$2"; shift ;;
        --volume-id)     VOLUME_ID="$2"; shift ;;
        --instance-id)   INSTANCE_ID="$2"; shift ;;
        --attachment-id) ATTACHMENT_ID="$2"; shift ;;
        *) echo "Unknown parameter: $1"; print_usage; exit 1 ;;
    esac
    shift
done

case $ACTION in
    list)
        echo "Listing block volumes in compartment $OCI_DEFAULT_COMPARTMENT_OCID..."
        oci bv volume list --compartment-id "$OCI_DEFAULT_COMPARTMENT_OCID" --output table
        ;;
    create)
        if [ -z "$DISPLAY_NAME" ] || [ -z "$SIZE_IN_GBS" ]; then
            echo "Error: --name and --size are required for 'create' action." >&2; print_usage; exit 1
        fi
        echo "Creating block volume '$DISPLAY_NAME' of size ${SIZE_IN_GBS}GB..."
        # OCI requires an Availability Domain. We'll dynamically pick the first one available.
        AD=$(oci iam availability-domain list --compartment-id "$OCI_TENANCY_OCID" | jq -r '.data[0].name')
        if [ -z "$AD" ] || [ "$AD" == "null" ]; then
            echo "Error: Could not determine an Availability Domain for this tenancy." >&2; exit 1
        fi
        echo "Using first available Availability Domain: $AD"
        oci bv volume create --availability-domain "$AD" \
            --compartment-id "$OCI_DEFAULT_COMPARTMENT_OCID" \
            --size-in-gbs "$SIZE_IN_GBS" \
            --display-name "$DISPLAY_NAME" \
            --wait-for-state AVAILABLE
        ;;
    attach)
        if [ -z "$VOLUME_ID" ] || [ -z "$INSTANCE_ID" ]; then
            echo "Error: --volume-id and --instance-id are required for 'attach' action." >&2; print_usage; exit 1
        fi
        echo "Attaching volume $VOLUME_ID to instance $INSTANCE_ID..."
        oci compute volume-attachment attach \
            --instance-id "$INSTANCE_ID" \
            --volume-id "$VOLUME_ID" \
            --type iscsi --wait-for-state ATTACHED
        echo "Attachment successful. Note: You may need to format and mount the disk inside the OS."
        ;;
    detach)
        if [ -z "$ATTACHMENT_ID" ]; then
            echo "Error: --attachment-id is required for 'detach' action." >&2; print_usage; exit 1
        fi
        echo "Detaching volume attachment $ATTACHMENT_ID..."
        read -p "Are you sure? This can cause data corruption if the volume is in use. (y/n): " confirm
        if [[ "$confirm" == "y" ]]; then
            oci compute volume-attachment detach --volume-attachment-id "$ATTACHMENT_ID" --force --wait-for-state DETACHED
            echo "Volume detached."
        else
            echo "Operation cancelled."
        fi
        ;;
    delete)
        if [ -z "$VOLUME_ID" ]; then
            echo "Error: --volume-id is required for 'delete' action." >&2; print_usage; exit 1
        fi
        echo "Deleting volume $VOLUME_ID..."
        read -p "DANGER: This is permanent and cannot be undone. Are you sure? (y/n): " confirm
        if [[ "$confirm" == "y" ]]; then
            oci bv volume delete --volume-id "$VOLUME_ID" --force --wait-for-state TERMINATED
            echo "Volume permanently deleted."
        else
            echo "Operation cancelled."
        fi
        ;;
    *)
        echo "Error: Invalid action '$ACTION'." >&2
        print_usage
        exit 1
        ;;
esac
