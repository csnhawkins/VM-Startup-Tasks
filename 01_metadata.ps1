# ============================================================
# 01_metadata.ps1
# Reads EC2 instance metadata and writes shared session.json
# that subsequent scripts read to get instance/stack/engine info.
# ============================================================

$LogFile     = "C:\git\Admin\logs\01_metadata.log"
$SessionFile = "C:\git\Admin\logs\session.json"

New-Item -Path "C:\git\Admin\logs" -ItemType Directory -Force | Out-Null

function Write-Log {
    param([string]$Message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts  $Message" | Out-File -FilePath $LogFile -Append
}

# VM config check
if ($env:VM_CONFIG -ne 'SalesDemo_Containerized') {
    Write-Host "  !!  " -NoNewline -ForegroundColor Yellow
    Write-Host "VM_CONFIG is '$env:VM_CONFIG' — expected 'SalesDemo_Containerized'" -ForegroundColor Yellow
    Write-Host "        Set VM_CONFIG and reboot, then try again." -ForegroundColor DarkGray
    Write-Log "Wrong VM_CONFIG: '$env:VM_CONFIG'"
    # Write fallback session so subsequent scripts still run
    @{ InstanceId = "unknown"; StackName = "unknown"; EnginesCsv = "mssql"; SelectedEngines = @("mssql") } `
        | ConvertTo-Json | Out-File $SessionFile
    exit 0
}

Write-Log "===== Reading instance metadata ====="
Write-Host "  >>  " -NoNewline -ForegroundColor Red
Write-Host "Reading instance metadata..."

$InstanceId = "unknown"
$StackName  = "unknown"
$EnginesCsv = "mssql"

try {
    $Token = Invoke-RestMethod `
        -Uri "http://169.254.169.254/latest/api/token" `
        -Method PUT `
        -Headers @{ "X-aws-ec2-metadata-token-ttl-seconds" = "60" } `
        -TimeoutSec 5

    $Headers = @{ "X-aws-ec2-metadata-token" = $Token }

    $InstanceId = Invoke-RestMethod `
        -Uri "http://169.254.169.254/latest/meta-data/instance-id" `
        -Headers $Headers -TimeoutSec 5

    $StackName = Invoke-RestMethod `
        -Uri "http://169.254.169.254/latest/meta-data/tags/instance/aws:cloudformation:stack-name" `
        -Headers $Headers -TimeoutSec 5

    $EnginesCsv = Invoke-RestMethod `
        -Uri "http://169.254.169.254/latest/meta-data/tags/instance/Engines" `
        -Headers $Headers -TimeoutSec 5

    Write-Host "  OK  " -NoNewline -ForegroundColor Green
    Write-Host "Instance: $InstanceId | Stack: $StackName | Engines: $EnginesCsv" -ForegroundColor Gray
    Write-Log "Instance: $InstanceId | Stack: $StackName | Engines: $EnginesCsv"

} catch {
    Write-Host "  !!  " -NoNewline -ForegroundColor Yellow
    Write-Host "Could not read instance metadata — using fallback (mssql only)" -ForegroundColor Yellow
    Write-Log "Metadata error: $($_.Exception.Message)"
}

$SelectedEngines = if ($EnginesCsv -eq "all") {
    @("mssql", "postgres", "mysql", "oracle")
} else {
    @($EnginesCsv.Trim())
}

# Write session.json for subsequent scripts to read
@{
    InstanceId       = $InstanceId
    StackName        = $StackName
    EnginesCsv       = $EnginesCsv
    SelectedEngines  = $SelectedEngines
} | ConvertTo-Json | Out-File -FilePath $SessionFile -Encoding UTF8

Write-Host ""
Write-Log "===== Metadata complete — session.json written ====="