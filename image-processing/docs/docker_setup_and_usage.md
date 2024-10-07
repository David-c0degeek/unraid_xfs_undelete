# Using Docker Containers for Image Processing

This guide explains how to set up and use a Docker container for post-processing images recovered by the XFS Undelete script on Unraid.

## Steps to Set Up and Use a Docker Container

### 1. Create a Custom Docker Image with Required Tools

#### a. Access Your Unraid Server via SSH or Terminal

- Open the Unraid web UI and go to **Tools** > **Terminal** to open a terminal session.

#### b. Create a Directory for the Docker Build

```bash
mkdir -p /boot/config/docker_build
cd /boot/config/docker_build
```

#### c. Create a Dockerfile

```bash
nano Dockerfile
```

#### d. Add the Following Content to the Dockerfile

```Dockerfile
FROM ubuntu:20.04

RUN apt-get update && apt-get install -y \
    libjpeg-turbo-progs \
    pngcrush \
    gifsicle \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
```

#### e. Save and Exit the Editor

- Press `Ctrl+O`, `Enter` to save, then `Ctrl+X` to exit.

#### f. Build the Docker Image

```bash
docker build -t image_processor:latest .
```

### 2. Set Up the Docker Container in Unraid

#### a. Go to the Docker Tab in the Unraid Web Interface

- Navigate to **Docker** > **Add Container**.

#### b. Configure the Docker Container

- **Name:** `image_processor`
- **Repository:** `image_processor:latest`
- **Console shell command:** `/bin/bash`
- **Network Type:** `None` (since network access isn't required)
- **Volume Mappings:**
  - **Add Path:**
    - **Container Path:** `/input`
    - **Host Path:** `/mnt/disks/ZVTDW2MH/recovered_files`
  - **Add Path:**
    - **Container Path:** `/output`
    - **Host Path:** `/mnt/disks/ZVTDW2MH/processed_images`
- **CPU and Memory Limitations:** Adjust if necessary.
- Click **Apply** to create and start the container.

### 3. Access the Container's Console

- In the **Docker** tab, find the `image_processor` container.
- Click on the container's icon and select **Console**.

### 4. Prepare the Processing Script Inside the Container

#### a. Inside the Container's Console, Create the Processing Script

```bash
nano /app/process_images.sh
```

#### b. Add the Script Content

Copy and paste the content of the `process_images.sh` file into this file.

#### c. Save and Exit the Editor

- Press `Ctrl+O`, `Enter` to save, then `Ctrl+X` to exit.

#### d. Make the Script Executable

```bash
chmod +x /app/process_images.sh
```

### 5. Run the Processing Script

```bash
/app/process_images.sh
```

- This command will process the images from the recovered files directory and output them to the processed images directory, maintaining the same directory structure and preserving metadata.

### 6. Monitor the Output

- The script will display messages indicating the progress and any errors encountered.

## Benefits of Using a Docker Container

- **Isolation:** The tools run in an isolated environment without affecting the host system.
- **No Dependency Conflicts:** All dependencies are contained within the Docker image.
- **Reusability:** You can reuse the container for similar tasks in the future.

## Customization

- You can modify the `DISK_IDS` array in the `process_images.sh` script to match your specific disk IDs.
- Adjust the input and output paths in the Docker container configuration if your recovered files are stored in a different location.

## Troubleshooting

- If you encounter permission issues, ensure that the Docker container has the necessary permissions to read from the input directory and write to the output directory.
- For any other issues, check the console output for error messages and refer to the main troubleshooting guide.