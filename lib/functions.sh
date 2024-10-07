#!/bin/bash

# Helper functions for XFS Undelete script

# Function to process a single disk
process_disk() {
    local DEVICE=$1
    local DISK_ID=$2
    local ENCRYPTION_STATUS=$3

    echo "Processing $DEVICE ($DISK_ID) - $ENCRYPTION_STATUS"

    # Clean up any previous mounts for this disk
    umount "/mnt/recovery_$DISK_ID" 2>/dev/null

    if [ "$ENCRYPTION_STATUS" = "encrypted" ]; then
        # For encrypted disks
        cryptsetup luksClose "decrypted_$DISK_ID" 2>/dev/null
        if ! unlock_disk "$DEVICE" "$DISK_ID"; then
            echo "Failed to unlock $DEVICE"
            return 1
        fi
        FS_DEVICE="/dev/mapper/decrypted_$DISK_ID"
    else
        # For unencrypted disks
        FS_DEVICE="$DEVICE"
    fi

    # Mount the filesystem
    if ! mount_filesystem "$DISK_ID" "$FS_DEVICE"; then
        return 1
    fi

    # Recover deleted files
    recover_files "$DISK_ID" "$FS_DEVICE"

    # Clean up
    cleanup_disk "$DISK_ID" "$ENCRYPTION_STATUS"

    echo "Completed processing $DEVICE ($DISK_ID)."
}

# Function to unlock an encrypted disk
unlock_disk() {
    local DEVICE=$1
    local DISK_ID=$2

    echo -n "$ENCRYPTION_PASSWORD" | cryptsetup luksOpen "$DEVICE" "decrypted_$DISK_ID" --key-file=-
    if [ $? -ne 0 ]; then
        return 1
    fi

    if [ ! -e "/dev/mapper/decrypted_$DISK_ID" ]; then
        echo "Decrypted device /dev/mapper/decrypted_$DISK_ID does not exist."
        return 1
    fi

    return 0
}

# Function to mount the filesystem
mount_filesystem() {
    local DISK_ID=$1
    local FS_DEVICE=$2

    # Verify that the filesystem is XFS
    local FS_TYPE=$(blkid -o value -s TYPE "$FS_DEVICE")
    if [ "$FS_TYPE" != "xfs" ]; then
        echo "The filesystem on $FS_DEVICE is not XFS. Skipping."
        return 1
    fi

    # Create mount point if it doesn't exist
    local MOUNT_POINT="/mnt/recovery_$DISK_ID"
    mkdir -p "$MOUNT_POINT"

    # Mount the filesystem (read-only)
    mount -o ro "$FS_DEVICE" "$MOUNT_POINT"
    if [ $? -ne 0 ]; then
        echo "Failed to mount $FS_DEVICE"
        return 1
    fi

    return 0
}

# Function to recover files
recover_files() {
    local DISK_ID=$1
    local FS_DEVICE=$2
    local OUTPUT_DIR="$OUTPUT_BASE_DIR/$DISK_ID"
    mkdir -p "$OUTPUT_DIR"

    cd "$XFS_UNDELETE_PATH"
    ./xfs_undelete -t "$TIME_RANGE" -r "$FILE_TYPES" -o "$OUTPUT_DIR" "$FS_DEVICE"

    # Optional: Delete .matroska files if not needed
    if [ "$DELETE_MATROSKA" = true ]; then
        find "$OUTPUT_DIR" -type f -name '*.matroska' -delete
    fi
}

# Function to clean up after processing a disk
cleanup_disk() {
    local DISK_ID=$1
    local ENCRYPTION_STATUS=$2
    umount "/mnt/recovery_$DISK_ID"
    if [ "$ENCRYPTION_STATUS" = "encrypted" ]; then
        cryptsetup luksClose "decrypted_$DISK_ID"
    fi
}

# Function to perform final cleanup
cleanup() {
    echo "Performing final cleanup..."
    for DISK_ID in "${DISK_IDS[@]}"; do
        umount "/mnt/recovery_$DISK_ID" 2>/dev/null
        cryptsetup luksClose "decrypted_$DISK_ID" 2>/dev/null
    done
}