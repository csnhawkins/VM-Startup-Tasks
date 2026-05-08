# ============================================================
# AMI-Prep-Warmup.ps1
# Pre-warms EBS volume by reading all files before AMI snapshot.
# Run this on the source instance BEFORE creating your AMI.
# This ensures all blocks are accessed, which can improve
# restoration time when launching new instances.
# ============================================================

# Disable QuickEdit mode to prevent window freeze when clicked/moved
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class ConsoleHelper {
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern IntPtr GetStdHandle(int nStdHandle);
    [DllImport("kernel32.dll")]
    public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);
    [DllImport("kernel32.dll")]
    public static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);
    public const int STD_INPUT_HANDLE = -10;
    public const uint ENABLE_QUICK_EDIT_MODE = 0x0040;
    public const uint ENABLE_EXTENDED_FLAGS = 0x0080;
}
"@
try {
    $handle = [ConsoleHelper]::GetStdHandle([ConsoleHelper]::STD_INPUT_HANDLE)
    $mode = 0
    [ConsoleHelper]::GetConsoleMode($handle, [ref]$mode) | Out-Null
    $mode = $mode -band (-bnot [ConsoleHelper]::ENABLE_QUICK_EDIT_MODE)
    $mode = $mode -bor [ConsoleHelper]::ENABLE_EXTENDED_FLAGS
    [ConsoleHelper]::SetConsoleMode($handle, $mode) | Out-Null
} catch {
    # Ignore errors if console mode cannot be set
}

$LogFile = "C:\git\Admin\logs\ami-prep-warmup.log"
$StartTime = Get-Date

New-Item -Path "C:\git\Admin\logs" -ItemType Directory -Force | Out-Null

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts  $Message" | Out-File -FilePath $LogFile -Append
    Write-Host "  $Message" -ForegroundColor $Color
}

function Format-Bytes {
    param([long]$Bytes)
    if ($Bytes -ge 1TB) { return "{0:N2} TB" -f ($Bytes / 1TB) }
    if ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return "{0:N2} KB" -f ($Bytes / 1KB) }
    return "$Bytes bytes"
}

function Format-Duration {
    param([TimeSpan]$Duration)
    if ($Duration.TotalMinutes -lt 1) {
        return "$([Math]::Floor($Duration.TotalSeconds)) seconds"
    } elseif ($Duration.TotalHours -lt 1) {
        $mins = [Math]::Floor($Duration.TotalMinutes)
        $secs = $Duration.Seconds
        return "$mins minutes $secs seconds"
    } else {
        $hrs = [Math]::Floor($Duration.TotalHours)
        $mins = $Duration.Minutes
        return "$hrs hours $mins minutes"
    }
}

Write-Host ""
Write-Host "  ═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  ║         AMI PREPARATION - EBS VOLUME PRE-WARMING           ║" -ForegroundColor Cyan
Write-Host "  ═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

Write-Log "===== AMI Pre-Warming Started =====" "Cyan"
Write-Log "This will read all files to ensure blocks are resident in the snapshot." "DarkGray"
Write-Host ""

# Define volumes/paths to warm
$PathsToWarm = @(
    "C:\git",
    "C:\Program Files\Docker",
    "C:\ProgramData\Docker",
    "C:\Users"
)

# Filter to only existing paths
$PathsToWarm = $PathsToWarm | Where-Object { Test-Path $_ }

$TotalFilesProcessed = 0
$TotalBytesRead = 0
$TotalErrors = 0

