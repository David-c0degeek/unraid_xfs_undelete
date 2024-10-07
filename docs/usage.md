# Usage Guide

## Configuration

Before running the script, ensure you've configured it properly:

1. Copy the example configuration:
   ```bash
   cp examples/example_config.sh config.sh
   ```

2. Edit the configuration file:
   ```bash
   nano config.sh
   ```

   Adjust the following variables:
   - `DISKS`: Array of disks to process
   - `TIME_RANGE`: Time range for file recovery
   - `FILE_TYPES`: Types of files to recover
   - `ENCRYPTION_PASSWORD`: Your disk encryption password (handle with care!)

## Running the Script

Execute the script with:

```bash
./recover_deleted_files.sh
```

## Options

The script uses the following options for xfs_undelete:

- `-t`: Time range for recovery (e.g., "2023-01-01..now")
- `-r`: File types to recover (e.g., "image/*" or "*" for all files)
- `-o`: Output directory for recovered files

## Output

Recovered files will be stored in:
```
/mnt/disks/ZVTDW2MH/recovered_files/<DISK_ID>/
```

## Monitoring Progress

The script will output progress information to the console. For long-running operations, consider using `screen` or `tmux` to maintain the session.

## Post-Recovery

After recovery:
1. Review the recovered files in the output directory.
2. If needed, run file recovery software on the recovered files to restore file names and directory structure.
3. Securely delete the configuration file containing your encryption password.

For troubleshooting, refer to the [Troubleshooting Guide](troubleshooting.md).