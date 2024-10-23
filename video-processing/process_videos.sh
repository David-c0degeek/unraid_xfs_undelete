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
ERROR_LOG="/app/video_error_log.txt"
PROCESS_LOG="/app/video_process_log.txt"
SUMMARY_LOG="/app/video_summary_log.txt"

# Video processing settings
VIDEO_TIMEOUT=3600     # 1 hour timeout for video processing
CONCURRENT_JOBS=2      # Number of concurrent video processing jobs

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

# Function to get video information
get_video_info() {
    local file="$1"
    if ! ffprobe -v quiet -print_format json -show_format -show_streams "$file" 2>/dev/null; then
        return 1
    fi
    return 0
}

# Function to process video files
process_video() {
    local file="$1"
    local output_file="$2"
    local disk_id="$3"
    
    if [ -f "$output_file" ]; then
        log_message "INFO" "Skipping already processed video $output_file"
        return 1
    fi

    # Check if input file is valid
    if ! get_video_info "$file" > /dev/null; then
        log_message "ERROR" "Corrupt or invalid video file detected: $file"
        return 2
    fi

    mkdir -p "$(dirname "$output_file")"
    
    # Get input video information
    local input_info=$(ffprobe -v quiet -print_format json -show_streams -show_format "$file")
    local input_codec=$(echo "$input_info" | jq -r '.streams[0].codec_name')
    local input_width=$(echo "$input_info" | jq -r '.streams[0].width')
    local input_height=$(echo "$input_info" | jq -r '.streams[0].height')
    
    # If input is already H.264 and not corrupted, just copy it
    if [[ "$input_codec" == "h264" ]] && ffmpeg -v error -i "$file" -f null - 2>/dev/null; then
        log_message "INFO" "Input is already H.264 and valid, copying: $file"
        cp "$file" "$output_file"
        return 0
    fi
    
    # Process with FFmpeg using maximum quality settings
    if timeout "$VIDEO_TIMEOUT" ffmpeg -i "$file" \
        -c:v libx264 \
        -preset veryslow \
        -crf 18 \
        -profile:v high \
        -level 4.2 \
        -pix_fmt yuv420p \
        -c:a aac \
        -b:a 384k \
        -ar 48000 \
        -movflags +faststart \
        -y "$output_file" 2>/dev/null; then
        
        log_message "INFO" "Processed video $output_file"
        
        # Log compression results
        local input_size=$(du -h "$file" | cut -f1)
        local output_size=$(du -h "$output_file" | cut -f1)
        log_message "INFO" "Size change for $file: $input_size -> $output_size"
        
        return 0
    else
        rm -f "$output_file"
        log_message "ERROR" "Failed to process or timed out video $file"
        return 2
    fi
}

# Export functions so they're available in subshells
export -f log_message process_video get_video_info
export VIDEO_TIMEOUT

# Main processing loop
for DISK_ID in "${DISK_IDS[@]}"; do
    RECOVERED_DIR="$RECOVERED_BASE_DIR/$DISK_ID"
    PROCESSED_DIR="$PROCESSED_BASE_DIR/$DISK_ID"

    if [ ! -d "$RECOVERED_DIR" ]; then
        log_message "ERROR" "Input directory $RECOVERED_DIR does not exist. Skipping disk $DISK_ID."
        continue
    fi

    log_message "INFO" "Starting video processing for disk $DISK_ID"

    # Initialize counters
    total_files=0
    processed_files=0
    skipped_files=0
    error_files=0

    # Process video files
    log_message "INFO" "Processing video files for disk $DISK_ID"
    while IFS= read -r -d '' file; do
        ((total_files++))
        output_file="$PROCESSED_DIR${file#$RECOVERED_DIR}"
        
        # Run video processing with parallel
        echo "$file" | parallel -j "$CONCURRENT_JOBS" process_video {} "$output_file" "$DISK_ID"
        case $? in
            0) ((processed_files++));;
            1) ((skipped_files++));;
            2) ((error_files++));;
        esac
        
        if ((processed_files % 10 == 0)); then
            log_message "INFO" "Progress: Processed $processed_files video files for disk $DISK_ID"
        fi
    done < <(find "$RECOVERED_DIR" -type f \( -iname "*.mp4" -o -iname "*.avi" -o -iname "*.mov" -o -iname "*.mkv" \) -print0)

    # Log summary for this disk
    log_message "SUMMARY" "Disk $DISK_ID video processing complete. Total files: $total_files, Processed: $processed_files, Skipped: $skipped_files, Errors: $error_files"
done

log_message "SUMMARY" "All video processing completed."
