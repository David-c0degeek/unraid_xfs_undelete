# Image Post-Processing for XFS Undelete

This directory contains tools and instructions for post-processing large images recovered using the XFS Undelete script. The post-processing aims to reduce the file size of excessively large recovered images while maintaining quality.

## Why Post-Processing is Necessary

After recovering deleted images, you may encounter files that are unusually large, even though they can be opened and viewed correctly. This occurs because:

1. File recovery tools like `xfs_undelete` may not always determine the exact end of a file.
2. Extra data beyond the actual image content might be included during recovery.
3. This extraneous data inflates file sizes without adding value to the image.

## Solution Overview

The post-processing addresses these issues by:

1. Identifying the End of Valid Image Data: We detect where the actual image data ends using image file markers.
2. Trimming the Files Accordingly: We truncate the files at the correct point to remove the extra data.
3. Automating the Process: We use scripts to process all affected files efficiently.

## Features

- Processes JPEG, PNG, and GIF images
- Uses Docker to ensure all required tools are available
- Preserves metadata and directory structure
- Handles multiple disk IDs
- Significantly reduces file sizes without compromising image quality

## Technical Process

### JPEG Files
- Structure: JPEG files have well-defined markers (Start of Image: FFD8, End of Image: FFD9)
- Method: We use `jpegtran` to create a clean version of the file, stopping at the EOI marker

### PNG Files
- Structure: PNG files have a specific end marker (IEND chunk)
- Method: We use `pngfix` to process and optimize the PNG files

### GIF Files
- Structure: GIF files end with a trailer byte (0x3B)
- Method: We truncate the file at the trailer byte

## Prerequisites

- Docker installed on your Unraid server
- Recovered images from the XFS Undelete process

## Quick Start

1. Follow the setup instructions in [Docker Setup and Usage Guide](docs/docker_setup_and_usage.md).
2. Run the image processing script inside the Docker container.

## What to Expect

After processing, you should see:
- Reduced file sizes for most images
- Preserved image quality and viewability
- Maintained directory structure and file names
- Potential significant savings in storage space

## Security Note

This process involves handling potentially sensitive recovered data. Ensure you have appropriate permissions and security measures in place when processing recovered files.

## Contributing

Contributions to improve the image processing functionality are welcome. Please submit pull requests or open issues in the main repository.

## Troubleshooting

If you encounter any issues during post-processing, refer to the [Troubleshooting](../docs/troubleshooting.md) guide in the main documentation.

## Important Note

Always create a backup of your recovered files before running any post-processing scripts. This ensures you have a fallback in case of any unexpected issues.