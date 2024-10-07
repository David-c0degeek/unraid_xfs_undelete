#!/bin/bash

# XFS Undelete for Unraid
# This script recovers deleted files from encrypted XFS filesystems on Unraid servers.

# Source configuration
source config.sh

# Source helper functions
source lib/functions.sh

# Handle password method
if [ "$PASSWORD_METHOD" = "prompt" ]; then
    # Prompt the user for the encryption passphrase
    read -s -p "Enter encryption passphrase: " ENCRYPTION_PASSWORD
    echo
elif [ "$PASSWORD_METHOD" = "script" ]; then
    # Password is already set in config.sh
    echo "Using encryption password from config file."
else
    echo "Invalid PASSWORD_METHOD in config. Use 'prompt' or 'script'."
    exit 1
fi

# Array to keep track of disk IDs
DISK_IDS=()

# Main execution
for entry in "${DISKS[@]}"; do
    set -- $entry
    DEVICE=$1
    DISK_ID=$2
    DISK_IDS+=("$DISK_ID")

    process_disk "$DEVICE" "$DISK_ID"
done

# Final cleanup
cleanup