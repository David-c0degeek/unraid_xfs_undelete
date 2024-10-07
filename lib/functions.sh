#!/bin/bash

# Helper functions for XFS Undelete script

# Function to process a single disk
process_disk() {
    local DEVICE=$1
    local DISK_ID=$2

    echo "Processing $DEVICE ($DISK_ID)..."

    # Clean up any previous mounts and mappings for this disk
    umount "/mnt/recovery_$DISK_ID" 2>/dev/null
    cryptsetup luksClose "decrypted_$DISK_ID" 2>/dev/null

    # Unlock the encrypted partition
    if ! unlock_disk "$DEVICE" "$DISK_ID"; then
        echo "Failed to unlock $DEVICE"
        return 1
    fi

    # Mount the decrypted filesystem
    if ! mount_filesystem "$DISK_ID"; then
        return 1
    fi

    # Recover deleted files
    recover_files "$DISK_ID"

    # Clean up
    cleanup_disk "$DISK_ID"

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

# Function to mount the decrypted filesystem
mount_filesystem() {
    local DISK_ID=$1
    local FS_DEVICE="/dev/mapper/decrypted_$DISK_ID"

    # Check if the decrypted device contains partitions
    local PARTITIONS=$(lsblk -ln -o NAME "$FS_DEVICE" | grep -E "^├─|^└─")
    if [ -n "$PARTITIONS" ]; then
        # If partitions exist, use the first partition
        local PART_NAME=$(lsblk -ln -o NAME "$FS_DEVICE" | grep -E "^├─|^└─" | head -n1 | awk '{print $1}')
        FS_DEVICE="/dev/mapper/$PART_NAME"
    fi

    # Verify that the filesystem is XFS
    local FS_TYPE=$(blkid -o value -s TYPE "$FS_DEVICE")
    if [ "$FS_TYPE" != "xfs" ]; then
        echo "The filesystem on $FS_DEVICE is not XFS. Skipping."
        cryptsetup luksClose "decrypted_$DISK_ID"
        return 1
    fi

    # Create mount point if it doesn't exist
    local MOUNT_POINT="/mnt/recovery_$DISK_ID"
    mkdir -p "$MOUNT_POINT"

    # Mount the decrypted filesystem (read-only)
    mount -o ro "$FS_DEVICE" "$MOUNT_POINT"
    if [ $? -ne 0 ]; then
        echo "Failed to mount $FS_DEVICE"
        cryptsetup luksClose "decrypted_$DISK_ID"
        return 1
    fi

    return 0
}

# Function to recover files
recover_files() {
    local DISK_ID=$1
    local OUTPUT_DIR="$OUTPUT_BASE_DIR/$DISK_ID"
    mkdir -p "$OUTPUT_DIR"

    cd "$XFS_UNDELETE_PATH"
    ./xfs_undelete -t "$TIME_RANGE" -r "$FILE_TYPES" -o "$OUTPUT_DIR" "/dev/mapper/decrypted_$DISK_ID"

    # Optional: Delete .matroska files if not needed
    if [ "$DELETE_MATROSKA" = true ]; then
        find "$OUTPUT_DIR" -type f -name '*.matroska' -delete
    fi
}

# Function to clean up after processing a disk
cleanup_disk() {
    local DISK_ID=$1
    umount "/mnt/recovery_$DISK_ID"
    cryptsetup luksClose "decrypted_$DISK_ID"
}

# Function to perform final cleanup
cleanup() {
    echo "Performing final cleanup..."
    for DISK_ID in "${DISK_IDS[@]}"; do
        umount "/mnt/recovery_$DISK_ID" 2>/dev/null
        cryptsetup luksClose "decrypted_$DISK_ID" 2>/dev/null
    done
}