foreach ($Path in $PathsToWarm) {
    Write-Host ""
    Write-Log "─────────────────────────────────────────────────────────────────" "DarkGray"
    Write-Log "Processing: $Path" "Yellow"
    
    # Count files first for progress tracking
    Write-Host "  Scanning files..." -ForegroundColor DarkGray
    $AllFiles = @(Get-ChildItem $Path -Recurse -File -Force -ErrorAction SilentlyContinue)
    $FileCount = $AllFiles.Count
    $TotalSize = ($AllFiles | Measure-Object -Property Length -Sum).Sum
    
    Write-Log "Found $FileCount files ($( Format-Bytes $TotalSize ))" "White"
    
    if ($FileCount -eq 0) {
        Write-Log "No files to process, skipping." "DarkGray"
        continue
    }
    
    # Estimate time (rough: 200 MB/s read speed)
    $EstimatedSecs = [Math]::Max(5, $TotalSize / (200 * 1MB))
    $EstimatedTime = [TimeSpan]::FromSeconds($EstimatedSecs)
    Write-Log "Estimated time: $(Format-Duration $EstimatedTime)" "DarkGray"
    Write-Host ""
    
    $PathStartTime = Get-Date
    $ProcessedFiles = 0
    $ProcessedBytes = 0
    $Errors = 0
    $LastUpdate = Get-Date
    
    foreach ($File in $AllFiles) {
        try {
            # Read the file (opens and closes immediately)
            $stream = [System.IO.File]::OpenRead($File.FullName)
            $stream.Close()
            $ProcessedBytes += $File.Length
        } catch {
            $Errors++
        }
        
        $ProcessedFiles++
        
        # Update progress every 0.5 seconds
        $now = Get-Date
        if (($now - $LastUpdate).TotalMilliseconds -gt 500 -or $ProcessedFiles -eq $FileCount) {
            $LastUpdate = $now
            $pct = [Math]::Floor(($ProcessedFiles / $FileCount) * 100)
            $elapsed = New-TimeSpan -Start $PathStartTime -End $now
            $rate = if ($elapsed.TotalSeconds -gt 0) { $ProcessedBytes / $elapsed.TotalSeconds } else { 0 }
            
            # Calculate ETA
            $remaining = $FileCount - $ProcessedFiles
            $eta = if ($ProcessedFiles -gt 10 -and $rate -gt 0) {
                $remainingBytes = $TotalSize - $ProcessedBytes
                $etaSecs = $remainingBytes / $rate
                $etaTime = [TimeSpan]::FromSeconds($etaSecs)
                "ETA " + $etaTime.ToString('mm\:ss')
            } else {
                "Calculating..."
            }
            
            $barWidth = 40
            $filled = [Math]::Floor($barWidth * $pct / 100)
            $empty = $barWidth - $filled
            $bar = ([string][char]0x2588 * $filled) + ([string][char]0x2591 * $empty)
            
            $line = "  [$bar] $($pct.ToString().PadLeft(3))%   " +
                    "$($ProcessedFiles.ToString().PadLeft(6))/$FileCount files   " +
                    "$(Format-Bytes $ProcessedBytes)   " +
                    "$eta   " +
                    "$(Format-Bytes $rate)/s   "
            
            Write-Host "`r$line" -NoNewline -ForegroundColor Cyan
        }
    }
    
    # Final stats for this path
    $PathDuration = New-TimeSpan -Start $PathStartTime -End (Get-Date)
    Write-Host "" # New line after progress bar
    Write-Host ""
    
    if ($Errors -gt 0) {
        Write-Log "Completed with $Errors errors" "Yellow"
    } else {
        Write-Log "Completed successfully!" "Green"
    }
    
    Write-Log "Time taken: $(Format-Duration $PathDuration)" "White"
    $avgRate = if ($PathDuration.TotalSeconds -gt 0) { $ProcessedBytes / $PathDuration.TotalSeconds } else { 0 }
    Write-Log "Average speed: $(Format-Bytes $avgRate)/s" "White"
    
    $TotalFilesProcessed += $ProcessedFiles
    $TotalBytesRead += $ProcessedBytes
    $TotalErrors += $Errors
}

# Final summary
$TotalDuration = New-TimeSpan -Start $StartTime -End (Get-Date)

Write-Host ""
Write-Host ""
Write-Host "  ═══════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "  ║                    PRE-WARMING COMPLETE                    ║" -ForegroundColor Green
Write-Host "  ═══════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host ""
Write-Log "===== Summary =====" "Green"
Write-Log "Total files processed: $TotalFilesProcessed" "White"
Write-Log "Total data read: $(Format-Bytes $TotalBytesRead)" "White"
Write-Log "Total time: $(Format-Duration $TotalDuration)" "White"
$overallRate = if ($TotalDuration.TotalSeconds -gt 0) { $TotalBytesRead / $TotalDuration.TotalSeconds } else { 0 }
Write-Log "Overall speed: $(Format-Bytes $overallRate)/s" "White"

if ($TotalErrors -gt 0) {
    Write-Log "Errors encountered: $TotalErrors (likely locked files - this is normal)" "Yellow"
}

Write-Host ""
Write-Log "EBS volume is now pre-warmed and ready for AMI snapshot creation." "Green"
Write-Log "You can now create your AMI from this instance." "Cyan"
Write-Host ""
Write-Log "===== AMI Pre-Warming Complete =====" "Green"
