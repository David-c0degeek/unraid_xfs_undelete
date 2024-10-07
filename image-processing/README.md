# Image Post-Processing for XFS Undelete

This directory contains tools and instructions for post-processing large images recovered using the XFS Undelete script. The post-processing aims to reduce the file size of excessively large recovered images while maintaining quality.

## Features

- Processes JPEG, PNG, and GIF images
- Uses Docker to ensure all required tools are available
- Preserves metadata and directory structure
- Handles multiple disk IDs

## Prerequisites

- Docker installed on your Unraid server
- Recovered images from the XFS Undelete process

## Quick Start

1. Follow the setup instructions in [Docker Setup and Usage Guide](docs/docker_setup_and_usage.md).
2. Run the image processing script inside the Docker container.

## Security Note

This process involves handling potentially sensitive recovered data. Ensure you have appropriate permissions and security measures in place when processing recovered files.

## Contributing

Contributions to improve the image processing functionality are welcome. Please submit pull requests or open issues in the main repository.