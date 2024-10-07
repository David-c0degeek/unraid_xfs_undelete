# XFS Undelete for Unraid

This project provides scripts and documentation for recovering deleted files from encrypted and unencrypted XFS filesystems on Unraid servers, as well as post-processing recovered images.

## Features

- Recovers deleted files from XFS filesystems
- Supports both encrypted and unencrypted disks
- Optional image post-processing to optimize large recovered images

## Quick Start

1. Clone this repository to your Unraid server.
2. Follow the installation instructions in `docs/installation.md`.
3. Copy `examples/example_config.sh` to `config.sh` and customize it for your setup.
   - **Important:** Update disk identifiers and paths to match your system.
   - Choose your preferred password handling method (prompt or script).
4. Run the recovery script:
   ```
   ./recover_deleted_files.sh
   ```
5. (Optional) For image post-processing, follow the instructions in `image-processing/docs/docker_setup_and_usage.md`.

## Configuration

The script uses a configuration file (`config.sh`) to set various parameters. You must customize this file to match your specific Unraid setup, including:

- Disk identifiers and device paths
- Output directory for recovered files (very important to set this correctly)
- Time range for file recovery
- File types to recover
- Password handling method (prompt or script)

See `examples/example_config.sh` for a template and `docs/usage.md` for detailed instructions on how to customize each setting, especially the output directory.

## Why Image Post-Processing?

After recovering deleted files, you may find that some image files are unusually large, even though they can be opened and viewed correctly. This is because file recovery tools like `xfs_undelete` may not always know the exact end of a file, leading to the inclusion of extra data beyond the actual image content.

Image post-processing aims to:
1. Extract the valid image data from these oversized files.
2. Remove the extraneous data appended during recovery.
3. Reduce the file sizes to their correct dimensions without losing image quality.

This process can significantly reduce storage requirements and make the recovered images easier to manage and use.

## Documentation

- [Installation Guide](docs/installation.md)
- [Usage Instructions](docs/usage.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Image Post-Processing Guide](image-processing/docs/docker_setup_and_usage.md)

## Security Warning

This script handles sensitive data, including encryption passwords. Use caution and ensure proper security measures are in place. The "prompt" password method is recommended for enhanced security.

## License

[MIT License](LICENSE)

## Contributing

Contributions are welcome! Please read our [Contributing Guide](CONTRIBUTING.md) for details on our code of conduct and the process for submitting pull requests.