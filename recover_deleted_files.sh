#!/bin/bash

# XFS Undelete for Unraid
# This script recovers deleted files from encrypted XFS filesystems on Unraid servers.

# Source configuration
source config.sh

# Source helper functions
source lib/functions.sh

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