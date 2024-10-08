#!/bin/bash

# Base directories inside the container
RECOVERED_BASE_DIR="/input"
PROCESSED_BASE_DIR="/output"

# Array of disk IDs
DISK_IDS=(
  "DISK1"
  "DISK2"
  "DISK3"
)

# Loop through each disk ID to process images
for DISK_ID in "${DISK_IDS[@]}"; do
  echo "Processing images for disk $DISK_ID..."

  RECOVERED_DIR="$RECOVERED_BASE_DIR/$DISK_ID"
  PROCESSED_DIR="$PROCESSED_BASE_DIR/$DISK_ID"

  # Process JPEG images
  find "$RECOVERED_DIR" -type f \( -iname '*.jpg' -o -iname '*.jpeg' \) -exec sh -c '
    for file do
      output_file="$3${file#$2}"
      mkdir -p "$(dirname "$output_file")"
      if jpegtran -copy all -optimize -perfect "$file" > "$output_file"; then
        echo "Processed JPEG $output_file"
      else
        rm "$output_file"
        echo "Failed to process JPEG $file"
      fi
    done
  ' sh {} + "$RECOVERED_DIR" "$PROCESSED_DIR"

  # Process PNG images
  find "$RECOVERED_DIR" -type f -iname '*.png' -exec sh -c '
    for file do
      output_file="$3${file#$2}"
      mkdir -p "$(dirname "$output_file")"
      cp "$file" "$output_file"
      if pngcrush -q -ow "$output_file"; then
        echo "Processed PNG $output_file"
      else
        rm "$output_file"
        echo "Failed to process PNG $file"
      fi
    done
  ' sh {} + "$RECOVERED_DIR" "$PROCESSED_DIR"

  # Process GIF images
  find "$RECOVERED_DIR" -type f -iname '*.gif' -exec sh -c '
    for file do
      output_file="$3${file#$2}"
      mkdir -p "$(dirname "$output_file")"
      cp "$file" "$output_file"
      if gifsicle --batch "$output_file"; then
        echo "Processed GIF $output_file"
      else
        rm "$output_file"
        echo "Failed to process GIF $file"
      fi
    done
  ' sh {} + "$RECOVERED_DIR" "$PROCESSED_DIR"

  echo "Completed processing images for disk $DISK_ID."
done
