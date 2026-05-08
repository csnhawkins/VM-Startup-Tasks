# ============================================================
# 00_warmup.ps1
# Monitors EBS volume warmup after boot.
# Shows a live progress bar — runs FIRST before git pull
# so the SE sees feedback immediately on logon.
# Uses carriage return to update a single line in place
# so moving the window does not break the display.
# ============================================================

# Disable QuickEdit mode to prevent window freeze when clicked/moved
if (-not ([System.Management.Automation.PSTypeName]'ConsoleHelper').Type) {
    Add-Type -TypeDefinition @'
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
'@
}
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

$LogFile    = "C:\git\Admin\logs\00_warmup.log"
$MaxMinutes = 15
$PollSecs   = 3
$WarmMBs    = 5
$BarWidth   = 46

New-Item -Path "C:\git\Admin\logs" -ItemType Directory -Force | Out-Null

Write-Host ""
Write-Host "  ██████╗ ███████╗██████╗  ██████╗  █████╗ ████████╗███████╗" -ForegroundColor Red
Write-Host "  ██╔══██╗██╔════╝██╔══██╗██╔════╝ ██╔══██╗╚══██╔══╝██╔════╝" -ForegroundColor Red
Write-Host "  ██████╔╝█████╗  ██║  ██║██║  ███╗███████║   ██║   █████╗  " -ForegroundColor Red
Write-Host "  ██╔══██╗██╔══╝  ██║  ██║██║   ██║██╔══██║   ██║   ██╔══╝  " -ForegroundColor Red
Write-Host "  ██║  ██║███████╗██████╔╝╚██████╔╝██║  ██║   ██║   ███████╗" -ForegroundColor Red
Write-Host "  ╚═╝  ╚═╝╚══════╝╚═════╝  ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚══════╝" -ForegroundColor Red
Write-Host ""
Write-Host "  Demo Environment" -ForegroundColor White
Write-Host "  Starting up — please wait..." -ForegroundColor DarkGray
Write-Host ""
Write-Host ("  " + ("─" * 62)) -ForegroundColor DarkGray
Write-Host ""

