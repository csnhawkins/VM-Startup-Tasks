# ============================================================
# 00_git_pull.ps1
# Pulls latest scripts from Git before anything else runs.
# If pull fails, continues with cached scripts — non-fatal.
# ============================================================

$LogFile  = "C:\git\Admin\logs\00_git_pull.log"
$RepoPath = "C:\git\Admin\VM-Startup-Tasks"

New-Item -Path "C:\git\Admin\logs" -ItemType Directory -Force | Out-Null

function Write-Log {
    param([string]$Message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts  $Message" | Out-File -FilePath $LogFile -Append
}

Write-Log "===== Git pull starting ====="

Write-Host "  >>  " -NoNewline -ForegroundColor Red
Write-Host "Pulling latest scripts from Git..."

try {
    Set-Location $RepoPath
    $result = git pull origin main 2>&1
    Write-Log $result
    Write-Host "  OK  " -NoNewline -ForegroundColor Green
    Write-Host "Scripts up to date" -ForegroundColor Gray
} catch {
    Write-Log "ERROR: Git pull failed — $($_.Exception.Message)"
    Write-Host "  !!  " -NoNewline -ForegroundColor Yellow
    Write-Host "Git pull failed — running with cached scripts" -ForegroundColor Yellow
}

Write-Host ""
Write-Log "===== Git pull complete ====="