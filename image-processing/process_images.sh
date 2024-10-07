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