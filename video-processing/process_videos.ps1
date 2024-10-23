# Advanced Video Processing and Recovery Script

param (
    [string]$InputPath = "./input",
    [string]$OutputPath = "./output",
    [string]$TempDir = "$env:TEMP\VideoRecovery",
    [switch]$AttemptRecovery = $true,
    [int]$MaxRetries = 3,
    [switch]$DeepAnalysis = $true,
    [switch]$AggressiveRecovery = $true,
    [int]$Verbosity = 2  # 0=minimal, 1=normal, 2=detailed
)

# Global configuration
$Global:Config = @{
    VideoTimeout = 7200        # 2 hour timeout
    MaxJobs = 1               # Single job for stability
    RecoveryAttempts = 12     # Increased recovery methods
    ChunkSize = 1024 * 1024   # 1MB chunks for processing
    MinValidSize = 1024       # Minimum valid file size
    MaxCorruptedRegions = 10  # Maximum corrupted regions to process
    BufferSize = 8192         # Read buffer size
    MaxAnalysisSize = 1GB     # Maximum size for deep analysis
}

# Initialize logging
$Global:LogPaths = @{
    Error = ".\video_error_log.txt"
    Process = ".\video_process_log.txt"
    Summary = ".\video_summary_log.txt"
    Recovery = ".\recovery_log.txt"
    Detailed = ".\detailed_recovery_log.txt"
    Analysis = ".\analysis_log.txt"
    Debug = ".\debug_log.txt"
}

# Codec and container signatures
$Global:MediaSignatures = @{
    Containers = @{
        MP4 = @{
            Signatures = @(
                @{ Name = "ftyp"; Hex = @(0x66, 0x74, 0x79, 0x70) }
                @{ Name = "moov"; Hex = @(0x6D, 0x6F, 0x6F, 0x76) }
                @{ Name = "mdat"; Hex = @(0x6D, 0x64, 0x61, 0x74) }
                @{ Name = "free"; Hex = @(0x66, 0x72, 0x65, 0x65) }
                @{ Name = "wide"; Hex = @(0x77, 0x69, 0x64, 0x65) }
            )
            RequiredAtoms = @("ftyp", "moov", "mdat")
        }
        MKV = @{
            Signatures = @(
                @{ Name = "EBML"; Hex = @(0x1A, 0x45, 0xDF, 0xA3) }
                @{ Name = "Segment"; Hex = @(0x18, 0x53, 0x80, 0x67) }
            )
        }
        AVI = @{
            Signatures = @(
                @{ Name = "RIFF"; Hex = @(0x52, 0x49, 0x46, 0x46) }
                @{ Name = "AVI "; Hex = @(0x41, 0x56, 0x49, 0x20) }
            )
        }
    }
    VideoCodecs = @{
        H264 = @{
            StartCodes = @(
                @(0x00, 0x00, 0x00, 0x01),
                @(0x00, 0x00, 0x01)
            )
            NALTypes = @{
                1  = "P-Frame"
                5  = "I-Frame"
                6  = "SEI"
                7  = "SPS"
                8  = "PPS"
                9  = "AUD"
            }
        }
        H265 = @{
            StartCodes = @(
                @(0x00, 0x00, 0x00, 0x01),
                @(0x00, 0x00, 0x01)
            )
            NALTypes = @{
                1  = "P-Frame"
                19 = "I-Frame"
                32 = "VPS"
                33 = "SPS"
                34 = "PPS"
            }
        }
        MPEG2 = @{
            StartCodes = @(
                @(0x00, 0x00, 0x01, 0xB3),
                @(0x00, 0x00, 0x01, 0x00)
            )
        }
        MPEG4 = @{
            StartCodes = @(
                @(0x00, 0x00, 0x01, 0xB6),
                @(0x00, 0x00, 0x01, 0xB3)
            )
        }
    }
    AudioCodecs = @{
        AAC = @{
            Signatures = @(
                @(0xFF, 0xF1),
                @(0xFF, 0xF9)
            )
        }
        MP3 = @{
            Signatures = @(
                @(0xFF, 0xFB),
                @(0xFF, 0xFA)
            )
        }
    }
}

# Initialize script environment
function Initialize-Environment {
    try {
        # Create necessary directories
        @($OutputPath, $TempDir) | ForEach-Object {
            if (-not (Test-Path $_)) {
                New-Item -ItemType Directory -Force -Path $_ | Out-Null
            }
        }

        # Initialize log files
        foreach ($logPath in $Global:LogPaths.Values) {
            if (Test-Path $logPath) {
                $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
                $backupPath = [System.IO.Path]::ChangeExtension($logPath, ".$timestamp.txt")
                Move-Item -Path $logPath -Destination $backupPath -Force
            }
            "" | Set-Content $logPath
        }

        # Verify FFmpeg installation
        if (-not (Test-FFmpeg)) {
            throw "FFmpeg is not installed or not in PATH"
        }

        Write-LogMessage -Level "INFO" -Message "Environment initialized successfully" -Detailed
        return $true
    }
    catch {
        Write-LogMessage -Level "ERROR" -Message "Failed to initialize environment: $($_.Exception.Message)"
        return $false
    }
}

