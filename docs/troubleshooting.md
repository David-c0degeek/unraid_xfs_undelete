# Troubleshooting Guide

## Common Issues and Solutions

### 1. Script Abruptly Terminates

**Problem:** The script ends unexpectedly, leaving mounted filesystems and open encrypted devices.

**Solution:**
1. Identify mounted filesystems:
   ```bash
   mount | grep /mnt/recovery_
   ```
2. Unmount recovery filesystems:
   ```bash
   umount /mnt/recovery_*
   ```
3. Close decrypted devices:
   ```bash
   for device in /dev/mapper/decrypted_*; do
     name=$(basename "$device")
     cryptsetup luksClose "$name"
   done
   ```
4. Verify clean state:
   ```bash
   mount | grep /mnt/recovery_
   ls /dev/mapper/decrypted_*
   ```
5. Restart the script.

### 2. Incorrect Device Identifiers

**Problem:** Device names (e.g., /dev/sdb1) have changed.

**Solution:**
1. Use `lsblk` to list current block devices:
   ```bash
   lsblk
   ```
2. Update the `DISKS` array in `config.sh` with the correct device identifiers.

### 3. Insufficient Disk Space

**Problem:** The recovery process fails due to lack of space on the destination drive.

**Solution:**
1. Check available space:
   ```bash
   df -h /mnt/disks/ZVTDW2MH
   ```
2. Free up space or use a different destination drive with sufficient capacity.
3. Update the `OUTPUT_DIR` in the script if using a different drive.

### 4. xfs_undelete Not Found

**Problem:** The script can't find the xfs_undelete tool.

**Solution:**
1. Verify xfs_undelete installation:
   ```bash
   /root/xfs_undelete-12.1/xfs_undelete --help
   ```
2. If not found, reinstall following the [Installation Guide](installation.md).

## Reporting Issues

If you encounter issues not covered here, please:
1. Check the script's output for error messages.
2. Review system logs: `dmesg | tail -n 50`
3. Open an issue on the GitHub repository with detailed information about the problem and steps to reproduce it.