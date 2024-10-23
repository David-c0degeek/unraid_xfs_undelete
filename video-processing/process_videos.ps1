# Video Processing Script for Windows
param (
    [string]$InputPath = ".\input",
    [string]$OutputPath = ".\output",
    [switch]$AttemptRecovery = $true  # Enable recovery attempts for corrupt files
)

# Initialize logging
$ErrorLogPath = ".\video_error_log.txt"
$ProcessLogPath = ".\video_process_log.txt"
$SummaryLogPath = ".\video_summary_log.txt"
$RecoveryLogPath = ".\recovery_log.txt"

# Video processing settings
$VideoTimeout = 3600  # 1 hour timeout
$MaxJobs = 2         # Number of concurrent jobs
$RecoveryAttempts = 2 # Number of recovery attempts with different methods

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
Initialize-LogFile -LogPath $RecoveryLogPath

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
        "RECOVERY" {
            Add-Content -Path $RecoveryLogPath -Value "[$timestamp] $Message"
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

# Function to validate video file and get codec info
function Test-VideoFile {
    param (
        [string]$FilePath
    )
    
    try {
        # First, check if we can read any stream info at all
        $probeOutput = & ffprobe -v error -of json -show_streams -i "$FilePath" 2>&1
        if ($LASTEXITCODE -ne 0) {
            return @{
                IsValid = $false
                CodecName = $null
                Error = "Failed to probe file"
                RequiresRecovery = $true
            }
        }

        # Try to parse the JSON output
        try {
            $videoInfo = $probeOutput | ConvertFrom-Json
        }
        catch {
            return @{
                IsValid = $false
                CodecName = $null
                Error = "Invalid probe output"
                RequiresRecovery = $true
            }
        }

        # Check if we have any streams
        if (-not $videoInfo -or -not $videoInfo.streams -or $videoInfo.streams.Count -eq 0) {
            return @{
                IsValid = $false
                CodecName = $null
                Error = "No streams found"
                RequiresRecovery = $true
            }
        }

        # Find the video stream
        $videoStream = $videoInfo.streams | Where-Object { $_.codec_type -eq "video" } | Select-Object -First 1
        if (-not $videoStream) {
            return @{
                IsValid = $false
                CodecName = $null
                Error = "No video stream found"
                RequiresRecovery = $false
            }
        }

        # Test if we can read the duration
        $duration = & ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$FilePath" 2>&1
        $requiresRecovery = ($LASTEXITCODE -ne 0 -or -not $duration -or $duration -eq "N/A")

        return @{
            IsValid = -not $requiresRecovery
            CodecName = $videoStream.codec_name
            Error = if ($requiresRecovery) { "Incomplete or corrupt file" } else { $null }
            RequiresRecovery = $requiresRecovery
        }
    }
    catch {
        return @{
            IsValid = $false
            CodecName = $null
            Error = $_.Exception.Message
            RequiresRecovery = $true
        }
    }
}

# Function to attempt video recovery
function Repair-Video {
    param (
        [string]$InputFile,
        [string]$OutputFile,
        [int]$AttemptNumber = 1
    )
    
    $fileName = Split-Path $InputFile -Leaf
    $tempOutput = "$OutputFile.repair$AttemptNumber.temp"
    
    try {
        Write-LogMessage -Level "RECOVERY" -Message "Attempting recovery method $AttemptNumber for: $fileName"
        
        # Different recovery methods based on attempt number
        switch ($AttemptNumber) {
            1 {
                # First attempt: Try to fix container without re-encoding
                $process = Start-Process -FilePath "ffmpeg" -ArgumentList @(
                    "-err_detect", "ignore_err",
                    "-i", "`"$InputFile`"",
                    "-c", "copy",
                    "-y",
                    "`"$tempOutput`""
                ) -NoNewWindow -PassThru -Wait -RedirectStandardError "$env:TEMP\ffmpeg_error.txt"
            }
            2 {
                # Second attempt: Try to recover with re-encoding
                $process = Start-Process -FilePath "ffmpeg" -ArgumentList @(
                    "-err_detect", "ignore_err",
                    "-i", "`"$InputFile`"",
                    "-c:v", "libx264",
                    "-preset", "medium",  # Faster preset for recovery
                    "-crf", "23",         # Lower quality for recovery
                    "-c:a", "aac",
                    "-y",
                    "`"$tempOutput`""
                ) -NoNewWindow -PassThru -Wait -RedirectStandardError "$env:TEMP\ffmpeg_error.txt"
            }
        }

        if ($process.ExitCode -eq 0 -and (Test-Path $tempOutput) -and (Get-Item $tempOutput).Length -gt 0) {
            # Verify the repaired file
            $verifyCheck = Test-VideoFile -FilePath $tempOutput
            if ($verifyCheck.IsValid) {
                Move-Item -Path $tempOutput -Destination $OutputFile -Force
                Write-LogMessage -Level "RECOVERY" -Message "Successfully recovered $fileName using method $AttemptNumber"
                return $true
            }
            else {
                Remove-Item -Path $tempOutput -Force
                Write-LogMessage -Level "RECOVERY" -Message "Recovery attempt $AttemptNumber failed verification for $fileName"
                return $false
            }
        }
        else {
            if (Test-Path $tempOutput) { Remove-Item -Path $tempOutput -Force }
            $errorContent = Get-Content "$env:TEMP\ffmpeg_error.txt" -Raw
            Write-LogMessage -Level "RECOVERY" -Message "Recovery attempt $AttemptNumber failed for $fileName`: $errorContent"
            return $false
        }
    }
    catch {
        if (Test-Path $tempOutput) { Remove-Item -Path $tempOutput -Force }
        Write-LogMessage -Level "RECOVERY" -Message "Exception during recovery attempt $AttemptNumber for $fileName`: $($_.Exception.Message)"
        return $false
    }
    finally {
        if (Test-Path "$env:TEMP\ffmpeg_error.txt") { Remove-Item "$env:TEMP\ffmpeg_error.txt" -Force }
    }
}

# Function to process video files
function Process-Video {
    param (
        [string]$InputFile,
        [string]$OutputFile
    )
    
    $fileName = Split-Path $InputFile -Leaf
    
    try {
        # Create output directory if it doesn't exist
        $outputDir = Split-Path -Parent $OutputFile
        if (-not (Test-Path $outputDir)) {
            New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
        }
        
        # Skip if output already exists
        if (Test-Path $OutputFile) {
            Write-LogMessage -Level "INFO" -Message "Skipping already processed video: $fileName"
            return 1
        }
        
        # Check if input file exists and is not empty
        if (-not (Test-Path $InputFile) -or (Get-Item $InputFile).Length -eq 0) {
            Write-LogMessage -Level "ERROR" -Message "Input file is missing or empty: $fileName"
            return 2
        }
        
        # Validate video file
        $videoCheck = Test-VideoFile -FilePath $InputFile
        
        if (-not $videoCheck.IsValid) {
            if ($AttemptRecovery -and $videoCheck.RequiresRecovery) {
                Write-LogMessage -Level "RECOVERY" -Message "Attempting recovery for corrupt file: $fileName"
                
                # Try each recovery method
                for ($i = 1; $i -le $RecoveryAttempts; $i++) {
                    if (Repair-Video -InputFile $InputFile -OutputFile $OutputFile -AttemptNumber $i) {
                        return 0  # Successfully recovered
                    }
                }
                
                Write-LogMessage -Level "ERROR" -Message "All recovery attempts failed for: $fileName"
                return 2
            }
            else {
                Write-LogMessage -Level "ERROR" -Message "Invalid or corrupt video file ($($videoCheck.Error)): $fileName"
                return 2
            }
        }
        
        # If input is already H.264 and valid, just copy
        if ($videoCheck.CodecName -eq "h264") {
            Write-LogMessage -Level "INFO" -Message "File is already H.264 and valid, copying: $fileName"
            Copy-Item -Path $InputFile -Destination $OutputFile -Force
            return 0
        }
        
        # Process with FFmpeg
        $tempOutput = "$OutputFile.temp"
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
            "`"$tempOutput`""
        ) -NoNewWindow -PassThru -Wait -RedirectStandardError "$env:TEMP\ffmpeg_error.txt"
        
        if ($process.ExitCode -eq 0 -and (Test-Path $tempOutput) -and (Get-Item $tempOutput).Length -gt 0) {
            Move-Item -Path $tempOutput -Destination $OutputFile -Force
            $inputSize = [math]::Round((Get-Item $InputFile).Length / 1MB, 2)
            $outputSize = [math]::Round((Get-Item $OutputFile).Length / 1MB, 2)
            Write-LogMessage -Level "INFO" -Message "Processed: $fileName"
            Write-LogMessage -Level "INFO" -Message "Size change for $fileName`: ${inputSize}MB -> ${outputSize}MB"
            return 0
        }
        else {
            $errorContent = Get-Content "$env:TEMP\ffmpeg_error.txt" -Raw
            Write-LogMessage -Level "ERROR" -Message "Failed to process $fileName`: $errorContent"
            if (Test-Path $tempOutput) { Remove-Item -Path $tempOutput -Force }
            if (Test-Path $OutputFile) { Remove-Item -Path $OutputFile -Force }
            return 2
        }
    }
    catch {
        Write-LogMessage -Level "ERROR" -Message "Exception processing $fileName`: $($_.Exception.Message)"
        if (Test-Path $tempOutput) { Remove-Item -Path $tempOutput -Force }
        if (Test-Path $OutputFile) { Remove-Item -Path $OutputFile -Force }
        return 2
    }
    finally {
        if (Test-Path "$env:TEMP\ffmpeg_error.txt") { Remove-Item "$env:TEMP\ffmpeg_error.txt" -Force }
    }
}

