# XFS Undelete for Unraid - Example Configuration

# Array of disks with device paths and disk IDs
# Format: "/dev/sdX1 DISK_ID"
DISKS=(
  "/dev/sdb1 ZL2KG9X9"
  "/dev/sdg1 ZL2KG6WF"
  "/dev/sdd1 WL2068SD"
  "/dev/sdf1 ZL2PFBXQ"
)

# Time range for file recovery
# Format: "YYYY-MM-DD..now" or "YYYY-MM-DD..YYYY-MM-DD"
TIME_RANGE="2023-01-01..now"

# File types to recover
# Use "*" for all files, or specify types like "image/*"
FILE_TYPES="*"

# Encryption password for the disks
# WARNING: Storing passwords in plain text is a security risk.
# Consider using a secure method to input the password at runtime.
ENCRYPTION_PASSWORD="YourEncryptionPassword"

# Output directory for recovered files
OUTPUT_DIR="/mnt/disks/ZVTDW2MH/recovered_files"

# XFS Undelete tool path
XFS_UNDELETE_PATH="/root/xfs_undelete-12.1/xfs_undelete"

# Optional: Uncomment to delete .matroska files after recovery
#DELETE_MATROSKA=true