# Base logging function
function Write-LogMessage {
    param (
        [string]$Level,
        [string]$Message,
        [switch]$Detailed
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    # Console output based on verbosity
    switch ($Level) {
        "ERROR" { Write-Host $logMessage -ForegroundColor Red }
        "WARNING" { Write-Host $logMessage -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logMessage -ForegroundColor Green }
        default { Write-Host $logMessage }
    }
    
    # File logging
    Add-Content -Path $Global:LogPaths.Process -Value $logMessage
    
    switch ($Level) {
        "ERROR" { Add-Content -Path $Global:LogPaths.Error -Value $logMessage }
        "SUMMARY" { Add-Content -Path $Global:LogPaths.Summary -Value $logMessage }
        "RECOVERY" { 
            Add-Content -Path $Global:LogPaths.Recovery -Value $logMessage
            if ($Detailed) {
                Add-Content -Path $Global:LogPaths.Detailed -Value $logMessage
            }
        }
    }
    
    if ($Detailed -and $Verbosity -ge 2) {
        Add-Content -Path $Global:LogPaths.Debug -Value $logMessage
    }
}

# FFmpeg verification function
function Test-FFmpeg {
    try {
        $ffmpegVersion = & ffmpeg -version
        $ffprobeVersion = & ffprobe -version
        Write-LogMessage -Level "INFO" -Message "Found FFmpeg: $($ffmpegVersion[0])"
        return $true
    }
    catch {
        Write-LogMessage -Level "ERROR" -Message "FFmpeg/FFprobe not found in PATH"
        return $false
    }
}

# Binary pattern search function
function Find-BinaryPattern {
    param (
        [byte[]]$Bytes,
        [byte[]]$Pattern,
        [int]$StartOffset = 0,
        [int]$MaxMatches = 0
    )
    
    $matches = New-Object System.Collections.ArrayList
    $patternLength = $Pattern.Length
    $searchLength = $Bytes.Length - $patternLength
    
    for ($i = $StartOffset; $i -lt $searchLength; $i++) {
        $found = $true
        for ($j = 0; $j -lt $patternLength; $j++) {
            if ($Bytes[$i + $j] -ne $Pattern[$j]) {
                $found = $false
                break
            }
        }
        if ($found) {
            $null = $matches.Add($i)
            if ($MaxMatches -gt 0 -and $matches.Count -ge $MaxMatches) {
                break
            }
        }
    }
    
    return $matches
}

# Enhanced binary analysis function
function Get-BinaryAnalysis {
    param (
        [string]$FilePath,
        [switch]$DeepScan
    )
    
    try {
        Write-LogMessage -Level "INFO" -Message "Starting binary analysis of $FilePath" -Detailed
        
        $fileInfo = Get-Item $FilePath
        $analysis = @{
            FilePath = $FilePath
            FileSize = $fileInfo.Length
            LastWriteTime = $fileInfo.LastWriteTime
            Signatures = @{
                Container = @()
                Video = @()
                Audio = @()
            }
            Structure = @{
                ValidRegions = @()
                CorruptedRegions = @()
                Atoms = @()
                NALUnits = @()
            }
            Streams = @{
                Video = @()
                Audio = @()
            }
            Metadata = @{
                Container = $null
                VideoCodec = $null
                AudioCodec = $null
                Duration = 0
                BitRate = 0
            }
            Recovery = @{
                RequiredLevel = "None"
                PossibleMethods = @()
                CorruptionType = @()
            }
        }

        # Create file reader with buffering
        $bufferSize = $Global:Config.BufferSize
        $fileStream = [System.IO.File]::OpenRead($FilePath)
        $reader = New-Object System.IO.BinaryReader($fileStream)
        
        # Initial container detection
        foreach ($containerType in $Global:MediaSignatures.Containers.Keys) {
            $signatures = $Global:MediaSignatures.Containers[$containerType].Signatures
            
            foreach ($sig in $signatures) {
                $matches = Find-BinaryPattern -Bytes ($reader.ReadBytes([Math]::Min($fileInfo.Length, 1MB))) -Pattern $sig.Hex
                if ($matches.Count -gt 0) {
                    $analysis.Signatures.Container += @{
                        Type = $containerType
                        Name = $sig.Name
                        Offset = $matches[0]
                        Signature = $sig.Hex
                    }
                }
                $fileStream.Position = 0
            }
        }

        # Determine container type
        if ($analysis.Signatures.Container.Count -gt 0) {
            $analysis.Metadata.Container = $analysis.Signatures.Container[0].Type
            Write-LogMessage -Level "INFO" -Message "Detected container type: $($analysis.Metadata.Container)" -Detailed
        }

        # Scan for codec signatures
        $scanSize = [Math]::Min($fileInfo.Length, 10MB)
        $scanBuffer = $reader.ReadBytes($scanSize)
        
        # Video codec detection
        foreach ($codec in $Global:MediaSignatures.VideoCodecs.Keys) {
            $startCodes = $Global:MediaSignatures.VideoCodecs[$codec].StartCodes
            
            foreach ($startCode in $startCodes) {
                $matches = Find-BinaryPattern -Bytes $scanBuffer -Pattern $startCode -MaxMatches 5
                if ($matches.Count -gt 0) {
                    $analysis.Signatures.Video += @{
                        Codec = $codec
                        Matches = $matches.Count
                        FirstOffset = $matches[0]
                    }
                    if (-not $analysis.Metadata.VideoCodec) {
                        $analysis.Metadata.VideoCodec = $codec
                    }
                }
            }
        }

        # Audio codec detection
        foreach ($codec in $Global:MediaSignatures.AudioCodecs.Keys) {
            $signatures = $Global:MediaSignatures.AudioCodecs[$codec].Signatures
            
            foreach ($sig in $signatures) {
                $matches = Find-BinaryPattern -Bytes $scanBuffer -Pattern $sig -MaxMatches 5
                if ($matches.Count -gt 0) {
                    $analysis.Signatures.Audio += @{
                        Codec = $codec
                        Matches = $matches.Count
                        FirstOffset = $matches[0]
                    }
                    if (-not $analysis.Metadata.AudioCodec) {
                        $analysis.Metadata.AudioCodec = $codec
                    }
                }
            }
        }

        # Deep analysis if requested
        if ($DeepScan) {
            Write-LogMessage -Level "INFO" -Message "Performing deep scan analysis" -Detailed
            
            # Analyze file structure
            switch ($analysis.Metadata.Container) {
                "MP4" { $analysis.Structure = Get-MP4Structure -Reader $reader }
                "MKV" { $analysis.Structure = Get-MKVStructure -Reader $reader }
                "AVI" { $analysis.Structure = Get-AVIStructure -Reader $reader }
            }

            # NAL unit analysis for H264/H265
            if ($analysis.Metadata.VideoCodec -in @("H264", "H265")) {
                $analysis.Structure.NALUnits = Get-NALUnits -Reader $reader -Codec $analysis.Metadata.VideoCodec
            }

            # Corruption detection
            $analysis.Structure.CorruptedRegions = Find-CorruptedRegions -Reader $reader -Analysis $analysis
            
            # Calculate valid regions
            $analysis.Structure.ValidRegions = Get-ValidRegions -Analysis $analysis
            
            # Determine recovery requirements
            $analysis.Recovery = Get-RecoveryRequirements -Analysis $analysis
        }

        Write-LogMessage -Level "INFO" -Message "Binary analysis completed" -Detailed
        return $analysis
    }
    catch {
        Write-LogMessage -Level "ERROR" -Message "Error during binary analysis: $($_.Exception.Message)" -Detailed
        return $null
    }
    finally {
        if ($reader) { $reader.Dispose() }
        if ($fileStream) { $fileStream.Dispose() }
    }
}

# MP4 structure analysis
function Get-MP4Structure {
    param (
        [System.IO.BinaryReader]$Reader
    )
    
    $structure = @{
        Atoms = @()
        Hierarchy = @{}
        ValidAtoms = 0
        InvalidAtoms = 0
    }
    
    try {
        $reader.BaseStream.Position = 0
        $fileSize = $reader.BaseStream.Length
        
        while ($reader.BaseStream.Position -lt ($fileSize - 8)) {
            $atomStart = $reader.BaseStream.Position
            
            # Check remaining bytes
            $remainingBytes = $fileSize - $reader.BaseStream.Position
            if ($remainingBytes -lt 8) {
                break
            }
            
            # Read atom size and type
            $atomSize = [System.Net.IPAddress]::NetworkToHostOrder($reader.ReadInt32())
            $atomType = [System.Text.Encoding]::ASCII.GetString($reader.ReadBytes(4))
            
            # Validate atom
            $isValid = $true
            if (($atomSize -lt 8) -or ($atomSize -gt ($fileSize - $atomStart))) {
                $isValid = $false
                $atomSize = 8 # Minimum atom size
            }
            
            $structure.Atoms += @{
                Type = $atomType
                Offset = $atomStart
                Size = $atomSize
                IsValid = $isValid
            }
            
            if ($isValid) {
                $structure.ValidAtoms++
            }
            else {
                $structure.InvalidAtoms++
            }
            
            # Position reader at next atom
            $reader.BaseStream.Position = $atomStart + $atomSize
        }
        
        return $structure
    }
    catch {
        Write-LogMessage -Level "ERROR" -Message "Error analyzing MP4 structure: $($_.Exception.Message)" -Detailed
        return $structure
    }
}

# Helper function for safe comparison
function Test-RemainingBytes {
    param (
        [System.IO.BinaryReader]$Reader,
        [int64]$RequiredBytes
    )
    
    $remaining = $Reader.BaseStream.Length - $Reader.BaseStream.Position
    return ($remaining -ge $RequiredBytes)
}

# Safe read function
function Read-SafeBytes {
    param (
        [System.IO.BinaryReader]$Reader,
        [int]$Count
    )
    
    if (Test-RemainingBytes -Reader $Reader -RequiredBytes $Count) {
        return $Reader.ReadBytes($Count)
    }
    return $null
}

# NAL unit analysis
function Get-NALUnits {
    param (
        [System.IO.BinaryReader]$Reader,
        [string]$Codec
    )
    
    $nalUnits = @()
    $startCodes = $Global:MediaSignatures.VideoCodecs[$Codec].StartCodes
    $nalTypes = $Global:MediaSignatures.VideoCodecs[$Codec].NALTypes
    
    try {
        $reader.BaseStream.Position = 0
        $fileSize = $reader.BaseStream.Length
        $buffer = New-Object byte[] $Global:Config.BufferSize
        
        while ($reader.BaseStream.Position -lt $fileSize) {
            $bytesRead = $reader.Read($buffer, 0, $buffer.Length)
            if ($bytesRead -lt 4) { break }
            
            foreach ($startCode in $startCodes) {
                $matches = Find-BinaryPattern -Bytes $buffer -Pattern $startCode
                
                foreach ($offset in $matches) {
                    if ($offset + $startCode.Length -lt $bytesRead) {
                        $nalType = $buffer[$offset + $startCode.Length] -band 0x1F
                        
                        $nalUnits += @{
                            Offset = $reader.BaseStream.Position - $bytesRead + $offset
                            Type = $nalTypes[$nalType]
                            StartCode = $startCode
                            Size = 0  # Will be calculated in post-processing
                        }
                    }
                }
            }
        }
        
        # Post-process NAL units to calculate sizes
        for ($i = 0; $i -lt $nalUnits.Count - 1; $i++) {
            $nalUnits[$i].Size = $nalUnits[$i + 1].Offset - $nalUnits[$i].Offset
        }
        if ($nalUnits.Count -gt 0) {
            $nalUnits[-1].Size = $fileSize - $nalUnits[-1].Offset
        }
        
        return $nalUnits
    }
    catch {
        Write-LogMessage -Level "ERROR" -Message "Error analyzing NAL units: $($_.Exception.Message)" -Detailed
        return $nalUnits
    }
}

# Corruption detection
function Find-CorruptedRegions {
    param (
        [System.IO.BinaryReader]$Reader,
        [hashtable]$Analysis
    )
    
    $corruptedRegions = @()
    
    try {
        $reader.BaseStream.Position = 0
        $fileSize = $reader.BaseStream.Length
        $chunkSize = $Global:Config.ChunkSize
        $buffer = New-Object byte[] $chunkSize
        
        Write-LogMessage -Level "INFO" -Message "Scanning for corrupted regions..." -Detailed
        
        $position = 0
        $consecutiveZeros = 0
        $corruptionStart = -1
        
        while ($position -lt $fileSize) {
            $bytesRead = $reader.Read($buffer, 0, [Math]::Min($chunkSize, $fileSize - $position))
            if ($bytesRead -eq 0) { break }
            
            # Analyze chunk for corruption patterns
            for ($i = 0; $i -lt $bytesRead; $i++) {
                # Pattern 1: Long sequences of zeros
                if ($buffer[$i] -eq 0) {
                    $consecutiveZeros++
                    if ($consecutiveZeros -eq 1024 -and $corruptionStart -eq -1) {
                        $corruptionStart = $position + $i - 1023
                    }
                }
                else {
                    if ($consecutiveZeros -ge 1024) {
                        $corruptedRegions += @{
                            Start = $corruptionStart
                            End = $position + $i
                            Type = "ZeroSequence"
                            Size = ($position + $i) - $corruptionStart
                        }
                    }
                    $consecutiveZeros = 0
                    $corruptionStart = -1
                }
                
                # Pattern 2: Invalid atom sizes (for MP4)
                if ($Analysis.Metadata.Container -eq "MP4" -and $i -le $bytesRead - 8) {
                    $potentialSize = [BitConverter]::ToUInt32($buffer[$i..($i+3)], 0)
                    if ($potentialSize -gt 0 -and $potentialSize -lt 8) {
                        $corruptedRegions += @{
                            Start = $position + $i
                            End = $position + $i + 8
                            Type = "InvalidAtomSize"
                            Size = 8
                        }
                    }
                }
            }
            
            $position += $bytesRead
        }
        
        # Merge overlapping regions
        if ($corruptedRegions.Count -gt 1) {
            $mergedRegions = @($corruptedRegions[0])
            for ($i = 1; $i -lt $corruptedRegions.Count; $i++) {
                $current = $corruptedRegions[$i]
                $previous = $mergedRegions[-1]
                
                if ($current.Start -le $previous.End) {
                    $previous.End = [Math]::Max($current.End, $previous.End)
                    $previous.Size = $previous.End - $previous.Start
                    $previous.Type = "Mixed"
                }
                else {
                    $mergedRegions += $current
                }
            }
            $corruptedRegions = $mergedRegions
        }
        
        Write-LogMessage -Level "INFO" -Message "Found $($corruptedRegions.Count) corrupted regions" -Detailed
        
        return $corruptedRegions
    }
    catch {
        Write-LogMessage -Level "ERROR" -Message "Error detecting corrupted regions: $($_.Exception.Message)" -Detailed
        return $corruptedRegions
    }
}

# Recovery requirements analysis
function Get-RecoveryRequirements {
    param (
        [hashtable]$Analysis
    )
    
    $requirements = @{
        RequiredLevel = "None"
        PossibleMethods = @()
        CorruptionType = @()
        Priority = 0
    }
    
    # Analyze container integrity
    if ($Analysis.Metadata.Container) {
        $requiredAtoms = $Global:MediaSignatures.Containers[$Analysis.Metadata.Container].RequiredAtoms
        $missingAtoms = @()
        
        if ($requiredAtoms) {
            $foundAtoms = $Analysis.Structure.Atoms | ForEach-Object { $_.Type }
            $missingAtoms = $requiredAtoms | Where-Object { $_ -notin $foundAtoms }
        }
        
        if ($missingAtoms.Count -gt 0) {
            $requirements.CorruptionType += "MissingAtoms"
            $requirements.PossibleMethods += "ContainerReconstruction"
            $requirements.Priority = [Math]::Max($requirements.Priority, 2)
        }
    }
    
    # Analyze stream integrity
    if ($Analysis.Structure.NALUnits.Count -eq 0 -and $Analysis.Metadata.VideoCodec -in @("H264", "H265")) {
        $requirements.CorruptionType += "NoNALUnits"
        $requirements.PossibleMethods += "StreamReconstruction"
        $requirements.Priority = [Math]::Max($requirements.Priority, 3)
    }
    
    # Analyze corruption level
    $corruptedSize = ($Analysis.Structure.CorruptedRegions | Measure-Object -Property Size -Sum).Sum
    if ($corruptedSize) {
        $corruptionPercentage = ($corruptedSize / $Analysis.FileSize) * 100
        
        if ($corruptionPercentage -gt 50) {
            $requirements.CorruptionType += "SevereCorruption"
            $requirements.PossibleMethods += "DeepRecovery"
            $requirements.Priority = [Math]::Max($requirements.Priority, 4)
        }
        elseif ($corruptionPercentage -gt 20) {
            $requirements.CorruptionType += "ModerateCorruption"
            $requirements.PossibleMethods += "StandardRecovery"
            $requirements.Priority = [Math]::Max($requirements.Priority, 2)
        }
        else {
            $requirements.CorruptionType += "MinorCorruption"
            $requirements.PossibleMethods += "LightRecovery"
            $requirements.Priority = [Math]::Max($requirements.Priority, 1)
        }
    }
    
    # Set required level based on priority
    $requirements.RequiredLevel = switch ($requirements.Priority) {
        0 { "None" }
        1 { "Light" }
        2 { "Standard" }
        3 { "Heavy" }
        4 { "Critical" }
        default { "Unknown" }
    }
    
    return $requirements
}

# Recovery method selection
function Get-RecoveryMethod {
    param (
        [hashtable]$Analysis
    )
    
    $recoveryMethods = @()
    
    # Add methods based on corruption type and container
    switch ($Analysis.Recovery.RequiredLevel) {
        "Light" {
            $recoveryMethods += @(
                @{
                    Name = "QuickFix"
                    Function = "Repair-QuickFix"
                    Priority = 1
                }
            )
        }
        "Standard" {
            $recoveryMethods += @(
                @{
                    Name = "ContainerRepair"
                    Function = "Repair-Container"
                    Priority = 2
                }
                @{
                    Name = "StreamExtraction"
                    Function = "Repair-StreamExtraction"
                    Priority = 3
                }
            )
        }
        "Heavy" {
            $recoveryMethods += @(
                @{
                    Name = "DeepRecovery"
                    Function = "Repair-DeepRecovery"
                    Priority = 4
                }
                @{
                    Name = "NALReconstruction"
                    Function = "Repair-NALReconstruction"
                    Priority = 4
                }
            )
        }
        "Critical" {
            $recoveryMethods += @(
                @{
                    Name = "AggressiveRecovery"
                    Function = "Repair-AggressiveRecovery"
                    Priority = 5
                }
                @{
                    Name = "BinaryReconstruction"
                    Function = "Repair-BinaryReconstruction"
                    Priority = 5
                }
                @{
                    Name = "FragmentRecovery"
                    Function = "Repair-Fragments"
                    Priority = 5
                }
            )
        }
    }
    
    # Add container-specific methods
    switch ($Analysis.Metadata.Container) {
        "MP4" {
            $recoveryMethods += @{
                Name = "MP4Repair"
                Function = "Repair-MP4Container"
                Priority = [Math]::Min($Analysis.Recovery.Priority + 1, 5)
            }
        }
        "MKV" {
            $recoveryMethods += @{
                Name = "MKVRepair"
                Function = "Repair-MKVContainer"
                Priority = [Math]::Min($Analysis.Recovery.Priority + 1, 5)
            }
        }
    }
    
    # Sort methods by priority
    return $recoveryMethods | Sort-Object -Property Priority
}

# Quick fix recovery
function Repair-QuickFix {
    param (
        [string]$InputFile,
        [string]$OutputFile,
        [hashtable]$Analysis
    )
    
    try {
        Write-LogMessage -Level "RECOVERY" -Message "Attempting quick fix recovery" -Detailed
        
        # Try simple remux first
        $process = Start-Process -FilePath "ffmpeg" -ArgumentList @(
            "-err_detect", "ignore_err",
            "-i", "`"$InputFile`"",
            "-c", "copy",
            "-movflags", "+faststart",
            "-y",
            "`"$OutputFile`""
        ) -NoNewWindow -PassThru -Wait -RedirectStandardError "$env:TEMP\ffmpeg_error.txt"
        
        if ($process.ExitCode -eq 0) {
            Write-LogMessage -Level "RECOVERY" -Message "Quick fix successful" -Detailed
            return $true
        }
        
        # If simple remux fails, try with error concealment
        $process = Start-Process -FilePath "ffmpeg" -ArgumentList @(
            "-fflags", "+genpts+discardcorrupt",
            "-i", "`"$InputFile`"",
            "-c", "copy",
            "-movflags", "+faststart",
            "-y",
            "`"$OutputFile`""
        ) -NoNewWindow -PassThru -Wait -RedirectStandardError "$env:TEMP\ffmpeg_error.txt"
        
        return $process.ExitCode -eq 0
    }
    catch {
        Write-LogMessage -Level "ERROR" -Message "Quick fix failed: $($_.Exception.Message)" -Detailed
        return $false
    }
}

# Container repair function
function Repair-Container {
    param (
        [string]$InputFile,
        [string]$OutputFile,
        [hashtable]$Analysis
    )
    
    try {
        Write-LogMessage -Level "RECOVERY" -Message "Attempting container repair" -Detailed
        
        switch ($Analysis.Metadata.Container) {
            "MP4" { return Repair-MP4Container -InputFile $InputFile -OutputFile $OutputFile -Analysis $Analysis }
            "MKV" { return Repair-MKVContainer -InputFile $InputFile -OutputFile $OutputFile -Analysis $Analysis }
            default { return Repair-GenericContainer -InputFile $InputFile -OutputFile $OutputFile -Analysis $Analysis }
        }
    }
    catch {
        Write-LogMessage -Level "ERROR" -Message "Container repair failed: $($_.Exception.Message)" -Detailed
        return $false
    }
}

# MP4 container repair
function Repair-MP4Container {
    param (
        [string]$InputFile,
        [string]$OutputFile,
        [hashtable]$Analysis
    )
    
    try {
        $tempFile = Join-Path $TempDir "rebuilt_container.mp4"
        $stream = [System.IO.File]::Create($tempFile)
        $reader = [System.IO.File]::OpenRead($InputFile)
        
        # Write FTYP
        $ftyp = $Analysis.Structure.Atoms | Where-Object { $_.Type -eq "ftyp" -and $_.IsValid } | Select-Object -First 1
        if ($ftyp) {
            $reader.Position = $ftyp.Offset
            $buffer = New-Object byte[] $ftyp.Size
            $reader.Read($buffer, 0, $ftyp.Size) | Out-Null
            $stream.Write($buffer, 0, $ftyp.Size)
        }
        else {
            # Write default FTYP
            $defaultFtyp = [byte[]]@(
                0,0,0,20,              # size
                0x66,0x74,0x79,0x70,   # 'ftyp'
                0x69,0x73,0x6F,0x6D,   # 'isom'
                0,0,0,1,               # minor version
                0x69,0x73,0x6F,0x6D    # compatible brand
            )
            $stream.Write($defaultFtyp, 0, $defaultFtyp.Length)
        }
        
        # Build or repair MOOV
        $moov = $Analysis.Structure.Atoms | Where-Object { $_.Type -eq "moov" -and $_.IsValid } | Select-Object -First 1
        if ($moov) {
            # Verify and repair MOOV if needed
            $reader.Position = $moov.Offset
            $moovData = New-Object byte[] $moov.Size
            $reader.Read($moovData, 0, $moov.Size) | Out-Null
            
            if (Test-MOOVAtom -Data $moovData) {
                $stream.Write($moovData, 0, $moovData.Length)
            }
            else {
                # Rebuild MOOV
                $newMoov = New-EnhancedMOOVAtom -VideoData $moovData -Analysis $Analysis
                $stream.Write($newMoov, 0, $newMoov.Length)
            }
        }
        else {
            # Generate new MOOV
            $newMoov = New-EnhancedMOOVAtom -Analysis $Analysis
            $stream.Write($newMoov, 0, $newMoov.Length)
        }
        
        # Write MDAT
        $mdat = $Analysis.Structure.Atoms | Where-Object { $_.Type -eq "mdat" -and $_.IsValid } | Select-Object -First 1
        if ($mdat) {
            $reader.Position = $mdat.Offset
            $bufferSize = 1MB
            $buffer = New-Object byte[] $bufferSize
            $remaining = $mdat.Size
            
            while ($remaining -gt 0) {
                $readSize = [Math]::Min($bufferSize, $remaining)
                $bytesRead = $reader.Read($buffer, 0, $readSize)
                if ($bytesRead -eq 0) { break }
                
                $stream.Write($buffer, 0, $bytesRead)
                $remaining -= $bytesRead
            }
        }
        else {
            # Try to construct MDAT from valid NAL units
            Write-VideoStream -Stream $stream -Analysis $Analysis -Reader $reader
        }
        
        $stream.Close()
        $reader.Close()
        
        # Verify and finalize with FFmpeg
        $process = Start-Process -FilePath "ffmpeg" -ArgumentList @(
            "-i", "`"$tempFile`"",
            "-c", "copy",
            "-movflags", "+faststart",
            "-y",
            "`"$OutputFile`""
        ) -NoNewWindow -PassThru -Wait -RedirectStandardError "$env:TEMP\ffmpeg_error.txt"
        
        if ($process.ExitCode -eq 0) {
            Write-LogMessage -Level "RECOVERY" -Message "MP4 container repair successful" -Detailed
            Remove-Item $tempFile -Force
            return $true
        }
        else {
            $errorContent = Get-Content "$env:TEMP\ffmpeg_error.txt" -Raw
            Write-LogMessage -Level "ERROR" -Message "MP4 container repair failed: $errorContent" -Detailed
            Remove-Item $tempFile -Force
            return $false
        }
    }
    catch {
        Write-LogMessage -Level "ERROR" -Message "MP4 container repair failed: $($_.Exception.Message)" -Detailed
        if (Test-Path $tempFile) { Remove-Item $tempFile -Force }
        return $false
    }
    finally {
        if ($stream) { $stream.Dispose() }
        if ($reader) { $reader.Dispose() }
    }
}

# Function to generate a new MOOV atom
function New-EnhancedMOOVAtom {
    param (
        [byte[]]$VideoData,
        [hashtable]$Analysis = $null,
        [hashtable]$StreamInfo = @{
            Width = 1920
            Height = 1080
            FrameRate = 30
            TimeScale = 90000
            AudioPresent = $false
            AudioCodec = "AAC"
            AudioChannels = 2
            AudioSampleRate = 48000
        }
    )
    
    try {
        $moov = New-Object System.Collections.ArrayList
        
        # MOOV header
        $moov.AddRange([byte[]]@(0,0,0,0, 0x6D,0x6F,0x6F,0x76))  # size will be updated later, 'moov'
        
        # MVHD atom (Movie Header)
        $mvhd = New-Object System.Collections.ArrayList
        $mvhd.AddRange([byte[]]@(
            0,0,0,0,                    # size (placeholder)
            0x6D,0x76,0x68,0x64,        # 'mvhd'
            0,0,0,0,                    # version/flags
            0,0,0,0,                    # creation time
            0,0,0,0                     # modification time
        ))
        
        # Add timescale (90000 is common for H.264)
        $timeScaleBytes = [BitConverter]::GetBytes([int32]$StreamInfo.TimeScale)
        [Array]::Reverse($timeScaleBytes)
        $mvhd.AddRange($timeScaleBytes)
        
        # Duration (estimate 60 seconds if unknown)
        $durationBytes = [BitConverter]::GetBytes([int32]($StreamInfo.TimeScale * 60))
        [Array]::Reverse($durationBytes)
        $mvhd.AddRange($durationBytes)
        
        # Rate (1.0 = normal speed)
        $mvhd.AddRange([byte[]]@(0,1,0,0))
        
        # Volume (1.0 = full volume)
        $mvhd.AddRange([byte[]]@(1,0))
        
        # Reserved
        $mvhd.AddRange([byte[]]@(0,0,0,0,0,0,0,0,0,0))
        
        # Matrix structure (identity matrix)
        $mvhd.AddRange([byte[]]@(
            0x00,0x01,0x00,0x00,  # a=1.0
            0x00,0x00,0x00,0x00,  # b=0.0
            0x00,0x00,0x00,0x00,  # u=0.0
            0x00,0x00,0x00,0x00,  # c=0.0
            0x00,0x01,0x00,0x00,  # d=1.0
            0x00,0x00,0x00,0x00,  # v=0.0
            0x00,0x00,0x00,0x00,  # x=0.0
            0x00,0x00,0x00,0x00,  # y=0.0
            0x40,0x00,0x00,0x00   # w=1.0
        ))
        
        # Preview time, duration, and other defaults
        $mvhd.AddRange([byte[]]@(
            0,0,0,0,              # Preview time
            0,0,0,0,              # Preview duration
            0,0,0,0,              # Poster time
            0,0,0,0,              # Selection time
            0,0,0,0,              # Selection duration
            0,0,0,0               # Current time
        ))
        
        # Next track ID (start with 1)
        $mvhd.AddRange([byte[]]@(0,0,0,1))
        
        # Update MVHD size
        $mvhdSize = $mvhd.Count
        $sizeBytes = [BitConverter]::GetBytes([int32]$mvhdSize)
        [Array]::Reverse($sizeBytes)
        for ($i = 0; $i -lt 4; $i++) {
            $mvhd[0] = $sizeBytes[$i]
        }
        
        # Add MVHD to MOOV
        $moov.AddRange($mvhd)
        
        # Add TRAK atom for video
        $trak = New-Object System.Collections.ArrayList
        $trak.AddRange([byte[]]@(
            0,0,0,0,              # size (placeholder)
            0x74,0x72,0x61,0x6B   # 'trak'
        ))
        
        # Add video track header (TKHD)
        $tkhd = New-Object System.Collections.ArrayList
        $tkhd.AddRange([byte[]]@(
            0,0,0,0,              # size (placeholder)
            0x74,0x6B,0x68,0x64,  # 'tkhd'
            0,0,0,3,              # version & flags (track enabled)
            0,0,0,0,              # creation time
            0,0,0,0,              # modification time
            0,0,0,1,              # track ID
            0,0,0,0,              # reserved
            0,0,0,0               # duration (same as movie)
        ))
        
        # Add video dimensions
        $widthBytes = [BitConverter]::GetBytes([int32]$StreamInfo.Width)
        $heightBytes = [BitConverter]::GetBytes([int32]$StreamInfo.Height)
        [Array]::Reverse($widthBytes)
        [Array]::Reverse($heightBytes)
        $tkhd.AddRange($widthBytes)
        $tkhd.AddRange($heightBytes)
        
        # Update TKHD size
        $tkhdSize = $tkhd.Count
        $sizeBytes = [BitConverter]::GetBytes([int32]$tkhdSize)
        [Array]::Reverse($sizeBytes)
        for ($i = 0; $i -lt 4; $i++) {
            $tkhd[$i] = $sizeBytes[$i]
        }
        
        # Add TKHD to TRAK
        $trak.AddRange($tkhd)
        
        # Update TRAK size
        $trakSize = $trak.Count
        $sizeBytes = [BitConverter]::GetBytes([int32]$trakSize)
        [Array]::Reverse($sizeBytes)
        for ($i = 0; $i -lt 4; $i++) {
            $trak[$i] = $sizeBytes[$i]
        }
        
        # Add TRAK to MOOV
        $moov.AddRange($trak)
        
        # Add audio track if present
        if ($StreamInfo.AudioPresent) {
            # Add audio TRAK structure (simplified for this example)
            $audioTrak = New-Object System.Collections.ArrayList
            $audioTrak.AddRange([byte[]]@(
                0,0,0,0,              # size (placeholder)
                0x74,0x72,0x61,0x6B   # 'trak'
            ))
            
            # Update audio TRAK size and add to MOOV
            $audioTrakSize = $audioTrak.Count
            $sizeBytes = [BitConverter]::GetBytes([int32]$audioTrakSize)
            [Array]::Reverse($sizeBytes)
            for ($i = 0; $i -lt 4; $i++) {
                $audioTrak[$i] = $sizeBytes[$i]
            }
            $moov.AddRange($audioTrak)
        }
        
        # Update final MOOV size
        $moovSize = $moov.Count
        $sizeBytes = [BitConverter]::GetBytes([int32]$moovSize)
        [Array]::Reverse($sizeBytes)
        for ($i = 0; $i -lt 4; $i++) {
            $moov[$i] = $sizeBytes[$i]
        }
        
        return $moov.ToArray()
    }
    catch {
        Write-LogMessage -Level "ERROR" -Message "Error generating MOOV atom: $($_.Exception.Message)"
        return $null
    }
}

# Stream extraction and reconstruction
function Repair-StreamExtraction {
    param (
        [string]$InputFile,
        [string]$OutputFile,
        [hashtable]$Analysis
    )
    
    try {
        Write-LogMessage -Level "RECOVERY" -Message "Attempting stream extraction recovery" -Detailed
        
        $tempVideoStream = Join-Path $TempDir "extracted_video.h264"
        $tempAudioStream = Join-Path $TempDir "extracted_audio.aac"
        
        # Extract video stream
        $videoSuccess = $false
        switch ($Analysis.Metadata.VideoCodec) {
            "H264" {
                $videoSuccess = Extract-H264Stream -InputFile $InputFile -OutputFile $tempVideoStream -Analysis $Analysis
            }
            "H265" {
                $videoSuccess = Extract-H265Stream -InputFile $InputFile -OutputFile $tempVideoStream -Analysis $Analysis
            }
            default {
                $videoSuccess = Extract-GenericVideoStream -InputFile $InputFile -OutputFile $tempVideoStream -Analysis $Analysis
            }
        }
        
        # Extract audio if present
        $audioSuccess = $false
        if ($Analysis.Metadata.AudioCodec) {
            $audioSuccess = Extract-AudioStream -InputFile $InputFile -OutputFile $tempAudioStream -Analysis $Analysis
        }
        
        if ($videoSuccess) {
            # Rebuild container with extracted streams
            $args = @(
                "-f", $(if ($Analysis.Metadata.VideoCodec -eq "H264") { "h264" } else { "hevc" }),
                "-i", "`"$tempVideoStream`""
            )
            
            if ($audioSuccess) {
                $args += @(
                    "-f", "aac",
                    "-i", "`"$tempAudioStream`""
                )
            }
            
            $args += @(
                "-c:v", "copy",
                "-c:a", "copy",
                "-movflags", "+faststart",
                "-y",
                "`"$OutputFile`""
            )
            
            $process = Start-Process -FilePath "ffmpeg" -ArgumentList $args -NoNewWindow -PassThru -Wait
            
            Remove-Item $tempVideoStream -Force -ErrorAction SilentlyContinue
            if ($audioSuccess) { Remove-Item $tempAudioStream -Force -ErrorAction SilentlyContinue }
            
            return $process.ExitCode -eq 0
        }
        
        return $false
    }
    catch {
        Write-LogMessage -Level "ERROR" -Message "Stream extraction failed: $($_.Exception.Message)" -Detailed
        return $false
    }
}

# H264 stream extraction
function Extract-H264Stream {
    param (
        [string]$InputFile,
        [string]$OutputFile,
        [hashtable]$Analysis
    )
    
    try {
        Write-LogMessage -Level "RECOVERY" -Message "Extracting H264 stream" -Detailed
        
        $reader = [System.IO.File]::OpenRead($InputFile)
        $writer = [System.IO.File]::Create($OutputFile)
        $buffer = New-Object byte[] $Global:Config.BufferSize
        
        # Track NAL unit state
        $nalUnits = @{
            SPS = $null
            PPS = $null
            IDR = $null
            Found = @()
        }
        
        # First pass: locate key NAL units
        Write-LogMessage -Level "RECOVERY" -Message "Scanning for key NAL units" -Detailed
        foreach ($nal in $Analysis.Structure.NALUnits) {
            $reader.Position = $nal.Offset
            $headerBuffer = New-Object byte[] 16
            $reader.Read($headerBuffer, 0, [Math]::Min(16, $nal.Size)) | Out-Null
            
            $nalType = $headerBuffer[4] -band 0x1F
            switch ($nalType) {
                7 { # SPS
                    if (-not $nalUnits.SPS) {
                        $nalUnits.SPS = @{
                            Offset = $nal.Offset
                            Size = $nal.Size
                        }
                    }
                }
                8 { # PPS
                    if (-not $nalUnits.PPS) {
                        $nalUnits.PPS = @{
                            Offset = $nal.Offset
                            Size = $nal.Size
                        }
                    }
                }
                5 { # IDR
                    if (-not $nalUnits.IDR) {
                        $nalUnits.IDR = @{
                            Offset = $nal.Offset
                            Size = $nal.Size
                        }
                    }
                }
            }
        }
        
        # Write stream header
        if ($nalUnits.SPS -and $nalUnits.PPS) {
            # Write SPS
            $reader.Position = $nalUnits.SPS.Offset
            $spsBuffer = New-Object byte[] $nalUnits.SPS.Size
            $reader.Read($spsBuffer, 0, $nalUnits.SPS.Size) | Out-Null
            $writer.Write($spsBuffer, 0, $spsBuffer.Length)
            
            # Write PPS
            $reader.Position = $nalUnits.PPS.Offset
            $ppsBuffer = New-Object byte[] $nalUnits.PPS.Size
            $reader.Read($ppsBuffer, 0, $nalUnits.PPS.Size) | Out-Null
            $writer.Write($ppsBuffer, 0, $ppsBuffer.Length)
        }
        else {
            Write-LogMessage -Level "WARNING" -Message "Missing SPS/PPS, stream may not be playable" -Detailed
        }
        
        # Second pass: write valid NAL units
        Write-LogMessage -Level "RECOVERY" -Message "Writing valid NAL units" -Detailed
        $validNALCount = 0
        foreach ($nal in $Analysis.Structure.NALUnits) {
            try {
                $reader.Position = $nal.Offset
                $remaining = $nal.Size
                
                while ($remaining -gt 0) {
                    $readSize = [Math]::Min($Global:Config.BufferSize, $remaining)
                    $bytesRead = $reader.Read($buffer, 0, $readSize)
                    if ($bytesRead -eq 0) { break }
                    
                    $writer.Write($buffer, 0, $bytesRead)
                    $remaining -= $bytesRead
                }
                
                $validNALCount++
            }
            catch {
                Write-LogMessage -Level "WARNING" -Message "Failed to write NAL unit at offset $($nal.Offset)" -Detailed
                continue
            }
        }
        
        $writer.Close()
        $reader.Close()
        
        Write-LogMessage -Level "RECOVERY" -Message "Extracted $validNALCount valid NAL units" -Detailed
        
        # Verify extracted stream
        if (Test-H264Stream -FilePath $OutputFile) {
            return $true
        }
        else {
            Remove-Item $OutputFile -Force
            return $false
        }
    }
    catch {
        Write-LogMessage -Level "ERROR" -Message "H264 stream extraction failed: $($_.Exception.Message)" -Detailed
        if ($writer) { $writer.Close() }
        if ($reader) { $reader.Close() }
        if (Test-Path $OutputFile) { Remove-Item $OutputFile -Force }
        return $false
    }
}

# H264 stream verification
function Test-H264Stream {
    param (
        [string]$FilePath
    )
    
    try {
        $process = Start-Process -FilePath "ffprobe" -ArgumentList @(
            "-v", "error",
            "-select_streams", "v:0",
            "-show_entries", "stream=codec_name",
            "-of", "default=noprint_wrappers=1:nokey=1",
            "`"$FilePath`""
        ) -NoNewWindow -PassThru -Wait -RedirectStandardOutput "$env:TEMP\ffprobe_out.txt"
        
        if ($process.ExitCode -eq 0) {
            $codec = Get-Content "$env:TEMP\ffprobe_out.txt"
            return $codec -eq "h264"
        }
        return $false
    }
    catch {
        return $false
    }
    finally {
        if (Test-Path "$env:TEMP\ffprobe_out.txt") {
            Remove-Item "$env:TEMP\ffprobe_out.txt" -Force
        }
    }
}

# NAL unit reconstruction
function Repair-NALReconstruction {
    param (
        [string]$InputFile,
        [string]$OutputFile,
        [hashtable]$Analysis
    )
    
    try {
        Write-LogMessage -Level "RECOVERY" -Message "Attempting NAL reconstruction" -Detailed
        
        $tempStream = Join-Path $TempDir "reconstructed_stream.h264"
        $writer = [System.IO.File]::Create($tempStream)
        $reader = [System.IO.File]::OpenRead($InputFile)
        
        # Track frame sequences
        $frameSequence = @{
            LastKeyFrame = $null
            CurrentGOP = @()
            ValidGOPs = 0
        }
        
        # Process NAL units
        $currentNAL = 0
        $totalNALs = $Analysis.Structure.NALUnits.Count
        
        foreach ($nal in $Analysis.Structure.NALUnits) {
            $currentNAL++
            if ($currentNAL % 100 -eq 0) {
                Write-LogMessage -Level "RECOVERY" -Message "Processing NAL unit $currentNAL of $totalNALs" -Detailed
            }
            
            try {
                $reader.Position = $nal.Offset
                $headerBuffer = New-Object byte[] 16
                $reader.Read($headerBuffer, 0, [Math]::Min(16, $nal.Size)) | Out-Null
                
                $nalType = $headerBuffer[4] -band 0x1F
                
                # Handle different NAL types
                switch ($nalType) {
                    5 { # IDR Frame
                        if ($frameSequence.CurrentGOP.Count -gt 0) {
                            # Write previous GOP if valid
                            if ($frameSequence.LastKeyFrame) {
                                Write-GOP -Writer $writer -GOP $frameSequence.CurrentGOP -Analysis $Analysis
                                $frameSequence.ValidGOPs++
                            }
                            $frameSequence.CurrentGOP.Clear()
                        }
                        $frameSequence.LastKeyFrame = $nal
                        $frameSequence.CurrentGOP += $nal
                    }
                    1 { # Non-IDR Frame
                        if ($frameSequence.LastKeyFrame) {
                            $frameSequence.CurrentGOP += $nal
                        }
                    }
                    7 { # SPS
                        Write-NALUnit -Writer $writer -NAL $nal -Reader $reader
                    }
                    8 { # PPS
                        Write-NALUnit -Writer $writer -NAL $nal -Reader $reader
                    }
                    default {
                        if ($frameSequence.LastKeyFrame) {
                            Write-NALUnit -Writer $writer -NAL $nal -Reader $reader
                        }
                    }
                }
            }
            catch {
                Write-LogMessage -Level "WARNING" -Message "Failed to process NAL unit $currentNAL" -Detailed
                continue
            }
        }
        
        # Write final GOP if exists
        if ($frameSequence.CurrentGOP.Count -gt 0 -and $frameSequence.LastKeyFrame) {
            Write-GOP -Writer $writer -GOP $frameSequence.CurrentGOP -Analysis $Analysis
            $frameSequence.ValidGOPs++
        }
        
        $writer.Close()
        $reader.Close()
        
        Write-LogMessage -Level "RECOVERY" -Message "Reconstructed $($frameSequence.ValidGOPs) valid GOPs" -Detailed
        
        # Convert reconstructed stream to final output
        if ($frameSequence.ValidGOPs -gt 0) {
            $process = Start-Process -FilePath "ffmpeg" -ArgumentList @(
                "-f", "h264",
                "-i", "`"$tempStream`"",
                "-c:v", "copy",
                "-movflags", "+faststart",
                "-y",
                "`"$OutputFile`""
            ) -NoNewWindow -PassThru -Wait
            
            Remove-Item $tempStream -Force
            return $process.ExitCode -eq 0
        }
        
        Remove-Item $tempStream -Force
        return $false
    }
    catch {
        Write-LogMessage -Level "ERROR" -Message "NAL reconstruction failed: $($_.Exception.Message)" -Detailed
        if ($writer) { $writer.Close() }
        if ($reader) { $reader.Close() }
        if (Test-Path $tempStream) { Remove-Item $tempStream -Force }
        return $false
    }
}

# Deep recovery implementation
function Repair-DeepRecovery {
    param (
        [string]$InputFile,
        [string]$OutputFile,
        [hashtable]$Analysis
    )
    
    try {
        Write-LogMessage -Level "RECOVERY" -Message "Starting deep recovery process" -Detailed
        
        # Create temporary directory for fragments
        $fragmentDir = Join-Path $TempDir "fragments"
        New-Item -ItemType Directory -Force -Path $fragmentDir | Out-Null
        
        # Extract valid segments
        $validSegments = Get-ValidSegments -Analysis $Analysis
        $segmentFiles = @()
        
        foreach ($segment in $validSegments) {
            $segmentFile = Join-Path $fragmentDir "segment_$($segment.Start).mp4"
            if (Extract-VideoSegment -InputFile $InputFile -OutputFile $segmentFile -Start $segment.Start -Size $segment.Size) {
                $segmentFiles += $segmentFile
            }
        }
        
        if ($segmentFiles.Count -eq 0) {
            Write-LogMessage -Level "ERROR" -Message "No valid segments could be extracted" -Detailed
            return $false
        }
        
        # Create segment list file
        $segmentList = Join-Path $TempDir "segments.txt"
        $segmentFiles | ForEach-Object {
            "file '$_'" | Add-Content $segmentList
        }
        
        # Combine segments
        $process = Start-Process -FilePath "ffmpeg" -ArgumentList @(
            "-f", "concat",
            "-safe", "0",
            "-i", "`"$segmentList`"",
            "-c", "copy",
            "-movflags", "+faststart",
            "-y",
            "`"$OutputFile`""
        ) -NoNewWindow -PassThru -Wait
        
        # Cleanup
        Remove-Item $fragmentDir -Recurse -Force
        Remove-Item $segmentList -Force
        
        return $process.ExitCode -eq 0
    }
    catch {
        Write-LogMessage -Level "ERROR" -Message "Deep recovery failed: $($_.Exception.Message)" -Detailed
        return $false
    }
}

# Aggressive recovery implementation
function Repair-AggressiveRecovery {
    param (
        [string]$InputFile,
        [string]$OutputFile,
        [hashtable]$Analysis
    )
    
    try {
        Write-LogMessage -Level "RECOVERY" -Message "Starting aggressive recovery" -Detailed
        
        # Attempt multiple approaches in sequence
        $approaches = @(
            @{
                Name = "Lenient"
                Args = @(
                    "-fflags", "+genpts+igndts+discardcorrupt",
                    "-err_detect", "ignore_err",
                    "-i", "`"$InputFile`"",
                    "-c:v", "libx264",
                    "-preset", "medium",
                    "-crf", "23",
                    "-c:a", "aac",
                    "-b:a", "128k",
                    "-y",
                    "`"$OutputFile`""
                )
            }
            @{
                Name = "Fragment"
                Args = @(
                    "-fflags", "+genpts+igndts",
                    "-i", "`"$InputFile`"",
                    "-f", "segment",
                    "-segment_time", "5",
                    "-reset_timestamps", "1",
                    "-c", "copy",
                    "-y",
                    "`"$OutputFile`""
                )
            }
            @{
                Name = "Rebuild"
                Args = @(
                    "-fflags", "+genpts",
                    "-i", "`"$InputFile`"",
                    "-c:v", "libx264",
                    "-preset", "veryslow",
                    "-crf", "18",
                    "-refs", "1",
                    "-deblock", "0:0",
                    "-c:a", "aac",
                    "-b:a", "192k",
                    "-y",
                    "`"$OutputFile`""
                )
            }
        )
        
        foreach ($approach in $approaches) {
            Write-LogMessage -Level "RECOVERY" -Message "Trying $($approach.Name) approach" -Detailed
            
            $process = Start-Process -FilePath "ffmpeg" -ArgumentList $approach.Args -NoNewWindow -PassThru -Wait
            
            if ($process.ExitCode -eq 0 -and (Test-Path $OutputFile)) {
                # Verify output
                $verifyProcess = Start-Process -FilePath "ffprobe" -ArgumentList @(
                    "-v", "error",
                    "-show_entries", "format=duration",
                    "-of", "default=noprint_wrappers=1:nokey=1",
                    "`"$OutputFile`""
                ) -NoNewWindow -PassThru -Wait -RedirectStandardOutput "$env:TEMP\ffprobe_out.txt"
                
                if ($verifyProcess.ExitCode -eq 0) {
                    $duration = Get-Content "$env:TEMP\ffprobe_out.txt"
                    if ([double]$duration -gt 0) {
                        Write-LogMessage -Level "RECOVERY" -Message "$($approach.Name) approach successful" -Detailed
                        return $true
                    }
                }
            }
            
            if (Test-Path $OutputFile) {
                Remove-Item $OutputFile -Force
            }
        }
        
        Write-LogMessage -Level "ERROR" -Message "All aggressive recovery approaches failed" -Detailed
        return $false
    }
    catch {
        Write-LogMessage -Level "ERROR" -Message "Aggressive recovery failed: $($_.Exception.Message)" -Detailed
        return $false
    }
}

function Get-ValidRegions {
    param (
        [hashtable]$Analysis
    )
    
    $validRegions = @()
    
    try {
        # Sort corruption points to find valid regions between them
        $corruptionPoints = @($Analysis.Structure.CorruptedRegions | Select-Object -ExpandProperty Start | Sort-Object)
        
        if ($corruptionPoints.Count -eq 0) {
            # If no corruption points, the whole file is valid
            $validRegions += @{
                Start = 0
                End = $Analysis.FileSize
                Size = $Analysis.FileSize
            }
        }
        else {
            # Check region before first corruption
            if ($corruptionPoints[0] -gt 1024) {
                $validRegions += @{
                    Start = 0
                    End = $corruptionPoints[0]
                    Size = $corruptionPoints[0]
                }
            }
            
            # Check regions between corruption points
            for ($i = 0; $i -lt ($corruptionPoints.Count - 1); $i++) {
                $start = $corruptionPoints[$i]
                $end = $corruptionPoints[$i + 1]
                $size = $end - $start
                
                if ($size -gt 1024) {  # Only include regions larger than 1KB
                    $validRegions += @{
                        Start = $start
                        End = $end
                        Size = $size
                    }
                }
            }
            
            # Check region after last corruption
            $lastPoint = $corruptionPoints[-1]
            if (($Analysis.FileSize - $lastPoint) -gt 1024) {
                $validRegions += @{
                    Start = $lastPoint
                    End = $Analysis.FileSize
                    Size = $Analysis.FileSize - $lastPoint
                }
            }
        }
        
        Write-LogMessage -Level "INFO" -Message "Found $($validRegions.Count) valid regions" -Detailed
        return $validRegions
    }
    catch {
        Write-LogMessage -Level "ERROR" -Message "Error getting valid regions: $($_.Exception.Message)" -Detailed
        return $validRegions
    }
}

# Main processing function
function Process-Video {
    param (
        [string]$InputFile,
        [string]$OutputFile
    )
    
    try {
        $fileName = Split-Path $InputFile -Leaf
        Write-LogMessage -Level "INFO" -Message "Processing $fileName"
        
        # Skip if output exists
        if (Test-Path $OutputFile) {
            Write-LogMessage -Level "INFO" -Message "Output file already exists, skipping"
            return 1
        }

        # Try simple processing first
        Write-LogMessage -Level "INFO" -Message "Attempting direct processing first"
        $process = Start-Process -FilePath "ffmpeg" -ArgumentList @(
            "-i", "`"$InputFile`"",
            "-c", "copy",
            "-y",
            "`"$OutputFile`""
        ) -NoNewWindow -PassThru -Wait -RedirectStandardError "$env:TEMP\ffmpeg_error.txt"

        if ($process.ExitCode -eq 0 -and (Test-Path $OutputFile)) {
            # Verify the output
            $verifyProcess = Start-Process -FilePath "ffprobe" -ArgumentList @(
                "-v", "error",
                "-select_streams", "v:0",
                "-show_entries", "stream=duration",
                "-of", "default=noprint_wrappers=1:nokey=1",
                "`"$OutputFile`""
            ) -NoNewWindow -PassThru -Wait -RedirectStandardOutput "$env:TEMP\ffprobe_out.txt"

            if ($verifyProcess.ExitCode -eq 0) {
                $duration = Get-Content "$env:TEMP\ffprobe_out.txt"
                if ([double]$duration -gt 0) {
                    Write-LogMessage -Level "SUCCESS" -Message "Direct processing successful"
                    return 0
                }
            }
            Remove-Item $OutputFile -Force
        }

        # If direct processing failed, then try recovery
        if (-not $AttemptRecovery) {
            Write-LogMessage -Level "ERROR" -Message "Direct processing failed and recovery is disabled"
            return 2
        }

        Write-LogMessage -Level "INFO" -Message "Direct processing failed, attempting recovery"
        
        # Now do the analysis for recovery
        $analysis = Get-BinaryAnalysis -FilePath $InputFile -DeepScan:$DeepAnalysis
        if (-not $analysis) {
            Write-LogMessage -Level "ERROR" -Message "Failed to analyze file for recovery"
            return 2
        }

        # Get recovery methods
        $methods = Get-RecoveryMethod -Analysis $analysis
        
        # Try each recovery method
        foreach ($method in $methods) {
            Write-LogMessage -Level "RECOVERY" -Message "Attempting $($method.Name) recovery method"
            
            $scriptBlock = $ExecutionContext.InvokeCommand.GetCommand($method.Function, 'Function')
            if ($scriptBlock) {
                if (& $scriptBlock -InputFile $InputFile -OutputFile $OutputFile -Analysis $analysis) {
                    Write-LogMessage -Level "SUCCESS" -Message "Recovery successful using $($method.Name)"
                    return 0
                }
            }
        }
        
        Write-LogMessage -Level "ERROR" -Message "All recovery methods failed"
        return 2
    }
    catch {
        Write-LogMessage -Level "ERROR" -Message "Error processing $fileName`: $($_.Exception.Message)"
        return 2
    }
    finally {
        if (Test-Path "$env:TEMP\ffmpeg_error.txt") { Remove-Item "$env:TEMP\ffmpeg_error.txt" -Force }
        if (Test-Path "$env:TEMP\ffprobe_out.txt") { Remove-Item "$env:TEMP\ffprobe_out.txt" -Force }
    }
}

# Function to write video stream data
function Write-VideoStream {
    param (
        [System.IO.Stream]$Stream,
        [hashtable]$Analysis,
        [System.IO.BinaryReader]$Reader
    )
    
    try {
        # Write MDAT header
        $mdatHeader = [byte[]]@(0,0,0,0, 0x6D,0x64,0x61,0x74)  # Size will be updated later
        $mdatStart = $Stream.Position
        $Stream.Write($mdatHeader, 0, 8)
        
        # Write NAL units
        $dataWritten = 0
        foreach ($nal in $Analysis.Structure.NALUnits) {
            if ($nal.Size -gt 0) {
                $Reader.BaseStream.Position = $nal.Offset
                $buffer = New-Object byte[] $nal.Size
                $bytesRead = $Reader.Read($buffer, 0, $nal.Size)
                
                if ($bytesRead -gt 0) {
                    $Stream.Write($buffer, 0, $bytesRead)
                    $dataWritten += $bytesRead
                }
            }
        }
        
        # Update MDAT size
        $mdatSize = $dataWritten + 8  # Include header size
        $sizeBytes = [BitConverter]::GetBytes([int32]$mdatSize)
        [Array]::Reverse($sizeBytes)
        
        $Stream.Position = $mdatStart
        $Stream.Write($sizeBytes, 0, 4)
        $Stream.Position = $Stream.Length
        
        return $true
    }
    catch {
        Write-LogMessage -Level "ERROR" -Message "Error writing video stream: $($_.Exception.Message)"
        return $false
    }
}

# Function to extract audio stream
function Extract-AudioStream {
    param (
        [string]$InputFile,
        [string]$OutputFile,
        [hashtable]$Analysis
    )
    
    try {
        # Try to extract audio stream using FFmpeg
        $process = Start-Process -FilePath "ffmpeg" -ArgumentList @(
            "-i", "`"$InputFile`"",
            "-vn",             # Disable video
            "-acodec", "copy", # Copy audio codec
            "-y",             # Overwrite output
            "`"$OutputFile`""
        ) -NoNewWindow -PassThru -Wait -RedirectStandardError "$env:TEMP\ffmpeg_error.txt"
        
        if ($process.ExitCode -eq 0 -and (Test-Path $OutputFile)) {
            # Verify the extracted audio
            $verifyProcess = Start-Process -FilePath "ffprobe" -ArgumentList @(
                "-v", "error",
                "-show_entries", "stream=codec_type",
                "-of", "default=noprint_wrappers=1:nokey=1",
                "`"$OutputFile`""
            ) -NoNewWindow -PassThru -Wait -RedirectStandardOutput "$env:TEMP\ffprobe_out.txt"
            
            if ($verifyProcess.ExitCode -eq 0) {
                $streamType = Get-Content "$env:TEMP\ffprobe_out.txt"
                if ($streamType -contains "audio") {
                    return $true
                }
            }
        }
        
        return $false
    }
    catch {
        Write-LogMessage -Level "ERROR" -Message "Error extracting audio stream: $($_.Exception.Message)"
        return $false
    }
    finally {
        if (Test-Path "$env:TEMP\ffmpeg_error.txt") { Remove-Item "$env:TEMP\ffmpeg_error.txt" -Force }
        if (Test-Path "$env:TEMP\ffprobe_out.txt") { Remove-Item "$env:TEMP\ffprobe_out.txt" -Force }
    }
}

# Function to safely read chunks of data
function Read-FileChunk {
    param (
        [System.IO.BinaryReader]$Reader,
        [int]$Size
    )
    
    try {
        $remaining = $Reader.BaseStream.Length - $Reader.BaseStream.Position
        $readSize = [Math]::Min($Size, $remaining)
        
        if ($readSize -le 0) { return $null }
        
        return $Reader.ReadBytes($readSize)
    }
    catch {
        Write-LogMessage -Level "ERROR" -Message "Error reading file chunk: $($_.Exception.Message)"
        return $null
    }
}

# Helper function to validate audio stream
function Test-AudioStream {
    param ([string]$FilePath)
    
    try {
        $process = Start-Process -FilePath "ffprobe" -ArgumentList @(
            "-v", "error",
            "-select_streams", "a:0",
            "-show_entries", "stream=codec_name",
            "-of", "default=noprint_wrappers=1:nokey=1",
            "`"$FilePath`""
        ) -NoNewWindow -PassThru -Wait -RedirectStandardOutput "$env:TEMP\ffprobe_out.txt"
        
        if ($process.ExitCode -eq 0) {
            $codec = Get-Content "$env:TEMP\ffprobe_out.txt"
            return -not [string]::IsNullOrWhiteSpace($codec)
        }
        return $false
    }
    catch {
        return $false
    }
    finally {
        if (Test-Path "$env:TEMP\ffprobe_out.txt") {
            Remove-Item "$env:TEMP\ffprobe_out.txt" -Force
        }
    }
}

# Main entry point
function Start-VideoProcessing {
    if (-not (Initialize-Environment)) {
        return
    }
    
    Write-LogMessage -Level "INFO" -Message "Starting video processing"
    Write-LogMessage -Level "INFO" -Message "Input path: $InputPath"
    Write-LogMessage -Level "INFO" -Message "Output path: $OutputPath"
    
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
            
            # Create output directory if needed
            $outputDir = Split-Path $outputFile -Parent
            if (-not (Test-Path $outputDir)) {
                New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
            }
            
            $result = Process-Video -InputFile $file.FullName -OutputFile $outputFile
            
            switch ($result) {
                0 { $script:processedFiles++ }
                1 { $script:skippedFiles++ }
                2 { $script:errorFiles++ }
            }
            
            # Log progress
            if (($processedFiles + $skippedFiles + $errorFiles) % 5 -eq 0) {
                Write-LogMessage -Level "INFO" -Message "Progress: $processedFiles processed, $skippedFiles skipped, $errorFiles failed (Total: $totalFiles)"
            }
        }
    }
    catch {
        Write-LogMessage -Level "ERROR" -Message "Fatal error during processing: $($_.Exception.Message)"
    }
    finally {
        # Cleanup
        if (Test-Path $TempDir) {
            Remove-Item $TempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        
        # Log final summary
        Write-LogMessage -Level "SUMMARY" -Message @"
Processing complete.
Total files: $totalFiles
Processed successfully: $processedFiles
Skipped: $skippedFiles
Failed: $errorFiles
"@
    }
}

# Start the processing
Start-VideoProcessing
