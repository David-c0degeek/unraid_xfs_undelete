# Usage Guide

## Configuration

Before running the script, you must configure it to match your specific Unraid setup:

1. Copy the example configuration:
   ```bash
   cp examples/example_config.sh config.sh
   ```

2. Edit the configuration file:
   ```bash
   nano config.sh
   ```

   Customize the following variables:
   - `DISKS`: Array of disks to process (update device paths, disk IDs, and encryption status)
   - `TIME_RANGE`: Time range for file recovery
   - `FILE_TYPES`: Types of files to recover
   - `PASSWORD_METHOD`: Choose between "prompt" (more secure) or "script" (less secure) for encrypted disks
   - `ENCRYPTION_PASSWORD`: Your disk encryption password (only if using PASSWORD_METHOD="script")
   - `OUTPUT_BASE_DIR`: Directory where recovered files will be stored

   Example of customizing the `DISKS` array:
   ```bash
   DISKS=(
     "/dev/sda1 DISK1 encrypted"
     "/dev/sdb1 DISK2 unencrypted"
     "/dev/sdc1 DISK3 encrypted"
   )
   ```

   **IMPORTANT:** Customize the output directory:
   ```bash
   OUTPUT_BASE_DIR="/mnt/disks/YOUR_OUTPUT_DISK/recovered_files"
   ```
   Replace `YOUR_OUTPUT_DISK` with the actual disk or share where you want to store recovered files.

3. For encrypted disks, choose a password handling method:
   - For enhanced security, set `PASSWORD_METHOD="prompt"`. You'll be asked for the password when running the script.
   - If you prefer to store the password in the config file (less secure), set `PASSWORD_METHOD="script"` and provide the password in the `ENCRYPTION_PASSWORD` variable.

4. Verify that the `XFS_UNDELETE_PATH` points to the correct location of the xfs_undelete tool on your system.

## Running the Script

After customizing the configuration, execute the script with:

```bash
./recover_deleted_files.sh
```

If you've set `PASSWORD_METHOD="prompt"`, you'll be asked to enter the encryption password for encrypted disks when the script runs.

## Output

Recovered files will be stored in:
```
$OUTPUT_BASE_DIR/<DISK_ID>/
```
Where `<DISK_ID>` is the identifier you specified in the `DISKS` array, and `OUTPUT_BASE_DIR` is the custom path you set in the configuration file.

## Monitoring Progress

The script will output progress information to the console. For long-running operations, consider using `screen` or `tmux` to maintain the session.

## Post-Recovery

After recovery:
1. Review the recovered files in your specified output directory.
2. If needed, run file recovery software on the recovered files to restore file names and directory structure.
3. If you used `PASSWORD_METHOD="script"`, securely delete the configuration file containing your encryption password or remove the password from it.

For troubleshooting, refer to the [Troubleshooting Guide](troubleshooting.md).