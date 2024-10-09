#!/bin/bash

# Base directories inside the container
RECOVERED_BASE_DIR="/input"
PROCESSED_BASE_DIR="/output"

# Array of disk IDs
DISK_IDS=(
  "DISK1"
  "DISK2"
  "DISK3"
  "DISK4"
)

# Error log file
ERROR_LOG="/app/error_log.txt"
touch "$ERROR_LOG"
chmod 644 "$ERROR_LOG"

# Loop through each disk ID to process images
for DISK_ID in "${DISK_IDS[@]}"; do
  echo "Processing images for disk $DISK_ID..."

  RECOVERED_DIR="$RECOVERED_BASE_DIR/$DISK_ID"
  PROCESSED_DIR="$PROCESSED_BASE_DIR/$DISK_ID"

  # Process JPEG images
  find "$RECOVERED_DIR" -type f \( -iname '*.jpg' -o -iname '*.jpeg' \) -exec sh -c '
    for file do
      output_file="$3${file#$2}"
      if [ -f "$output_file" ]; then
        echo "Skipping already processed JPEG $output_file"
        continue
      fi
      mkdir -p "$(dirname "$output_file")"
      if timeout 30s jpegtran -copy all -optimize -perfect "$file" > "$output_file"; then
        echo "Processed JPEG $output_file"
      else
        rm "$output_file"
        echo "Failed to process or timed out JPEG $file" | tee -a "$ERROR_LOG"
      fi
    done
  ' sh {} + "$RECOVERED_DIR" "$PROCESSED_DIR"

  # Process PNG images
  find "$RECOVERED_DIR" -type f -iname '*.png' -exec sh -c '
    for file do
      output_file="$3${file#$2}"
      if [ -f "$output_file" ]; then
        echo "Skipping already processed PNG $output_file"
        continue
      fi
      mkdir -p "$(dirname "$output_file")"
      cp "$file" "$output_file"
      if timeout 30s pngcrush -q -ow "$output_file"; then
        echo "Processed PNG $output_file"
      else
        rm "$output_file"
        echo "Failed to process or timed out PNG $file" | tee -a "$ERROR_LOG"
      fi
    done
  ' sh {} + "$RECOVERED_DIR" "$PROCESSED_DIR"

  # Process GIF images
  find "$RECOVERED_DIR" -type f -iname '*.gif' -exec sh -c '
    for file do
      output_file="$3${file#$2}"
      if [ -f "$output_file" ]; then
        echo "Skipping already processed GIF $output_file"
        continue
      fi
      mkdir -p "$(dirname "$output_file")"
      cp "$file" "$output_file"
      if timeout 30s gifsicle --batch "$output_file"; then
        echo "Processed GIF $output_file"
      else
        rm "$output_file"
        echo "Failed to process or timed out GIF $file" | tee -a "$ERROR_LOG"
      fi
    done
  ' sh {} + "$RECOVERED_DIR" "$PROCESSED_DIR"

  echo "Completed processing images for disk $DISK_ID."
done
