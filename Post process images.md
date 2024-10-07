Certainly! Here is the entire guide formatted in Markdown for you to copy-paste into your editor.

---

# Using Docker Containers with the Required Tools

Unraid has excellent Docker support, and using a Docker container is a clean and efficient way to run applications with dependencies that are not available on your host system.

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

- This Dockerfile uses Ubuntu 20.04 as the base image and installs `jpegtran`, `pngcrush`, and `gifsicle`.

#### e. Save and Exit the Editor

- Press `Ctrl+O`, `Enter` to save, then `Ctrl+X` to exit.

#### f. Build the Docker Image

```bash
docker build -t image_processor:latest .
```

- This command builds a Docker image named `image_processor`.

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

#### b. Add the Adjusted Script Content

```bash
#!/bin/bash

# Base directories inside the container
RECOVERED_BASE_DIR="/input"
PROCESSED_BASE_DIR="/output"

# Array of disk IDs
DISK_IDS=(
  "ZL2KG9X9"
  "ZL2KG6WF"
  "WL2068SD"
  "ZL2PFBXQ"
)

# Ensure the processed base directory exists
mkdir -p "$PROCESSED_BASE_DIR"

# Loop through each disk ID to process images
for DISK_ID in "${DISK_IDS[@]}"; do
  echo "Processing images for disk $DISK_ID..."

  # Directories for recovered and processed files for this disk
  RECOVERED_DIR="$RECOVERED_BASE_DIR/$DISK_ID"
  PROCESSED_DIR="$PROCESSED_BASE_DIR/$DISK_ID"

  # Ensure the processed directory exists
  mkdir -p "$PROCESSED_DIR"

  # Process JPEG images
  find "$RECOVERED_DIR" -type f \( -iname '*.jpg' -o -iname '*.jpeg' \) | while read -r file; do
    # Output file path in the processed directory
    output_file="$PROCESSED_DIR${file#$RECOVERED_DIR}"
    output_dir="$(dirname "$output_file")"

    # Ensure the output directory exists
    mkdir -p "$output_dir"

    # Process the image, preserving metadata
    jpegtran -copy all -optimize -perfect "$file" > "$output_file"
    if [ $? -eq 0 ]; then
      echo "Processed JPEG $output_file"
    else
      rm "$output_file"
      echo "Failed to process JPEG $file"
    fi
  done

  # Process PNG images
  find "$RECOVERED_DIR" -type f -iname '*.png' | while read -r file; do
    # Output file path in the processed directory
    output_file="$PROCESSED_DIR${file#$RECOVERED_DIR}"
    output_dir="$(dirname "$output_file")"

    # Ensure the output directory exists
    mkdir -p "$output_dir"

    # Process the image, preserving metadata
    cp "$file" "$output_file"
    pngcrush -q -ow "$output_file"
    echo "Processed PNG $output_file"
  done

  # Process GIF images
  find "$RECOVERED_DIR" -type f -iname '*.gif' | while read -r file; do
    # Output file path in the processed directory
    output_file="$PROCESSED_DIR${file#$RECOVERED_DIR}"
    output_dir="$(dirname "$output_file")"

    # Ensure the output directory exists
    mkdir -p "$output_dir"

    # Process the image, preserving metadata
    cp "$file" "$output_file"
    gifsicle --batch "$output_file"
    echo "Processed GIF $output_file"
  done

  echo "Completed processing images for disk $DISK_ID."
done
```

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

---