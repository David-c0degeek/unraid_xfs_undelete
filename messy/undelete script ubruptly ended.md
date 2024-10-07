I'm sorry to hear that the script ended abruptly. When a script like this terminates unexpectedly, it may leave mounted filesystems and open encrypted devices. You'll need to clean these up before restarting the script. Here's how you can unmount, clear, and prepare to restart the script:

---

### **1. Identify Mounted Filesystems and Open Encrypted Devices**

First, let's check for any mounted filesystems and open encrypted devices left by the script.

#### **List Mounted Recovery Filesystems**

Run the following command to list any recovery mount points:

```bash
mount | grep /mnt/recovery_
```

This will show all mount points that start with `/mnt/recovery_`.

#### **List Open Encrypted Devices**

Check for any open decrypted devices:

```bash
ls /dev/mapper/decrypted_*
```

---

### **2. Unmount Mounted Filesystems**

For each mounted recovery filesystem, unmount it using `umount`.

**Example:**

```bash
umount /mnt/recovery_ZL2KG9X9
umount /mnt/recovery_ZL2KG6WF
umount /mnt/recovery_WL2068SD
umount /mnt/recovery_ZL2PFBXQ
```

If you have multiple mount points, you can unmount them all with a single command:

```bash
umount /mnt/recovery_*
```

**Note:** If you receive a "target is busy" error, you can use the lazy unmount option (use with caution):

```bash
umount -l /mnt/recovery_ZL2KG9X9
```

---

### **3. Close Open Encrypted Devices**

For each open decrypted device, close it using `cryptsetup luksClose`.

**Example:**

```bash
cryptsetup luksClose decrypted_ZL2KG9X9
cryptsetup luksClose decrypted_ZL2KG6WF
cryptsetup luksClose decrypted_WL2068SD
cryptsetup luksClose decrypted_ZL2PFBXQ
```

Alternatively, you can use a loop to close all decrypted devices:

```bash
for device in /dev/mapper/decrypted_*; do
    name=$(basename "$device")
    cryptsetup luksClose "$name"
done
```

---

### **4. Remove Leftover Mount Points (Optional)**

If you want to remove the recovery directories:

```bash
rm -rf /mnt/recovery_ZL2KG9X9
rm -rf /mnt/recovery_ZL2KG6WF
rm -rf /mnt/recovery_WL2068SD
rm -rf /mnt/recovery_ZL2PFBXQ
```

Ensure the directories are unmounted before deleting them.

---

### **5. Verify Clean State**

Check that there are no more mounted recovery filesystems or open decrypted devices.

**Check Mounts:**

```bash
mount | grep /mnt/recovery_
```

This should return no output if all recovery filesystems are unmounted.

**Check Decrypted Devices:**

```bash
ls /dev/mapper/decrypted_*
```

This should return no output if all decrypted devices are closed.

---

### **6. Investigate Why the Script Ended Abruptly**

Before restarting, it's important to understand why the script terminated.

#### **Check Script Output**

- Review any error messages displayed in the terminal.

#### **Check System Logs**

- View the system log for errors:

  ```bash
  dmesg | tail -n 50
  ```

#### **Check Disk Space**

- Ensure that the destination drive (`ZVTDW2MH`) has sufficient free space:

  ```bash
  df -h /mnt/disks/ZVTDW2MH
  ```

#### **Check Permissions**

- Ensure you have the necessary permissions to perform recovery operations.

---

### **7. Modify the Script for Better Error Handling**

To prevent abrupt termination in the future, consider adding error handling to your script.

#### **Add a Cleanup Function**

Include a cleanup function that runs on script exit, even if it exits unexpectedly.

**Add at the top of your script:**

```bash
trap cleanup EXIT

cleanup() {
    echo "Cleaning up..."
    umount /mnt/recovery_* 2>/dev/null
    for device in /dev/mapper/decrypted_*; do
        name=$(basename "$device")
        cryptsetup luksClose "$name" 2>/dev/null
    done
}
```

This ensures that any mounted filesystems and open devices are closed when the script exits.

---

### **8. Restart the Script**

Now that you've cleaned up the environment:

- **Optionally**, adjust your script based on any errors you found.
- **Run the script again:**

  ```bash
  ./recover_photos.sh
  ```

---

### **9. Monitor the Script Execution**

Consider redirecting script output to a log file to capture any errors:

```bash
./recover_photos.sh | tee recovery.log
```

This way, you can review `recovery.log` for any issues that occur during execution.

---

### **10. Additional Tips**

#### **Ensure Correct Device Names**

- Device identifiers like `/dev/sdb1` can change after reboots.
- Use `lsblk` to verify the correct device names:

  ```bash
  lsblk -o NAME,SIZE,MODEL,MOUNTPOINT
  ```

#### **Avoid Concurrent Access**

- Ensure no other processes are accessing the disks you're working on.

#### **Check for Running Processes Using Mount Points**

If you can't unmount a filesystem, it might be because processes are using it.

Find such processes:

```bash
lsof +D /mnt/recovery_ZL2KG9X9
```

Terminate them if necessary.

---

### **11. Consider Rebooting (Last Resort)**

If you're unable to clean up mounts or devices, a system reboot can reset the environment. However, use this as a last resort and ensure that all critical operations are saved or completed.

---

### **Summary**

- **Unmount Mounted Filesystems:** Use `umount /mnt/recovery_*`.
- **Close Encrypted Devices:** Use `cryptsetup luksClose decrypted_*`.
- **Clean Up Directories (Optional):** Use `rm -rf /mnt/recovery_*`.
- **Verify Clean State:** Ensure no recovery mount points or decrypted devices are active.
- **Investigate Errors:** Check script output, system logs, and disk space.
- **Modify Script:** Add cleanup functions and better error handling.
- **Restart Script:** After ensuring a clean environment.
- **Monitor Execution:** Redirect output to a log file for troubleshooting.

---

### **Feel Free to Ask for Further Assistance**

If you need help interpreting any errors or adjusting your script, please let me know, and I'll be happy to assist further.