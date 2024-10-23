# Video Processing Script for Windows
param (
    [string]$InputPath = ".\input",
    [string]$OutputPath = ".\output"
)

# Initialize logging
$ErrorLogPath = ".\video_error_log.txt"
$ProcessLogPath = ".\video_process_log.txt"
$SummaryLogPath = ".\video_summary_log.txt"

# Video processing settings
$VideoTimeout = 3600  # 1 hour timeout
$MaxJobs = 2         # Number of concurrent jobs

# Create output directory if it doesn't exist
New-Item -ItemType Directory -Force -Path $OutputPath | Out-Null

# Function to handle existing logs
function Initialize-LogFile {
    param (
        [string]$LogPath
    )
    
    if (Test-Path $LogPath) {
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $backupPath = [System.IO.Path]::ChangeExtension($LogPath, ".$timestamp.txt")
        Move-Item -Path $LogPath -Destination $backupPath
        Write-Host "Existing log file backed up to $backupPath"
    }
    New-Item -ItemType File -Force -Path $LogPath | Out-Null
}

# Initialize log files
Initialize-LogFile -LogPath $ErrorLogPath
Initialize-LogFile -LogPath $ProcessLogPath
Initialize-LogFile -LogPath $SummaryLogPath

# Logging function
function Write-LogMessage {
    param (
        [string]$Level,
        [string]$Message
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    Write-Host $logMessage
    Add-Content -Path $ProcessLogPath -Value $logMessage
    
    switch ($Level) {
        "ERROR" {
            Add-Content -Path $ErrorLogPath -Value "[$timestamp] $Message"
        }
        "SUMMARY" {
            Add-Content -Path $SummaryLogPath -Value "[$timestamp] $Message"
        }
    }
}

# Function to check if FFmpeg exists
function Test-FFmpeg {
    try {
        $null = & ffmpeg -version
        $null = & ffprobe -version
        return $true
    }
    catch {
        Write-LogMessage -Level "ERROR" -Message "FFmpeg/FFprobe not found in PATH. Please install FFmpeg and add it to your system PATH."
        return $false
    }
}

# Function to get video information
function Get-VideoInfo {
    param (
        [string]$FilePath
    )
    
    try {
        $info = & ffprobe -v quiet -print_format json -show_format -show_streams "$FilePath" 2>$null
        return $info | ConvertFrom-Json
    }
    catch {
        return $null
    }
}

# Function to process a single video file
function Process-Video {
    param (
        [string]$InputFile,
        [string]$OutputFile
    )
    
    # Create output directory if it doesn't exist
    $outputDir = Split-Path -Parent $OutputFile
    if (-not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
    }
    
    # Skip if output already exists
    if (Test-Path $OutputFile) {
        Write-LogMessage -Level "INFO" -Message "Skipping already processed video: $OutputFile"
        return 1
    }
    
    # Check if input file is valid
    $videoInfo = Get-VideoInfo -FilePath $InputFile
    if (-not $videoInfo) {
        Write-LogMessage -Level "ERROR" -Message "Corrupt or invalid video file detected: $InputFile"
        return 2
    }
    
    # Check if input is already H.264 and not corrupted
    $inputCodec = $videoInfo.streams[0].codec_name
    if ($inputCodec -eq "h264") {
        try {
            & ffmpeg -v error -i "$InputFile" -f null - 2>$null
            Write-LogMessage -Level "INFO" -Message "Input is already H.264 and valid, copying: $InputFile"
            Copy-Item -Path $InputFile -Destination $OutputFile -Force
            return 0
        }
        catch {
            # If validation fails, continue with processing
        }
    }
    
    # Process with FFmpeg
    try {
        $process = Start-Process -FilePath "ffmpeg" -ArgumentList @(
            "-i", "`"$InputFile`"",
            "-c:v", "libx264",
            "-preset", "veryslow",
            "-crf", "18",
            "-profile:v", "high",
            "-level", "4.2",
            "-pix_fmt", "yuv420p",
            "-c:a", "aac",
            "-b:a", "384k",
            "-ar", "48000",
            "-movflags", "+faststart",
            "-y",
            "`"$OutputFile`""
        ) -NoNewWindow -PassThru -Wait
        
        if ($process.ExitCode -eq 0) {
            $inputSize = [math]::Round((Get-Item "$InputFile").Length / 1MB, 2)
            $outputSize = [math]::Round((Get-Item "$OutputFile").Length / 1MB, 2)
            Write-LogMessage -Level "INFO" -Message "Processed video: $(Split-Path $OutputFile -Leaf)"
            Write-LogMessage -Level "INFO" -Message "Size change: ${inputSize}MB -> ${outputSize}MB for $(Split-Path $InputFile -Leaf)"
            return 0
        }
        else {
            if (Test-Path $OutputFile) {
                Remove-Item -Path $OutputFile -Force
            }
            Write-LogMessage -Level "ERROR" -Message "Failed to process video: $(Split-Path $InputFile -Leaf)"
            return 2
        }
    }
    catch {
        if (Test-Path $OutputFile) {
            Remove-Item -Path $OutputFile -Force
        }
        Write-LogMessage -Level "ERROR" -Message "Error processing video: $(Split-Path $InputFile -Leaf) - $($_.Exception.Message)"
        return 2
    }
}

# Main processing function
function Start-VideoProcessing {
    # Check for FFmpeg
    if (-not (Test-FFmpeg)) {
        return
    }
    
    Write-LogMessage -Level "INFO" -Message "Starting video processing"
    
    # Initialize counters
    $totalFiles = 0
    $processedFiles = 0
    $skippedFiles = 0
    $errorFiles = 0
    
    # Get all video files
    $videoFiles = Get-ChildItem -Path $InputPath -Recurse -Include @("*.mp4", "*.avi", "*.mov", "*.mkv")
    $totalFiles = $videoFiles.Count
    
    Write-LogMessage -Level "INFO" -Message "Found $totalFiles video files to process"
    
    # Process files with job throttling
    $jobs = @()
    
    foreach ($file in $videoFiles) {
        $relativePath = $file.FullName.Substring($InputPath.Length)
        $outputFile = Join-Path $OutputPath $relativePath
        
        # Process video directly without jobs (simpler for Windows)
        $result = Process-Video -InputFile $file.FullName -OutputFile $outputFile
        
        switch ($result) {
            0 { $processedFiles++ }
            1 { $skippedFiles++ }
            2 { $errorFiles++ }
        }
        
        # Log progress every 5 files
        if (($processedFiles + $skippedFiles + $errorFiles) % 5 -eq 0) {
            Write-LogMessage -Level "INFO" -Message "Progress: $processedFiles processed, $skippedFiles skipped, $errorFiles failed"
        }
    }
    
    # Log final summary
    Write-LogMessage -Level "SUMMARY" -Message "Processing complete. Total files: $totalFiles, Processed: $processedFiles, Skipped: $skippedFiles, Errors: $errorFiles"
}

# Start the processing
Start-VideoProcessing
