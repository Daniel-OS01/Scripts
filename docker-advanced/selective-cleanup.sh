#!/bin/bash
# ==============================================================================
# Docker Advanced: Selective Resource Cleanup
# ==============================================================================
#
# Description:
#   This script provides advanced, selective cleanup capabilities for Docker,
#   going beyond the standard `docker system prune`. It allows for targeted
#   deletion of images based on name filters, and includes a safeguarded
#   option to remove unused volumes, which can be critical for saving space.
#
# Usage:
#   ./selective-cleanup.sh [options]
#
# Options:
#   --all                 Remove all unused resources (stopped containers, unused networks).
#   --images              Selectively prune images by name filter.
#   --volumes             Selectively prune all unused volumes (DANGEROUS).
#   --filter-name <glob>  For --images, removes images with names matching a pattern (e.g., "*-dev").
#   --dry-run             Show what would be removed without actually deleting anything.
#   --force               Required for volume cleanup to proceed.
#
# Examples:
#   - Dry run of removing all 'dev' images:
#     ./selective-cleanup.sh --images --filter-name "-dev" --dry-run
#
#   - Remove all 'test' images and all stopped containers:
#     ./selective-cleanup.sh --all --images --filter-name "-test"
#
#   - Forcefully remove all unused Docker volumes after confirmation:
#     ./selective-cleanup.sh --volumes --force
#
# Variables from config.env:
#   - None, this script is self-contained.
#
# ==============================================================================

set -e
set -u
set -o pipefail

# --- Load Configuration ---
# Although this script doesn't use variables from it, sourcing the config
# is a standard practice for consistency across all scripts.
if ! source "$(dirname "$0")/../config.env"; then
    echo "Warning: Could not load configuration file 'config.env'." >&2
fi

# --- Default Flags ---
CLEAN_ALL=false
CLEAN_IMAGES=false
CLEAN_VOLUMES=false
FILTER_NAME=""
DRY_RUN=false
FORCE=false

# --- Argument Parsing ---
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --all) CLEAN_ALL=true ;;
        --images) CLEAN_IMAGES=true ;;
        --volumes) CLEAN_VOLUMES=true ;;
        --filter-name) FILTER_NAME="$2"; shift ;;
        --dry-run) DRY_RUN=true ;;
        --force) FORCE=true ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

# --- Execution Logic ---

if [ "$DRY_RUN" = true ]; then
    echo "--- DRY RUN MODE ENABLED ---"
    echo "No actual changes will be made."
    echo
fi

# 1. Standard Cleanup (stopped containers, unused networks)
if [ "$CLEAN_ALL" = true ]; then
    echo "--- Cleaning stopped containers and unused networks ---"
    if [ "$DRY_RUN" = false ]; then
        docker container prune --force
        docker network prune --force
    else
        echo "[Dry Run] Would execute: docker container prune --force"
        echo "[Dry Run] Would execute: docker network prune --force"
    fi
    echo "Standard cleanup complete."
    echo
fi

# 2. Advanced Image Cleanup
if [ "$CLEAN_IMAGES" = true ]; then
    echo "--- Performing selective image cleanup ---"
    if [ -z "$FILTER_NAME" ]; then
        echo "Error: --filter-name <pattern> is required when using --images." >&2
        exit 1
    fi

    echo "Finding images with name matching pattern: '$FILTER_NAME'"
    # Find images matching the filter pattern, ignoring the currently running ones.
    image_ids=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep "$FILTER_NAME" | xargs -r docker inspect --format='{{.Id}} {{range .RepoTags}}{{.}} {{end}}' | awk '{print $1}')

    if [ -n "$image_ids" ]; then
        echo "Found images to prune:"
        docker images --filter "id=${image_ids}"

        if [ "$DRY_RUN" = false ]; then
            echo "Proceeding with deletion..."
            docker rmi -f $image_ids || echo "Warning: Some images could not be removed (they may be in use by running containers)."
        else
            echo "[Dry Run] Would execute: docker rmi -f $image_ids"
        fi
    else
        echo "No unused images found matching filter '$FILTER_NAME'."
    fi
    echo
fi

# 3. Advanced Volume Cleanup
if [ "$CLEAN_VOLUMES" = true ]; then
    echo "--- Performing volume cleanup ---"
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "!!! DANGER: This is a destructive operation and can result   !!!"
    echo "!!! in permanent data loss. This will remove ALL unused      !!!"
    echo "!!! Docker volumes.                                          !!!"
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"

    if [ "$FORCE" = false ]; then
        echo "Error: The --force flag is required to clean volumes. Aborting to prevent accidental data loss." >&2
        exit 1
    fi

    if [ "$DRY_RUN" = false ]; then
        read -p "Are you absolutely sure you want to delete all unused volumes? Please type 'yes' to confirm: " confirm
        if [[ "$confirm" == "yes" ]]; then
            echo "Proceeding with volume deletion..."
            docker volume prune --force
            echo "Volume cleanup complete."
        else
            echo "Operation cancelled."
        fi
    else
        echo "[Dry Run] Would execute: docker volume prune --force"
    fi
    echo
fi

echo "--- Docker cleanup script finished. ---"
