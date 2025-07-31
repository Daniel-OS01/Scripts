#!/bin/bash
# ==============================================================================
# Backup & Recovery: Perform Encrypted S3 Backup
# ==============================================================================
#
# Description:
#   This script automates the process of backing up a local directory.
#   It performs the following critical steps for a secure backup workflow:
#   1. Compresses the source directory into a .tar.gz archive.
#   2. Encrypts the archive using GPG with a symmetric passphrase from the config.
#   3. Uploads the final encrypted archive to an S3-compatible object storage.
#
# Usage:
#   ./perform-s3-backup.sh <path_to_directory>
#
# Example:
#   ./perform-s3-backup.sh /var/lib/docker/volumes/my_app_data
#
# Variables from config.env:
#   - BACKUP_S3_ENDPOINT
#   - BACKUP_S3_ACCESS_KEY
#   - BACKUP_S3_SECRET_KEY
#   - BACKUP_S3_BUCKET_NAME
#   - BACKUP_ENCRYPTION_PASSPHRASE
#
# Prerequisites:
#   - `aws-cli` must be installed (`sudo apt install awscli`).
#   - `gpg` must be installed (`sudo apt install gnupg`).
#
# ==============================================================================

set -e
set -u
set -o pipefail

# --- Configuration ---
# This script assumes that all BACKUP_* variables have been exported into the
# environment by the main.sh orchestrator.

# --- Check Prerequisites ---
if ! command -v aws &> /dev/null; then
    echo "Error: 'aws-cli' is not installed. Please install it first (e.g., 'sudo apt install awscli')." >&2
    exit 1
fi
if ! command -v gpg &> /dev/null; then
    echo "Error: 'gpg' is not installed. Please install it first (e.g., 'sudo apt install gnupg')." >&2
    exit 1
fi

# --- Script Parameters ---
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <path_to_directory_to_backup>" >&2
    exit 1
fi

SOURCE_DIR="$1"
# Ensure the source directory exists and is a directory
if [ ! -d "$SOURCE_DIR" ]; then
    echo "Error: Source directory '$SOURCE_DIR' does not exist or is not a directory." >&2
    exit 1
fi

# --- Main Logic ---

# Define filenames and paths using a temporary directory for safety
TMP_DIR=$(mktemp -d)
# Clean up the temp directory on script exit
trap 'rm -rf -- "$TMP_DIR"' EXIT

DIR_BASENAME=$(basename "$SOURCE_DIR")
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
ARCHIVE_FILE="${TMP_DIR}/${DIR_BASENAME}_${TIMESTAMP}.tar.gz"
ENCRYPTED_FILE="${ARCHIVE_FILE}.gpg"
S3_TARGET_PATH="s3://${BACKUP_S3_BUCKET_NAME}/${DIR_BASENAME}/${DIR_BASENAME}_${TIMESTAMP}.tar.gz.gpg"

echo "Starting backup process for: $SOURCE_DIR"
echo "-------------------------------------------------"

# Step 1: Create a compressed archive
echo "Step 1/4: Compressing directory..."
tar -czf "$ARCHIVE_FILE" -C "$(dirname "$SOURCE_DIR")" "$DIR_BASENAME"
echo "  - Archive created at: $ARCHIVE_FILE"

# Step 2: Encrypt the archive
echo "Step 2/4: Encrypting archive..."
gpg --quiet --batch --yes --symmetric --cipher-algo AES256 \
    --passphrase "$BACKUP_ENCRYPTION_PASSPHRASE" \
    --output "$ENCRYPTED_FILE" "$ARCHIVE_FILE"
echo "  - Encryption complete: $ENCRYPTED_FILE"

# Step 3: Configure AWS CLI for S3 upload using environment variables
# This is the recommended way to provide credentials to the AWS CLI in scripts.
echo "Step 3/4: Configuring S3 credentials for this session..."
export AWS_ACCESS_KEY_ID="$BACKUP_S3_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$BACKUP_S3_SECRET_KEY"
# Unset session token for safety, as we are using long-lived credentials
export AWS_SESSION_TOKEN=""

# Step 4: Upload to S3-compatible storage
echo "Step 4/4: Uploading to S3..."
echo "  - Target: $S3_TARGET_PATH"
aws s3 cp "$ENCRYPTED_FILE" "$S3_TARGET_PATH" --endpoint-url "$BACKUP_S3_ENDPOINT"
echo "  - Upload complete."

# The trap will automatically clean up the temporary directory.
echo "Cleaning up local temporary files..."

echo
echo "-----------------------------------------------------------------"
echo "SUCCESS! Backup completed and uploaded successfully."
echo "-----------------------------------------------------------------"
