# XFS Undelete for Unraid - Example Configuration

# IMPORTANT: This is an example configuration. You MUST modify these values to match your specific setup.

# Array of disks with device paths, disk IDs, and encryption status
# Format: "/dev/sdX1 DISK_ID encrypted|unencrypted"
# CUSTOMIZE THESE VALUES for your specific disks:
DISKS=(
  "/dev/sdb1 DISK1 encrypted"
  "/dev/sdg1 DISK2 encrypted"
  "/dev/sdd1 DISK3 unencrypted"
  "/dev/sdf1 DISK4 unencrypted"
)

# Time range for file recovery
# Format: "YYYY-MM-DD..now" or "YYYY-MM-DD..YYYY-MM-DD"
TIME_RANGE="2023-01-01..now"

# File types to recover
# Use "*" for all files, or specify types like "image/*"
FILE_TYPES="*"

# Encryption password handling (for encrypted disks)
# Set to "prompt" to be asked for the password at runtime (more secure)
# Set to "script" to use the password defined below (less secure)
PASSWORD_METHOD="prompt"

# Encryption password for the disks (used if PASSWORD_METHOD is "script")
# WARNING: Storing passwords in plain text is a security risk.
# Only use this method if you understand and accept the security implications.
ENCRYPTION_PASSWORD="YourEncryptionPassword"

# Output directory for recovered files
# CUSTOMIZE THIS PATH to match your desired output location:
# Replace YOUR_OUTPUT_DISK with the actual disk or share where you want to store recovered files
OUTPUT_BASE_DIR="/mnt/disks/YOUR_OUTPUT_DISK/recovered_files"

# XFS Undelete tool path
# Update this if you installed xfs_undelete in a different location:
XFS_UNDELETE_PATH="/root/xfs_undelete-12.1/xfs_undelete"

# Optional: Uncomment to delete .matroska files after recovery
#DELETE_MATROSKA=true