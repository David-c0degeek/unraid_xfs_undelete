# Advanced Video Processing Script with Maximum Recovery Options
param (
    [string]$InputPath = ".\input",
    [string]$OutputPath = ".\output",
    [switch]$AttemptRecovery = $true,
    [string]$TempDir = "$env:TEMP\VideoRecovery",
    [int]$MaxRetries = 3
)

# Initialize logging
$ErrorLogPath = ".\video_error_log.txt"
$ProcessLogPath = ".\video_process_log.txt"
$SummaryLogPath = ".\video_summary_log.txt"
$RecoveryLogPath = ".\recovery_log.txt"
$DetailedRecoveryPath = ".\detailed_recovery_log.txt"

# Video processing settings
$VideoTimeout = 7200  # 2 hour timeout for complex recovery
$MaxJobs = 1         # Single job for maximum stability
$RecoveryAttempts = 8 # Increased number of recovery methods

# Create necessary directories
$null = New-Item -ItemType Directory -Force -Path $OutputPath
$null = New-Item -ItemType Directory -Force -Path $TempDir

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

# Initialize all log files
@($ErrorLogPath, $ProcessLogPath, $SummaryLogPath, $RecoveryLogPath, $DetailedRecoveryPath) | ForEach-Object {
    Initialize-LogFile $_
}

# Enhanced logging function
function Write-LogMessage {
    param (
        [string]$Level,
        [string]$Message,
        [switch]$Detailed
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
            if ($Detailed) {
                Add-Content -Path $DetailedRecoveryPath -Value "[$timestamp] $Message"
            }
        }
    }
}

# Function to check FFmpeg existence
function Test-FFmpeg {
    try {
        $ffmpegVersion = & ffmpeg -version
        $ffprobeVersion = & ffprobe -version
        Write-LogMessage -Level "INFO" -Message "Found FFmpeg: $($ffmpegVersion[0])"
        return $true
    }
    catch {
        Write-LogMessage -Level "ERROR" -Message "FFmpeg/FFprobe not found in PATH. Please install FFmpeg and add it to your system PATH."
        return $false
    }
}

# Function to analyze error type
function Get-VideoErrorType {
    param (
        [string]$FilePath,
        [string]$ErrorText
    )
    
    $errorTypes = @()
    
    if ($ErrorText -match "moov atom not found") {
        $errorTypes += "MISSING_INDEX"
    }
    if ($ErrorText -match "Invalid NAL unit size") {
        $errorTypes += "CORRUPT_STREAM"
    }
    if ($ErrorText -match "partial file") {
        $errorTypes += "PARTIAL_FILE"
    }
    if ($ErrorText -match "Error splitting the input into NAL units") {
        $errorTypes += "NAL_ERROR"
    }
    if ($ErrorText -match "Invalid data found when processing input") {
        $errorTypes += "INVALID_DATA"
    }
    
    # Additional checks
    try {
        $fileSize = (Get-Item $FilePath).Length
        if ($fileSize -lt 1024) {
            $errorTypes += "TOO_SMALL"
        }
        
        # Check for zero bytes in the first 512 bytes
        $bytes = [System.IO.File]::ReadAllBytes($FilePath)[0..511]
        if ($bytes.Count -gt 0 -and ($bytes | Where-Object { $_ -eq 0 }).Count -gt 100) {
            $errorTypes += "ZERO_BYTES"
        }
    }
    catch {
        $errorTypes += "FILE_ACCESS_ERROR"
    }
    
    if ($errorTypes.Count -eq 0) {
        $errorTypes += "UNKNOWN"
    }
    
    return $errorTypes
}

# Function to extract raw H264 stream
function Export-RawStream {
    param (
        [string]$InputFile,
        [string]$OutputFile,
        [string]$StreamType = "video"
    )
    
    try {
        $mapOption = if ($StreamType -eq "video") { "-vcodec copy -an" } else { "-acodec copy -vn" }
        $format = if ($StreamType -eq "video") { "h264" } else { "adts" }
        
        $process = Start-Process -FilePath "ffmpeg" -ArgumentList @(
            "-i", "`"$InputFile`"",
            "-f", $format
            $mapOption.Split(" ")
            "-y",
            "`"$OutputFile`""
        ) -NoNewWindow -PassThru -Wait -RedirectStandardError "$env:TEMP\ffmpeg_error.txt"
        
        return $process.ExitCode -eq 0
    }
    catch {
        return $false
    }
}

