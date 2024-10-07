# XFS Undelete Script for Unraid

This guide provides a comprehensive script to recover deleted files from encrypted XFS filesystems on your Unraid server. It includes detailed explanations, usage instructions, and steps to recover from abrupt script termination.

---

## Table of Contents

1. [Introduction](#introduction)
2. [Prerequisites](#prerequisites)
3. [Script Overview](#script-overview)
4. [Full Script](#full-script)
5. [Usage Instructions](#usage-instructions)
6. [Script Explanation](#script-explanation)
7. [Handling Script Abrupt Termination](#handling-script-abrupt-termination)
8. [Additional Considerations](#additional-considerations)
9. [Conclusion](#conclusion)

---

## Introduction

This script automates the process of:

- Unlocking encrypted disks using `cryptsetup`.
- Mounting the decrypted filesystems in read-only mode.
- Recovering deleted files using `xfs_undelete`.
- Cleaning up by unmounting and closing decrypted devices.

---

## Prerequisites

- **Unraid Server** with the disks you wish to recover from.
- **Encryption Password** for the encrypted disks.
- **`xfs_undelete` Tool** installed in `/root/xfs_undelete-12.1/`.
- **Sufficient Disk Space** on the destination drive (`ZVTDW2MH`) to store recovered files.
- **Root Access** to run the script with necessary permissions.

---

## Script Overview

- **Purpose:** Recover deleted files (e.g., photos) from encrypted XFS filesystems.
- **Disks:** The script processes multiple disks specified in an array.
- **Time Range and File Types:** Customizable to target specific files.
- **Cleanup Mechanism:** Ensures mounts and encrypted devices are closed, even if the script exits unexpectedly.

---

## Full Script

```bash
#!/bin/bash

# Array of disks with device paths and disk IDs
disks=(
  "/dev/sdb1 ZL2KG9X9"
  "/dev/sdg1 ZL2KG6WF"
  "/dev/sdd1 WL2068SD"
  "/dev/sdf1 ZL2PFBXQ"
)

# Adjust time range and file types as needed
TIME_RANGE="2024-01-01..now"
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
```

---

## Usage Instructions

### 1. Prepare the Script

- **Save the Script:**
  - Copy the script content and save it as `recover_deleted_files.sh` on your Unraid server.
- **Make It Executable:**
  ```bash
  chmod +x recover_deleted_files.sh
  ```

### 2. Adjust Variables

- **Encryption Password:**
  - Replace `"YourEncryptionPassword"` with your actual encryption password.
  ```bash
  ENCRYPTION_PASSWORD="YourActualPassword"
  ```
  - **Security Note:** Storing passwords in scripts is insecure. Consider prompting for the password at runtime:
    ```bash
    read -s -p "Enter encryption passphrase: " ENCRYPTION_PASSWORD
    echo
    ```
- **Time Range:**
  - Set `TIME_RANGE` to the desired time frame for recovery.
  ```bash
  TIME_RANGE="2024-01-01..now"
  ```
- **File Types:**
  - Specify the file types you want to recover (e.g., images).
  ```bash
  FILE_TYPES="image/*"
  ```

### 3. Run the Script

- **Execute the Script:**
  ```bash
  ./recover_deleted_files.sh
  ```
- **Monitor Output:**
  - The script will display progress and any errors encountered.

### 4. Verify Recovered Files

- **Location of Recovered Files:**
  - Files are recovered to `/mnt/disks/ZVTDW2MH/recovered_files/<DISK_ID>/`.
- **Check for Unwanted Files:**
  - If `.matroska` files are present and not needed, uncomment the line in the script to delete them.

---

## Script Explanation

### Disk Array

- **Definition:**
  ```bash
  disks=(
    "/dev/sdb1 ZL2KG9X9"
    "/dev/sdg1 ZL2KG6WF"
    "/dev/sdd1 WL2068SD"
    "/dev/sdf1 ZL2PFBXQ"
  )
  ```
- **Purpose:** Lists the disk devices and their corresponding IDs for processing.

### Variables

- **`TIME_RANGE`:** Specifies the time frame for file recovery.
- **`FILE_TYPES`:** Defines the types of files to recover.
- **`ENCRYPTION_PASSWORD`:** The password used to unlock encrypted disks.

### Cleanup Function and Trap

- **Cleanup Function:**
  ```bash
  cleanup() { ... }
  ```
  - Ensures that any mounted filesystems and decrypted devices are closed upon script exit.
- **Trap Command:**
  ```bash
  trap cleanup EXIT
  ```
  - Invokes the cleanup function when the script exits, even if abruptly.

### Processing Loop

- **Unlock Encrypted Partition:**
  ```bash
  echo -n "$ENCRYPTION_PASSWORD" | cryptsetup luksOpen "$DEVICE" "decrypted_$DISK_ID" --key-file=-
  ```
- **Check Decrypted Device:**
  - Verifies that the decrypted device exists before proceeding.
- **Determine Filesystem Device:**
  - Checks if the decrypted device contains partitions and sets `FS_DEVICE` accordingly.
- **Verify Filesystem Type:**
  - Uses `blkid` to ensure the filesystem is XFS.
- **Mount Filesystem:**
  - Mounts the decrypted filesystem in read-only mode.
- **Recover Deleted Files:**
  - Runs `xfs_undelete` with specified parameters.
- **Cleanup:**
  - Unmounts the filesystem and closes the decrypted device.

---

## Handling Script Abrupt Termination

### Issue

If the script ends unexpectedly, it may leave mounted filesystems and open encrypted devices, which can cause conflicts or prevent rerunning the script.

### Recovery Steps

1. **Identify Mounted Filesystems:**

   ```bash
   mount | grep /mnt/recovery_
   ```

2. **Unmount Recovery Filesystems:**

   ```bash
   umount /mnt/recovery_*
   ```

3. **Close Decrypted Devices:**

   ```bash
   for device in /dev/mapper/decrypted_*; do
     name=$(basename "$device")
     cryptsetup luksClose "$name"
   done
   ```

4. **Verify Clean State:**

   - Check that no recovery filesystems are mounted:
     ```bash
     mount | grep /mnt/recovery_
     ```
   - Check that no decrypted devices are open:
     ```bash
     ls /dev/mapper/decrypted_*
     ```

5. **Restart the Script:**

   ```bash
   ./recover_deleted_files.sh
   ```

### Preventing Future Abrupt Termination

- **Error Handling:**
  - The script includes checks after critical commands to handle failures gracefully.
- **Cleanup Function:**
  - The `cleanup` function ensures resources are released even if the script is interrupted.
- **System Monitoring:**
  - Ensure sufficient disk space and system resources to prevent unexpected terminations.
- **Logging:**
  - Redirect output to a log file for troubleshooting:
    ```bash
    ./recover_deleted_files.sh | tee recovery.log
    ```

---

## Additional Considerations

### Security

- **Encryption Password:**
  - Avoid hardcoding passwords in scripts.
  - Use prompts or secure methods to supply the password.

### Device Identifiers

- **Consistency:**
  - Device names (e.g., `/dev/sdb1`) can change. Use UUIDs or labels if possible.
  - Verify device mappings before running the script.

### Disk Space

- **Ensure Adequate Space:**
  - The destination directory must have enough space to store recovered files.

### Permissions

- **Run as Root:**
  - The script requires root privileges to perform certain operations.

### Testing

- **Test with a Single Disk:**
  - Before processing all disks, test the script on one to ensure it works as expected.

### Backup Strategy

- **Regular Backups:**
  - Implement a backup plan to prevent data loss and minimize the need for recovery.

---

## Conclusion

This script provides an automated solution to recover deleted files from encrypted XFS filesystems on your Unraid server. By following the usage instructions and being mindful of the considerations outlined, you can effectively recover your data.

**Remember:**

- **Security First:** Protect your encryption passwords and sensitive data.
- **Stay Informed:** Monitor the script's output and system resources.
- **Be Prepared:** Know how to handle unexpected interruptions and recover gracefully.

---

**Disclaimer:** Use this script at your own risk. Always ensure you have backups of your data. The author is not responsible for any data loss or system issues resulting from the use of this script.

---

If you have any questions or need further assistance, feel free to reach out!