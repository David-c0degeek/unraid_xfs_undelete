# XFS Undelete for Unraid - Example Configuration

# IMPORTANT: This is an example configuration. You MUST modify these values to match your specific setup.

# Array of disks with device paths and disk IDs
# Format: "/dev/sdX1 DISK_ID"
# CUSTOMIZE THESE VALUES for your specific disks:
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

# Encryption password handling
# Set to "prompt" to be asked for the password at runtime (more secure)
# Set to "script" to use the password defined below (less secure)
PASSWORD_METHOD="prompt"

# Encryption password for the disks (used if PASSWORD_METHOD is "script")
# WARNING: Storing passwords in plain text is a security risk.
# Only use this method if you understand and accept the security implications.
ENCRYPTION_PASSWORD="YourEncryptionPassword"

# Output directory for recovered files
# CUSTOMIZE THIS PATH to match your desired output location:
OUTPUT_BASE_DIR="/mnt/disks/ZVTDW2MH/recovered_files"

# XFS Undelete tool path
# Update this if you installed xfs_undelete in a different location:
XFS_UNDELETE_PATH="/root/xfs_undelete-12.1/xfs_undelete"

# Optional: Uncomment to delete .matroska files after recovery
#DELETE_MATROSKA=true