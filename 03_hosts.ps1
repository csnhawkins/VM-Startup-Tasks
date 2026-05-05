# ============================================================
# 03_hosts.ps1
# Writes hosts file entries for all provisioned engines.
# Reads engine IPs from session.json.
# ============================================================

$LogFile     = "C:\git\Admin\logs\03_hosts.log"
$SessionFile = "C:\git\Admin\logs\session.json"

New-Item -Path "C:\git\Admin\logs" -ItemType Directory -Force | Out-Null

function Write-Log {
    param([string]$Message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts  $Message" | Out-File -FilePath $LogFile -Append
}

$EngineHostnameMap = @{
    "mssql"    = "demo-mssql"
    "postgres" = "demo-postgres"
    "mysql"    = "demo-mysql"
    "oracle"   = "demo-oracle"
}

$Session         = Get-Content $SessionFile -Raw | ConvertFrom-Json
$SelectedEngines = $Session.SelectedEngines
$EngineIpMap     = $Session.EngineIpMap

Write-Log "===== Writing hosts file ====="
Write-Host "  >>  " -NoNewline -ForegroundColor Red
Write-Host "Writing network configuration..."

$HostsFile = "C:\Windows\System32\drivers\etc\hosts"

$HostsContent = [System.IO.File]::ReadAllLines($HostsFile) | Where-Object {
    $_ -notmatch "demo-mssql"    -and
    $_ -notmatch "demo-postgres" -and
    $_ -notmatch "demo-mysql"    -and
    $_ -notmatch "demo-oracle"   -and
    $_ -notmatch "rg-app01"
}

$NewEntries = @("127.0.0.1`trg-app01`t# Local services")

foreach ($Engine in $SelectedEngines) {
    $Ip = $EngineIpMap.$Engine
    if ($Ip -and $EngineHostnameMap.ContainsKey($Engine)) {
        $Hostname    = $EngineHostnameMap[$Engine]
        $NewEntries += "$Ip`t$Hostname`t# $Engine container"
        Write-Log "Hosts: $Ip -> $Hostname"
    }
}

$FinalContent = ($HostsContent + $NewEntries) -join "`r`n"
[System.IO.File]::WriteAllText($HostsFile, $FinalContent)

Write-Host "  OK  " -NoNewline -ForegroundColor Green
Write-Host "Hosts file updated" -ForegroundColor Gray
Write-Host ""
Write-Log "===== Hosts file complete ====="