# Main processing function
function Start-VideoProcessing {
    if (-not (Test-FFmpeg)) {
        return
    }
    
    Write-LogMessage -Level "INFO" -Message "Starting video processing"
    
    # Initialize counters
    $totalFiles = 0
    $processedFiles = 0
    $skippedFiles = 0
    $errorFiles = 0
    $recoveredFiles = 0
    
    try {
        # Get all video files
        $videoFiles = Get-ChildItem -Path $InputPath -Recurse -Include @("*.mp4", "*.avi", "*.mov", "*.mkv")
        $totalFiles = $videoFiles.Count
        
        Write-LogMessage -Level "INFO" -Message "Found $totalFiles video files to process"
        
        foreach ($file in $videoFiles) {
            $relativePath = $file.FullName.Substring($InputPath.Length)
            $outputFile = Join-Path $OutputPath $relativePath
            
            $result = Process-Video -InputFile $file.FullName -OutputFile $outputFile
            
            switch ($result) {
                0 { 
                    $processedFiles++
                    # Check if this was a recovered file
                    if (Get-Content $RecoveryLogPath | Select-String -SimpleMatch $file.Name) {
                        $recoveredFiles++
                    }
                }
                1 { $skippedFiles++ }
                2 { $errorFiles++ }
            }
            
            # Log progress every 5 files
            if (($processedFiles + $skippedFiles + $errorFiles) % 5 -eq 0) {
                Write-LogMessage -Level "INFO" -Message "Progress: $processedFiles processed ($recoveredFiles recovered), $skippedFiles skipped, $errorFiles failed (Total: $totalFiles)"
            }
        }
    }
    catch {
        Write-LogMessage -Level "ERROR" -Message "Fatal error during processing: $($_.Exception.Message)"
    }
    finally {
        # Log final summary
        Write-LogMessage -Level "SUMMARY" -Message "Processing complete. Total files: $totalFiles, Processed: $processedFiles ($recoveredFiles recovered), Skippe
