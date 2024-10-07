# Installation Guide

## Prerequisites

- Unraid server
- Root access to the server
- Nerd Tools plugin installed

## Steps

1. Install required tools:
   ```bash
   # Install tcl and tcllib using Nerd Tools
   # Go to Settings > Nerd Tools
   # Enable tcl and tcllib
   # Click Apply
   ```

2. Download and prepare xfs_undelete:
   ```bash
   cd /root/
   wget https://github.com/ianka/xfs_undelete/archive/refs/tags/v12.1.zip -O xfs_undelete.zip
   unzip xfs_undelete.zip
   cd xfs_undelete-12.1/
   ```

3. Verify installation:
   ```bash
   ./xfs_undelete --help
   ```

4. Clone this repository:
   ```bash
   git clone https://github.com/yourusername/xfs-undelete-unraid.git
   cd xfs-undelete-unraid
   ```

5. Configure the script:
   ```bash
   cp examples/example_config.sh config.sh
   nano config.sh  # Edit the configuration as needed
   ```

6. Make the script executable:
   ```bash
   chmod +x recover_deleted_files.sh
   ```

You're now ready to use the script. Refer to the [Usage Guide](usage.md) for next steps.