# Function to analyze frame corruption
function Get-FrameAnalysis {
    param (
        [string]$InputFile
    )
    
    try {
        $frameInfo = & ffprobe -v error -select_streams v -show_frames -of json "$InputFile" 2>$null | ConvertFrom-Json
        
        $result = @{
            TotalFrames = 0
            CorruptFrames = 0
            KeyFrames = 0
            LastGoodKeyframe = -1
            HasAudio = $false
        }
        
        if ($frameInfo.frames) {
            $result.TotalFrames = $frameInfo.frames.Count
            $result.KeyFrames = ($frameInfo.frames | Where-Object { $_.key_frame -eq 1 }).Count
            $result.CorruptFrames = ($frameInfo.frames | Where-Object { $_.corrupt -eq 1 }).Count
            
            # Find last good keyframe
            for ($i = $frameInfo.frames.Count - 1; $i -ge 0; $i--) {
                if ($frameInfo.frames[$i].key_frame -eq 1 -and $frameInfo.frames[$i].corrupt -ne 1) {
                    $result.LastGoodKeyframe = $i
                    break
                }
            }
        }
        
        # Check for audio
        $audioInfo = & ffprobe -v error -select_streams a -show_streams "$InputFile" 2>$null
        $result.HasAudio = $null -ne $audioInfo
        
        return $result
    }
    catch {
        return $null
    }
}

# Function to attempt stream repair
function Repair-Stream {
    param (
        [string]$InputFile,
        [string]$OutputFile,
        [string]$StreamType = "video"
    )
    
    $tempFile = Join-Path $TempDir "temp_stream.$StreamType"
    
    try {
        if (Export-RawStream -InputFile $InputFile -OutputFile $tempFile -StreamType $StreamType) {
            # Additional stream-specific repair steps
            if ($StreamType -eq "video") {
                # H264 bitstream filter
                $process = Start-Process -FilePath "ffmpeg" -ArgumentList @(
                    "-i", "`"$tempFile`"",
                    "-bsf:v", "h264_mp4toannexb,dump_extra",
                    "-c", "copy",
                    "-y",
                    "`"$OutputFile`""
                ) -NoNewWindow -PassThru -Wait
                
                return $process.ExitCode -eq 0
            }
            else {
                # Audio stream repair
                $process = Start-Process -FilePath "ffmpeg" -ArgumentList @(
                    "-i", "`"$tempFile`"",
                    "-c:a", "aac",
                    "-b:a", "384k",
                    "-y",
                    "`"$OutputFile`""
                ) -NoNewWindow -PassThru -Wait
                
                return $process.ExitCode -eq 0
            }
        }
        return $false
    }
    finally {
        if (Test-Path $tempFile) {
            Remove-Item $tempFile -Force
        }
    }
}

