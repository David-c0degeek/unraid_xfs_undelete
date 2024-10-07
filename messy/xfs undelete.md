I'm sorry to hear about your missing photos. Recovering deleted files from an encrypted XFS filesystem in an Unraid array can be complex, but I'll guide you through the process step by step. We'll focus on using `xfs_undelete`, a tool specifically designed for XFS filesystem recovery.

**Important Preliminary Notes:**

- **Minimize Disk Activity:** Stop any operations that might write to the disks in your array to prevent overwriting the deleted data.
- **Backup if Possible:** If you have the means, create a backup image of the affected disks before proceeding.
- **Understand the Risks:** Working with encrypted filesystems adds complexity. Proceed carefully to avoid data loss.

---

### **Step-by-Step Recovery Guide**

#### **1. Identify the Affected Disk(s):**

Unraid stores data across multiple disks. Determine which disk(s) the deleted photos were on:

- **Method A:** If you remember which disk(s) the photos were stored on, note their device identifiers (e.g., `/dev/sdb1`).
- **Method B:** If unsure, you'll need to repeat the recovery process for each data disk in the array.

#### **2. Stop the Array:**

- **Action:** In the Unraid web interface, stop the array to prevent further writes.
- **Path:** **Main** > **Array Operations** > Click **Stop**.

#### **3. Access the Terminal:**

- Open the Unraid terminal from the web interface or SSH into your server.

#### **4. Install Necessary Tools and Dependencies:**

##### **Install Nerd Tools Plugin:**

- **If not already installed:**

  - Go to **Plugins** > **Install Plugin**.
  - Paste the URL for Nerd Tools (formerly Nerd Pack).
  - Click **Install**.

##### **Install `tcl` and `tcllib`:**

- **Action:**

  - Go to **Settings** > **Nerd Tools**.
  - Enable `tcl` and `tcllib`.
  - Click **Apply**.

#### **5. Download and Prepare `xfs_undelete`:**

##### **Download `xfs_undelete`:**

```bash
cd /root/
wget https://github.com/ianka/xfs_undelete/archive/refs/tags/v12.1.zip -O xfs_undelete.zip
unzip xfs_undelete.zip
cd xfs_undelete-12.1/
```

##### **Verify Installation:**

```bash
./xfs_undelete --help
```

#### **6. Decrypt the Encrypted Disk:**

##### **Identify the Encrypted Partition:**

- Use `lsblk` to list block devices:

  ```bash
  lsblk
  ```

- Look for your data disks (e.g., `/dev/sdb1`). The partition number (`1`) is important.

##### **Unlock the Encrypted Partition:**

- **Action:** Use `cryptsetup` to open the encrypted partition.

  ```bash
  cryptsetup luksOpen /dev/sdX1 decrypted_disk
  ```

  - Replace `/dev/sdX1` with the correct device (e.g., `/dev/sdb1`).
  - You'll be prompted for your encryption passphrase.

##### **Verify the Decrypted Device:**

- Check that the decrypted device is available:

  ```bash
  ls /dev/mapper/
  ```

  - You should see `decrypted_disk` listed.

#### **7. Mount the Decrypted Filesystem (Read-Only):**

- **Create a Mount Point:**

  ```bash
  mkdir /mnt/recovery
  ```

- **Mount the Filesystem:**

  ```bash
  mount -o ro /dev/mapper/decrypted_disk /mnt/recovery
  ```

  - The `-o ro` option mounts it as read-only.

#### **8. Prepare an Output Directory on a Separate Drive:**

- **Use an Unassigned Device or External Drive:**

  - **Mount the Drive:**

    - If using Unassigned Devices plugin, the drive should be mounted under `/mnt/disks/YourDriveName/`.

- **Create an Output Directory:**

  ```bash
  mkdir /mnt/disks/YourDriveName/recovered_files
  ```

#### **9. Run `xfs_undelete` to Recover Files:**

##### **Navigate to the `xfs_undelete` Directory:**

```bash
cd /root/xfs_undelete-12.1/
```

##### **Run the Recovery Command:**

```bash
./xfs_undelete -t '2023-10-01..now' -r 'image/*' -o /mnt/disks/YourDriveName/recovered_files /dev/mapper/decrypted_disk
```

- **Explanation:**

  - `-t '2023-10-01..now'`: Specifies the time range (from October 1st, 2023, to now). Adjust as needed.
  - `-r 'image/*'`: Recovers files identified as images.
  - `-o /mnt/disks/YourDriveName/recovered_files`: Specifies the output directory.
  - `/dev/mapper/decrypted_disk`: The decrypted device.

##### **Example Adjustments:**

- **If You Know the Deletion Date:**

  ```bash
  ./xfs_undelete -t '2023-11-05..now' -r 'image/*' -o /mnt/disks/YourDriveName/recovered_files /dev/mapper/decrypted_disk
  ```

- **To Recover All File Types:**

  ```bash
  ./xfs_undelete -t '2023-10-01..now' -r '*' -o /mnt/disks/YourDriveName/recovered_files /dev/mapper/decrypted_disk
  ```

#### **10. Wait for the Process to Complete:**

- **Note:** Recovery may take several hours depending on disk size and number of files.

#### **11. Verify Recovered Files:**

- **Action:** Navigate to the output directory and check the recovered photos.

  ```bash
  cd /mnt/disks/YourDriveName/recovered_files
  ls -l
  ```

#### **12. Clean Up:**

- **Unmount the Decrypted Filesystem:**

  ```bash
  umount /mnt/recovery
  ```

- **Close the Encrypted Device:**

  ```bash
  cryptsetup luksClose decrypted_disk
  ```

- **Start the Array (if desired):**

  - Return to the Unraid web interface and start the array.

---

### **Additional Information**

#### **Time Range Specification:**

- The `-t` option in `xfs_undelete` accepts time ranges understood by Tcl's `[clock scan]`.
- Examples:

  - Specific Date Range:

    ```bash
    -t '2023-10-01..2023-11-01'
    ```

  - Relative Time:

    ```bash
    -t '-7days..now'
    ```

#### **File Type Specification:**

- To list all recognized file types:

  ```bash
  ./xfs_undelete -l
  ```

#### **Alternate Devices (`/dev/mdX`):**

- Some users attempt to use `/dev/mdX` devices (Unraid's managed devices), but these may not work with encrypted filesystems.
- **Recommendation:** Use the decrypted device `/dev/mapper/decrypted_disk`.

#### **Using `photorec` as an Alternative:**

- If `xfs_undelete` doesn't recover the files, consider using `photorec`:

  **Install `testdisk`:**

  ```bash
  apt-get update
  apt-get install testdisk
  ```

  **Run `photorec`:**

  ```bash
  photorec /dev/mapper/decrypted_disk
  ```

  - Follow the on-screen instructions.
  - **Note:** `photorec` may recover a large number of files without filenames.

#### **Handling Encrypted Filesystems:**

- Encrypted filesystems require you to work with the decrypted device.
- Always ensure you're operating on `/dev/mapper/decrypted_disk` after unlocking.

---

### **Final Recommendations**

- **Data Backup:** After recovery, set up a regular backup strategy to prevent future data loss.
- **Professional Assistance:** If you're uncomfortable with these steps or if the data is critical, consider consulting a professional data recovery service.
- **Exercise Caution:** Double-check commands before executing them to prevent unintended consequences.

---

**Feel free to ask if you need further clarification or assistance with any of these steps.**