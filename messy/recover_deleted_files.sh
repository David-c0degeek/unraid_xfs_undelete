#!/bin/bash

# Array of disks with device paths and disk IDs
disks=(
  "/dev/sdb1 ZL2KG9X9"
  "/dev/sdg1 ZL2KG6WF"
  "/dev/sdd1 WL2068SD"
  "/dev/sdf1 ZL2PFBXQ"
)

# Adjust time range and file types as needed
TIME_RANGE="2023-01-01..now"
FILE_TYPES="*"

# Enter your encryption passphrase here
# WARNING: Storing your encryption password in a script is insecure.
# Ensure this script is secured and delete it after use.
ENCRYPTION_PASSWORD="YourEncryptionPassword"

# Function to clean up mounts and decrypted devices
cleanup() {
  echo "Cleaning up..."
  for DISK_ID in "${DISK_IDS[@]}"; do
    umount "/mnt/recovery_$DISK_ID" 2>/dev/null
    cryptsetup luksClose "decrypted_$DISK_ID" 2>/dev/null
  done
}

# Trap script exit to ensure cleanup
trap cleanup EXIT

# Array to keep track of disk IDs
DISK_IDS=()

for entry in "${disks[@]}"
do
  set -- $entry
  DEVICE=$1
  DISK_ID=$2
  DISK_IDS+=("$DISK_ID")

  echo "Processing $DEVICE ($DISK_ID)..."

  # Clean up any previous mounts and mappings for this disk
  umount "/mnt/recovery_$DISK_ID" 2>/dev/null
  cryptsetup luksClose "decrypted_$DISK_ID" 2>/dev/null

  # Unlock the encrypted partition
  echo -n "$ENCRYPTION_PASSWORD" | cryptsetup luksOpen "$DEVICE" "decrypted_$DISK_ID" --key-file=-
  if [ $? -ne 0 ]; then
    echo "Failed to unlock $DEVICE"
    continue
  fi

  # Check if the decrypted device exists
  if [ ! -e "/dev/mapper/decrypted_$DISK_ID" ]; then
    echo "Decrypted device /dev/mapper/decrypted_$DISK_ID does not exist."
    cryptsetup luksClose "decrypted_$DISK_ID"
    continue
  fi

  # Determine if the XFS filesystem is on the decrypted device or a partition inside it
  FS_DEVICE="/dev/mapper/decrypted_$DISK_ID"

  # Check if the decrypted device contains partitions
  PARTITIONS=$(lsblk -ln -o NAME "$FS_DEVICE" | grep -E "^├─|^└─")
  if [ -n "$PARTITIONS" ]; then
    # If partitions exist, use the first partition
    PART_NAME=$(lsblk -ln -o NAME "$FS_DEVICE" | grep -E "^├─|^└─" | head -n1 | awk '{print $1}')
    FS_DEVICE="/dev/mapper/$PART_NAME"
  fi

  # Verify that the filesystem is XFS
  FS_TYPE=$(blkid -o value -s TYPE "$FS_DEVICE")
  if [ "$FS_TYPE" != "xfs" ]; then
    echo "The filesystem on $FS_DEVICE is not XFS. Skipping."
    cryptsetup luksClose "decrypted_$DISK_ID"
    continue
  fi

  # Create mount point if it doesn't exist
  MOUNT_POINT="/mnt/recovery_$DISK_ID"
  if [ ! -d "$MOUNT_POINT" ]; then
    mkdir "$MOUNT_POINT"
  fi

  # Mount the decrypted filesystem (read-only)
  mount -o ro "$FS_DEVICE" "$MOUNT_POINT"
  if [ $? -ne 0 ]; then
    echo "Failed to mount $FS_DEVICE"
    cryptsetup luksClose "decrypted_$DISK_ID"
    continue
  fi

  # Create output directory
  OUTPUT_DIR="/mnt/disks/ZVTDW2MH/recovered_files/$DISK_ID"
  mkdir -p "$OUTPUT_DIR"

  # Recover deleted files
  cd /root/xfs_undelete-12.1/
  ./xfs_undelete -t "$TIME_RANGE" -r "$FILE_TYPES" -o "$OUTPUT_DIR" "$FS_DEVICE"

  # Optional: Delete .matroska files if not needed
  # Uncomment the following line to delete .matroska files
  # find "$OUTPUT_DIR" -type f -name '*.matroska' -delete

  # Clean up
  umount "$MOUNT_POINT"
  cryptsetup luksClose "decrypted_$DISK_ID"

  echo "Completed processing $DEVICE ($DISK_ID)."

done