# Enhanced video repair function
function Repair-Video {
    param (
        [string]$InputFile,
        [string]$OutputFile,
        [int]$AttemptNumber = 1
    )
    
    $fileName = Split-Path $InputFile -Leaf
    $tempOutput = Join-Path $TempDir "repair${AttemptNumber}_$fileName"
    
    try {
        Write-LogMessage -Level "RECOVERY" -Message "Starting recovery method $AttemptNumber for: $fileName" -Detailed
        
        # Get error type and frame analysis
        $probeError = & ffprobe "$InputFile" 2>&1 | Out-String
        $errorTypes = Get-VideoErrorType -FilePath $InputFile -ErrorText $probeError
        $frameAnalysis = Get-FrameAnalysis -InputFile $InputFile
        
        Write-LogMessage -Level "RECOVERY" -Message "Detected error types: $($errorTypes -join ', ') for $fileName" -Detailed
        if ($frameAnalysis) {
            Write-LogMessage -Level "RECOVERY" -Message "Frame analysis: Total=$($frameAnalysis.TotalFrames), Corrupt=$($frameAnalysis.CorruptFrames), KeyFrames=$($frameAnalysis.KeyFrames)" -Detailed
        }
        
        # Different recovery methods based on error type and attempt number
        switch ($AttemptNumber) {
            1 {
                # Basic container fix
                $process = Start-Process -FilePath "ffmpeg" -ArgumentList @(
                    "-err_detect", "ignore_err",
                    "-i", "`"$InputFile`"",
                    "-c", "copy",
                    "-f", "mp4",
                    "-y",
                    "`"$tempOutput`""
                ) -NoNewWindow -PassThru -Wait -RedirectStandardError "$env:TEMP\ffmpeg_error.txt"
            }
            2 {
                # Index recovery for missing MOOV
                $process = Start-Process -FilePath "ffmpeg" -ArgumentList @(
                    "-f", "mp4",
                    "-fflags", "+genpts+igndts",
                    "-i", "`"$InputFile`"",
                    "-c", "copy",
                    "-movflags", "+faststart+use_metadata_tags",
                    "-f", "mp4",
                    "-y",
                    "`"$tempOutput`""
                ) -NoNewWindow -PassThru -Wait -RedirectStandardError "$env:TEMP\ffmpeg_error.txt"
            }
            3 {
                # Stream extraction and rebuild
                $videoStream = Join-Path $TempDir "temp_video.h264"
                $audioStream = Join-Path $TempDir "temp_audio.aac"
                
                try {
                    $videoSuccess = Repair-Stream -InputFile $InputFile -OutputFile $videoStream -StreamType "video"
                    $audioSuccess = Repair-Stream -InputFile $InputFile -OutputFile $audioStream -StreamType "audio"
                    
                    if ($videoSuccess) {
                        $args = @(
                            "-i", "`"$videoStream`""
                        )
                        
                        if ($audioSuccess) {
                            $args += @("-i", "`"$audioStream`"")
                        }
                        
                        $args += @(
                            "-c:v", "copy",
                            "-c:a", "copy",
                            "-f", "mp4",
                            "-y",
                            "`"$tempOutput`""
                        )
                        
                        $process = Start-Process -FilePath "ffmpeg" -ArgumentList $args -NoNewWindow -PassThru -Wait
                    }
                }
                finally {
                    @($videoStream, $audioStream) | Where-Object { Test-Path $_ } | ForEach-Object { Remove-Item $_ -Force }
                }
            }
            4 {
                # Frame-by-frame reconstruction
                $process = Start-Process -FilePath "ffmpeg" -ArgumentList @(
                    "-fflags", "+genpts+igndts+discardcorrupt",
                    "-err_detect", "ignore_err",
                    "-i", "`"$InputFile`"",
                    "-c:v", "libx264",
                    "-preset", "medium",
                    "-crf", "18",
                    "-refs", "1",
                    "-force_key_frames", "expr:gte(t,n_forced*2)",
                    "-c:a", "aac",
                    "-b:a", "384k",
                    "-ar", "48000",
                    "-f", "mp4",
                    "-y",
                    "`"$tempOutput`""
                ) -NoNewWindow -PassThru -Wait -RedirectStandardError "$env:TEMP\ffmpeg_error.txt"
            }
            5 {
                # Keyframe preservation with error concealment
                $process = Start-Process -FilePath "ffmpeg" -ArgumentList @(
                    "-fflags", "+genpts+igndts",
                    "-err_detect", "aggressive",
                    "-i", "`"$InputFile`"",
                    "-c:v", "libx264",
                    "-preset", "slow",
                    "-crf", "18",
                    "-refs", "1",
                    "-g", "30",
                    "-keyint_min", "30",
                    "-sc_threshold", "0",
                    "-c:a", "aac",
                    "-b:a", "384k",
                    "-f", "mp4",
                    "-y",
                    "`"$tempOutput`""
                ) -NoNewWindow -PassThru -Wait -RedirectStandardError "$env:TEMP\ffmpeg_error.txt"
            }
            6 {
                # Segment-based recovery
                $segments = Join-Path $TempDir "segments"
                New-Item -ItemType Directory -Force -Path $segments | Out-Null
                
                try {
                    # Split into segments
                    $segmentProcess = Start-Process -FilePath "ffmpeg" -ArgumentList @(
                        "-i", "`"$InputFile`"",
                        "-f", "segment",
                        "-segment_time", "10",
                        "-reset_timestamps", "1",
                        "-c", "copy",
                        "`"$segments\segment_%03d.mp4`""
                    ) -NoNewWindow -PassThru -Wait
                    
                    # Concatenate valid segments
                    $segmentList = Join-Path $TempDir "segments.txt"
                    Get-ChildItem "$segments\segment_*.mp4" | ForEach-Object {
                        if ((Get-VideoErrorType -FilePath $_.FullName -ErrorText "").Count -eq 0) {
                            "file '$($_.FullName)'" | Add-Content $segmentList
                        }
                    }
                    
                    if (Test-Path $segmentList) {
                        $process = Start-Process -FilePath "ffmpeg" -ArgumentList @(
                            "-f", "concat",
                            "-safe", "0",
                            "-i", "`"$segmentList`"",
                            "-c", "copy",
                            "-f", "mp4",
                            "-y",
                            "`"$tempOutput`""
                        ) -NoNewWindow -PassThru -Wait -RedirectStandardError "$env:TEMP\ffmpeg_error.txt"
                    }
                }
                finally {
                    Remove-Item -Path $segments -Recurse -Force -ErrorAction SilentlyContinue
                    Remove-Item -Path $segmentList -Force -ErrorAction SilentlyContinue
                }
            }
            7 {
                # Two-pass recovery with error concealment
                $pass1Output = Join-Path $TempDir "pass1_$fileName"
                
                try {
                    # First pass - analyze and attempt to fix stream errors
                    $process1 = Start-Process -FilePath "ffmpeg" -ArgumentList @(
                        "-fflags", "+genpts+igndts+discardcorrupt",
                        "-err_detect", "aggressive",
                        "-i", "`"$InputFile`"",
                        "-c:v", "libx264",
                        "-preset", "slow",
                        "-crf", "18",
                        "-refs", "1",
                        "-bf", "0",
                        "-flags", "+low_delay",
                        "-strict", "experimental",
                        "-y",
                        "`"$pass1Output`""
                    ) -NoNewWindow -PassThru -Wait
                    
                    if ($process1.ExitCode -eq 0) {
                        # Second pass - optimize and finalize
                        $process = Start-Process -FilePath "ffmpeg" -ArgumentList @(
                            "-i", "`"$pass1Output`"",
                            "-c:v", "libx264",
                            "-preset", "slow",
                            "-crf", "18",
                            "-movflags", "+faststart",
                            "-c:a", "aac",
                            "-b:a", "384k",
                            "-f", "mp4",
                            "-y",
                            "`"$tempOutput`""
                        ) -NoNewWindow -PassThru -Wait -RedirectStandardError "$env:TEMP\ffmpeg_error.txt"
                    }
                }
                finally {
                    Remove-Item -Path $pass1Output -Force -ErrorAction SilentlyContinue
                }
            }
            8 {
                # Last resort: aggressive recovery with frame drop
                $process = Start-Process -FilePath "ffmpeg" -ArgumentList @(
                    "-fflags", "+genpts+igndts+discardcorrupt",
                    "-err_detect", "aggressive",
                    "-i", "`"$InputFile`"",
                    "-c:v", "libx264",
                    "-preset", "medium",
                    "-crf", "23",
                    "-refs", "1",
                    "-vf", "select='not(mod(n,1))',setpts=N/FRAME_RATE/TB",
                    "-af", "aselect='not(mod(n,1))',asetpts=N/SR/TB",
                    "-max_muxing_queue_size", "1024",
                    "-f", "mp4",
                    "-y",
                    "`"$tempOutput`""
                ) -NoNewWindow -PassThru -Wait -RedirectStandardError "$env:TEMP\ffmpeg_error.txt"
            }
        }
        
        # Verify the output
        if ($process.ExitCode -eq 0 -and (Test-Path $tempOutput) -and (Get-Item $tempOutput).Length -gt 0) {
            $verifyCheck = Test-VideoFile -FilePath $tempOutput
            if ($verifyCheck.IsValid) {
                Move-Item -Path $tempOutput -Destination $OutputFile -Force
                Write-LogMessage -Level "RECOVERY" -Message "Successfully recovered $fileName using method $AttemptNumber" -Detailed
                
                # Log recovery details
                $originalSize = [math]::Round((Get-Item $InputFile).Length / 1MB, 2)
                $recoveredSize = [math]::Round((Get-Item $OutputFile).Length / 1MB, 2)
                Write-LogMessage -Level "RECOVERY" -Message "Recovery stats for $fileName - Original: ${originalSize}MB, Recovered: ${recoveredSize}MB" -Detailed
                
                return $true
            }
            else {
                Remove-Item -Path $tempOutput -Force
                Write-LogMessage -Level "RECOVERY" -Message "Recovery attempt $AttemptNumber failed verification for $fileName" -Detailed
                return $false
            }
        }
        else {
            if (Test-Path $tempOutput) { Remove-Item -Path $tempOutput -Force }
            $errorContent = Get-Content "$env:TEMP\ffmpeg_error.txt" -Raw
            Write-LogMessage -Level "RECOVERY" -Message "Recovery attempt $AttemptNumber failed for $fileName`: $errorContent" -Detailed
            return $false
        }
    }
    catch {
        Write-LogMessage -Level "RECOVERY" -Message "Exception during recovery attempt $AttemptNumber for $fileName`: $($_.Exception.Message)" -Detailed
        if (Test-Path $tempOutput) { Remove-Item -Path $tempOutput -Force }
        return $false
    }
    finally {
        if (Test-Path "$env:TEMP\ffmpeg_error.txt") { Remove-Item "$env:TEMP\ffmpeg_error.txt" -Force }
    }
}

# Function to validate video file
function Test-VideoFile {
    param (
        [string]$FilePath
    )
    
    try {
        # First check if we can read any stream info
        $probeOutput = & ffprobe -v error -of json -show_streams -show_format -i "$FilePath" 2>&1
        if ($LASTEXITCODE -ne 0) {
            return @{
                IsValid = $false
                CodecName = $null
                Error = "Failed to probe file"
                RequiresRecovery = $true
                Duration = 0
                HasVideo = $false
                HasAudio = $false
            }
        }

        # Parse the JSON output
        try {
            $videoInfo = $probeOutput | ConvertFrom-Json
        }
        catch {
            return @{
                IsValid = $false
                CodecName = $null
                Error = "Invalid probe output"
                RequiresRecovery = $true
                Duration = 0
                HasVideo = $false
                HasAudio = $false
            }
        }

        # Find video and audio streams
        $videoStream = $videoInfo.streams | Where-Object { $_.codec_type -eq "video" } | Select-Object -First 1
        $audioStream = $videoInfo.streams | Where-Object { $_.codec_type -eq "audio" } | Select-Object -First 1
        
        if (-not $videoStream) {
            return @{
                IsValid = $false
                CodecName = $null
                Error = "No video stream found"
                RequiresRecovery = $true
                Duration = 0
                HasVideo = $false
                HasAudio = ($null -ne $audioStream)
            }
        }

        # Check duration and validate streams
        $duration = if ($videoInfo.format.duration) { [float]$videoInfo.format.duration } else { 0 }
        $requiresRecovery = $duration -eq 0 -or $duration -eq "N/A"

        # Additional validation of video stream
        $process = Start-Process -FilePath "ffmpeg" -ArgumentList @(
            "-v", "error",
            "-i", "`"$FilePath`"",
            "-t", "1",
            "-f", "null",
            "-"
        ) -NoNewWindow -PassThru -Wait -RedirectStandardError "$env:TEMP\ffmpeg_error.txt"

        $hasErrors = $false
        if (Test-Path "$env:TEMP\ffmpeg_error.txt") {
            $errors = Get-Content "$env:TEMP\ffmpeg_error.txt"
            $hasErrors = $errors.Count -gt 0
            Remove-Item "$env:TEMP\ffmpeg_error.txt" -Force
        }

        return @{
            IsValid = -not $requiresRecovery -and -not $hasErrors
            CodecName = $videoStream.codec_name
            Error = if ($requiresRecovery -or $hasErrors) { "Stream validation failed" } else { $null }
            RequiresRecovery = $requiresRecovery -or $hasErrors
            Duration = $duration
            HasVideo = $true
            HasAudio = ($null -ne $audioStream)
            Width = $videoStream.width
            Height = $videoStream.height
            FrameRate = $videoStream.r_frame_rate
        }
    }
    catch {
        return @{
            IsValid = $false
            CodecName = $null
            Error = $_.Exception.Message
            RequiresRecovery = $true
            Duration = 0
            HasVideo = $false
            HasAudio = $false
        }
    }
}

# Function to process video files
function Process-Video {
    param (
        [string]$InputFile,
        [string]$OutputFile
    )
    
    $fileName = Split-Path $InputFile -Leaf
    $tempOutput = $null
    
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
        Write-LogMessage -Level "INFO" -Message "Video check for $fileName - Valid: $($videoCheck.IsValid), Codec: $($videoCheck.CodecName), Has Audio: $($videoCheck.HasAudio)" -Detailed
        
        if (-not $videoCheck.IsValid) {
            if ($AttemptRecovery -and $videoCheck.RequiresRecovery) {
                Write-LogMessage -Level "RECOVERY" -Message "Starting recovery process for: $fileName"
                
                # Try each recovery method
                for ($i = 1; $i -le $RecoveryAttempts; $i++) {
                    Write-LogMessage -Level "RECOVERY" -Message "Attempting recovery method $i of $RecoveryAttempts for $fileName"
                    if (Repair-Video -InputFile $InputFile -OutputFile $OutputFile -AttemptNumber $i) {
                        Write-LogMessage -Level "RECOVERY" -Message "Successfully recovered $fileName using method $i"
                        return 0
                    }
                    Write-LogMessage -Level "RECOVERY" -Message "Recovery method $i failed for $fileName"
                }
                
                Write-LogMessage -Level "ERROR" -Message "All recovery attempts failed for: $fileName"
                return 2
            }
            else {
                Write-LogMessage -Level "ERROR" -Message "Invalid or corrupt video file ($($videoCheck.Error)): $fileName"
                return 2
            }
        }
        
        # If input is already H.264 and valid, optimize the container
        if ($videoCheck.CodecName -eq "h264" -and $videoCheck.IsValid) {
            $tempOutput = Join-Path $TempDir "temp_$fileName"
            
            $process = Start-Process -FilePath "ffmpeg" -ArgumentList @(
                "-i", "`"$InputFile`"",
                "-c", "copy",
                "-movflags", "+faststart",
                "-y",
                "`"$tempOutput`""
            ) -NoNewWindow -PassThru -Wait -RedirectStandardError "$env:TEMP\ffmpeg_error.txt"

            if ($process.ExitCode -eq 0) {
                Move-Item -Path $tempOutput -Destination $OutputFile -Force
                Write-LogMessage -Level "INFO" -Message "Optimized container for $fileName"
                return 0
            }
        }
        
        # Process with high-quality settings
        $tempOutput = Join-Path $TempDir "temp_$fileName"
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
            return 2
        }
    }
    catch {
        Write-LogMessage -Level "ERROR" -Message "Exception processing $fileName`: $($_.Exception.Message)"
        if ($tempOutput -and (Test-Path $tempOutput)) { Remove-Item -Path $tempOutput -Force }
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
    Write-LogMessage -Level "INFO" -Message "Input path: $InputPath"
    Write-LogMessage -Level "INFO" -Message "Output path: $OutputPath"
    Write-LogMessage -Level "INFO" -Message "Recovery attempts: $RecoveryAttempts"
    
    # Initialize counters
    $script:totalFiles = 0
    $script:processedFiles = 0
    $script:skippedFiles = 0
    $script:errorFiles = 0
    $script:recoveredFiles = 0
    
    try {
        # Get all video files
        $videoFiles = Get-ChildItem -Path $InputPath -Recurse -Include @("*.mp4", "*.avi", "*.mov", "*.mkv")
        $script:totalFiles = $videoFiles.Count
        
        Write-LogMessage -Level "INFO" -Message "Found $totalFiles video files to process"
        
        # Process each file
        foreach ($file in $videoFiles) {
            $relativePath = $file.FullName.Substring($InputPath.Length)
            $outputFile = Join-Path $OutputPath $relativePath
            
            $result = Process-Video -InputFile $file.FullName -OutputFile $outputFile
            
            switch ($result) {
                0 { 
                    $script:processedFiles++
                    # Check if this was a recovered file
                    if (Get-Content $RecoveryLogPath | Select-String -SimpleMatch $file.Name) {
                        $script:recoveredFiles++
                    }
                }
                1 { $script:skippedFiles++ }
                2 { $script:errorFiles++ }
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
        # Clean up temp directory
        if (Test-Path $TempDir) {
            Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        
        # Log final summary
        Write-LogMessage -Level "SUMMARY" -Message @"
Processing complete.
Total files: $totalFiles
Processed successfully: $processedFiles
Recovered from corruption: $recoveredFiles
Skipped (already processed): $skippedFiles
Failed: $errorFiles
"@
    }
}

# Start the processing
Start-VideoProcessing
