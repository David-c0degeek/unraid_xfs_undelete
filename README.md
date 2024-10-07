# XFS Undelete for Unraid

This project provides a script and documentation for recovering deleted files from encrypted XFS filesystems on Unraid servers.

## Quick Start

1. Clone this repository to your Unraid server.
2. Follow the installation instructions in `docs/installation.md`.
3. Copy `examples/example_config.sh` to `config.sh` and customize it for your setup.
   - **Important:** Update disk identifiers and paths to match your system.
   - Choose your preferred password handling method (prompt or script).
4. Run the script:
   ```
   ./recover_deleted_files.sh
   ```

## Configuration

The script uses a configuration file (`config.sh`) to set various parameters. You must customize this file to match your specific Unraid setup, including:

- Disk identifiers and device paths
- Output directory for recovered files
- Time range for file recovery
- File types to recover
- Password handling method (prompt or script)

See `examples/example_config.sh` for a template and `docs/usage.md` for detailed instructions.

## Documentation

- [Installation Guide](docs/installation.md)
- [Usage Instructions](docs/usage.md)
- [Troubleshooting](docs/troubleshooting.md)

## Security Warning

This script handles sensitive data, including encryption passwords. Use caution and ensure proper security measures are in place. The "prompt" password method is recommended for enhanced security.

## License

[MIT License](LICENSE)

## Contributing

Contributions are welcome! Please read our [Contributing Guide](CONTRIBUTING.md) for details on our code of conduct and the process for submitting pull requests.