function Write-Log {
    param([string]$Message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts  $Message" | Out-File -FilePath $LogFile -Append
}

function Get-DiskReadMBs {
    try {
        $s = Get-Counter '\PhysicalDisk(_Total)\Disk Read Bytes/sec' `
            -SampleInterval 1 -MaxSamples 1 -ErrorAction SilentlyContinue
        return [Math]::Round($s.CounterSamples[0].CookedValue / 1MB, 1)
    } catch { return 0 }
}

function Write-ProgressLine {
    param([double]$ReadMBs, [int]$ElapsedSecs)

    $progress = [Math]::Min(99, [Math]::Max(0,
        100 - ([Math]::Max(0, $ReadMBs - $WarmMBs) /
               [Math]::Max(1, $script:InitialMBs - $WarmMBs) * 100)
    ))

    $filled  = [Math]::Floor($BarWidth * $progress / 100)
    $empty   = $BarWidth - $filled
    $bar     = ([string][char]0x2588 * $filled) + ([string][char]0x2591 * $empty)
    $pct     = "$([Math]::Floor($progress))%".PadLeft(4)
    $elapsed = [TimeSpan]::FromSeconds($ElapsedSecs).ToString('mm\:ss')

    # Calculate ETA based on progress rate
    $eta = if ($ElapsedSecs -gt 10 -and $progress -gt 5 -and $progress -lt 99) {
        $remainingPct = 100 - $progress
        $rate = $progress / $ElapsedSecs
        $etaSecs = [Math]::Max(0, $remainingPct / [Math]::Max(0.01, $rate))
        $etaTime = [TimeSpan]::FromSeconds($etaSecs)
        if ($etaSecs -lt 60) {
            "ETA <1 min  "
        } else {
            "ETA " + $etaTime.ToString('m\m\ s\s').PadRight(8)
        }
    } else {
        "            "
    }

    $status = switch ($true) {
        ($ReadMBs -gt 100)      { "Loading system files      " }
        ($ReadMBs -gt 50)       { "Restoring application data" }
        ($ReadMBs -gt 20)       { "Almost there              " }
        ($ReadMBs -gt 10)       { "Finishing up              " }
        ($ReadMBs -gt $WarmMBs) { "Nearly ready              " }
        default                 { "Warmed up                 " }
    }

    $colour = if ($ReadMBs -gt 20) { "Yellow" } else { "Green" }
    $line   = "  [$bar] $pct   $($ReadMBs.ToString('F1').PadLeft(6)) MB/s   $elapsed   $eta  $status  "
    Write-Host "`r$line" -NoNewline -ForegroundColor $colour
}

# ── Check if already warm ─────────────────────────────────────
$script:InitialMBs = Get-DiskReadMBs

if ($script:InitialMBs -lt $WarmMBs) {
    Write-Log "Disk already warm ($($script:InitialMBs) MB/s) — skipping warmup"
    exit 0
}

Write-Log "===== Warmup starting. Initial: $($script:InitialMBs) MB/s ====="

# ── Static header — drawn once only ──────────────────────────
Clear-Host
Write-Host ""
Write-Host "  ██████╗ ███████╗██████╗  ██████╗  █████╗ ████████╗███████╗" -ForegroundColor Red
Write-Host "  ██╔══██╗██╔════╝██╔══██╗██╔════╝ ██╔══██╗╚══██╔══╝██╔════╝" -ForegroundColor Red
Write-Host "  ██████╔╝█████╗  ██║  ██║██║  ███╗███████║   ██║   █████╗  " -ForegroundColor Red
Write-Host "  ██╔══██╗██╔══╝  ██║  ██║██║   ██║██╔══██║   ██║   ██╔══╝  " -ForegroundColor Red
Write-Host "  ██║  ██║███████╗██████╔╝╚██████╔╝██║  ██║   ██║   ███████╗" -ForegroundColor Red
Write-Host "  ╚═╝  ╚═╝╚══════╝╚═════╝  ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚══════╝" -ForegroundColor Red
Write-Host ""
Write-Host ("  " + ([string][char]0x2500 * 62)) -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Warming up your environment — please wait..." -ForegroundColor White
Write-Host "  AWS is restoring EBS volume from snapshot..." -ForegroundColor DarkGray
Write-Host "  This typically takes 2-5 minutes on first boot." -ForegroundColor DarkGray
Write-Host ""

Write-ProgressLine -ReadMBs $script:InitialMBs -ElapsedSecs 0

# ── Warmup loop ───────────────────────────────────────────────
$StartTime      = Get-Date
$Warmed         = $false
$MaxSecs        = $MaxMinutes * 60
$ConsecutiveLow = 0
$LastMBs        = $script:InitialMBs

while (-not $Warmed) {
    Start-Sleep -Seconds $PollSecs

    $ElapsedSecs = [int](New-TimeSpan -Start $StartTime -End (Get-Date)).TotalSeconds
    $ReadMBs     = Get-DiskReadMBs
    $LastMBs     = $ReadMBs

    Write-ProgressLine -ReadMBs $ReadMBs -ElapsedSecs $ElapsedSecs

    if ($ReadMBs -lt $WarmMBs) { $ConsecutiveLow++ } else { $ConsecutiveLow = 0 }

    if ($ConsecutiveLow -ge 5 -or $ElapsedSecs -ge $MaxSecs) {
        $Warmed = $true
        Write-Log "Warmup complete after ${ElapsedSecs}s. Final: $ReadMBs MB/s"
    }
}

# ── Completion ────────────────────────────────────────────────
$TotalSecs = [int](New-TimeSpan -Start $StartTime -End (Get-Date)).TotalSeconds
$TotalMins = [Math]::Floor($TotalSecs / 60)
$TotalSec2 = $TotalSecs % 60
$TotalTime = [TimeSpan]::FromSeconds($TotalSecs).ToString('mm\:ss')
$doneBar   = [string][char]0x2588 * $BarWidth

# Overwrite progress line with completed bar
$doneLine = "  [$doneBar] 100%   $($LastMBs.ToString('F1').PadLeft(6)) MB/s   $TotalTime   Warmup complete    "
Write-Host "`r$doneLine" -ForegroundColor Green
Write-Host ""
Write-Host ""

# Human-friendly time description
$timeDesc = if ($TotalMins -eq 0) {
    "${TotalSec2} seconds"
} elseif ($TotalMins -eq 1) {
    "1 minute $TotalSec2 seconds"
} else {
    "$TotalMins minutes $TotalSec2 seconds"
}

Write-Host "  Environment warmed up in $timeDesc." -ForegroundColor Green
Write-Host ("  " + ([string][char]0x2500 * 62)) -ForegroundColor DarkGray
Write-Host ""

Write-Log "===== Warmup done in $timeDesc ====="
Start-Sleep -Seconds 1