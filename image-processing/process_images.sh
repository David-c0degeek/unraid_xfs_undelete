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

# Log files
ERROR_LOG="/app/error_log.txt"
PROCESS_LOG="/app/process_log.txt"
SUMMARY_LOG="/app/summary_log.txt"

# Function to handle existing log files
handle_existing_logs() {
    local log_file="$1"
    if [ -f "$log_file" ]; then
        local timestamp=$(date "+%Y%m%d_%H%M%S")
        local backup_file="${log_file%.txt}_${timestamp}.txt"
        mv "$log_file" "$backup_file"
        echo "Existing log file backed up to $backup_file"
    fi
    touch "$log_file"
    chmod 644 "$log_file"
}

# Handle existing log files
handle_existing_logs "$ERROR_LOG"
handle_existing_logs "$PROCESS_LOG"
handle_existing_logs "$SUMMARY_LOG"

# Logging function
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] [$level] $message" | tee -a "$PROCESS_LOG"
    case "$level" in
        ERROR)
            echo "[$timestamp] $message" >> "$ERROR_LOG"
            ;;
        SUMMARY)
            echo "[$timestamp] $message" >> "$SUMMARY_LOG"
            ;;
    esac
}

# Function to process JPEG files
process_jpeg() {
    local file="$1"
    local output_file="$2"
    local disk_id="$3"
    
    if [ -f "$output_file" ]; then
        log_message "INFO" "Skipping already processed JPEG $output_file"
        return 1
    fi
    if ! identify -format "%m" "$file" &>/dev/null; then
        log_message "ERROR" "Corrupt JPEG file detected: $file"
        return 2
    fi
    mkdir -p "$(dirname "$output_file")"
    if timeout 60s jpegtran -copy all -optimize -perfect "$file" > "$output_file" 2>/dev/null; then
        log_message "INFO" "Processed JPEG $output_file"
        return 0
    else
        rm -f "$output_file"
        log_message "ERROR" "Failed to process or timed out JPEG $file"
        return 2
    fi
}

# Function to process PNG files
process_png() {
    local file="$1"
    local output_file="$2"
    local disk_id="$3"
    
    if [ -f "$output_file" ]; then
        log_message "INFO" "Skipping already processed PNG $output_file"
        return 1
    fi
    if ! pngcheck "$file" &>/dev/null; then
        log_message "ERROR" "Corrupt PNG file detected: $file"
        return 2
    fi
    mkdir -p "$(dirname "$output_file")"
    cp "$file" "$output_file"
    if timeout 60s pngcrush -q -ow "$output_file" 2>/dev/null; then
        log_message "INFO" "Processed PNG $output_file"
        return 0
    else
        rm -f "$output_file"
        log_message "ERROR" "Failed to process or timed out PNG $file"
        return 2
    fi
}

# Function to process GIF files
process_gif() {
    local file="$1"
    local output_file="$2"
    local disk_id="$3"
    
    if [ -f "$output_file" ]; then
        log_message "INFO" "Skipping already processed GIF $output_file"
        return 1
    fi
    if ! gifsicle --info "$file" &>/dev/null; then
        log_message "ERROR" "Corrupt GIF file detected: $file"
        return 2
    fi
    mkdir -p "$(dirname "$output_file")"
    cp "$file" "$output_file"
    if timeout 60s gifsicle --batch "$output_file" 2>/dev/null; then
        log_message "INFO" "Processed GIF $output_file"
        return 0
    else
        rm -f "$output_file"
        log_message "ERROR" "Failed to process or timed out GIF $file"
        return 2
    fi
}

# Export functions so they're available in subshells
export -f log_message process_jpeg process_png process_gif

# Main processing loop
for DISK_ID in "${DISK_IDS[@]}"; do
    RECOVERED_DIR="$RECOVERED_BASE_DIR/$DISK_ID"
    PROCESSED_DIR="$PROCESSED_BASE_DIR/$DISK_ID"

    if [ ! -d "$RECOVERED_DIR" ]; then
        log_message "ERROR" "Input directory $RECOVERED_DIR does not exist. Skipping disk $DISK_ID."
        continue
    fi

    log_message "INFO" "Starting processing for disk $DISK_ID"

    # Initialize counters
    total_files=0
    processed_files=0
    skipped_files=0
    error_files=0

    # Process JPEG images
    log_message "INFO" "Processing JPEG files for disk $DISK_ID"
    while IFS= read -r -d '' file; do
        ((total_files++))
        output_file="$PROCESSED_DIR${file#$RECOVERED_DIR}"
        process_jpeg "$file" "$output_file" "$DISK_ID"
        case $? in
            0) ((processed_files++));;
            1) ((skipped_files++));;
            2) ((error_files++));;
        esac
        if ((processed_files % 100 == 0)); then
            log_message "INFO" "Progress: Processed $processed_files JPEG files for disk $DISK_ID"
        fi
    done < <(find "$RECOVERED_DIR" -type f \( -iname "*.jpg" -o -iname "*.jpeg" \) -print0)

    # Process PNG images
    log_message "INFO" "Processing PNG files for disk $DISK_ID"
    while IFS= read -r -d '' file; do
        ((total_files++))
        output_file="$PROCESSED_DIR${file#$RECOVERED_DIR}"
        process_png "$file" "$output_file" "$DISK_ID"
        case $? in
            0) ((processed_files++));;
            1) ((skipped_files++));;
            2) ((error_files++));;
        esac
        if ((processed_files % 100 == 0)); then
            log_message "INFO" "Progress: Processed $processed_files PNG files for disk $DISK_ID"
        fi
    done < <(find "$RECOVERED_DIR" -type f -iname "*.png" -print0)

    # Process GIF images
    log_message "INFO" "Processing GIF files for disk $DISK_ID"
    while IFS= read -r -d '' file; do
        ((total_files++))
        output_file="$PROCESSED_DIR${file#$RECOVERED_DIR}"
        process_gif "$file" "$output_file" "$DISK_ID"
        case $? in
            0) ((processed_files++));;
            1) ((skipped_files++));;
            2) ((error_files++));;
        esac
        if ((processed_files % 100 == 0)); then
            log_message "INFO" "Progress: Processed $processed_files GIF files for disk $DISK_ID"
        fi
    done < <(find "$RECOVERED_DIR" -type f -iname "*.gif" -print0)

    # Log summary for this disk
    log_message "SUMMARY" "Disk $DISK_ID processing complete. Total files: $total_files, Processed: $processed_files, Skipped: $skipped_files, Errors: $error_files"
done

log_message "SUMMARY" "All processing completed."
