# ============================================================
# 05_connectivity.ps1
# Verifies TCP connectivity to each provisioned database engine.
# Reads engine list from session.json.
# ============================================================

$LogFile     = "C:\git\Admin\logs\05_connectivity.log"
$SessionFile = "C:\git\Admin\logs\session.json"

New-Item -Path "C:\git\Admin\logs" -ItemType Directory -Force | Out-Null

function Write-Log {
    param([string]$Message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts  $Message" | Out-File -FilePath $LogFile -Append
}

$EngineMap = @{
    "mssql"    = @{ Hostname = "demo-mssql";    Port = 1433; Display = "SQL Server"  }
    "postgres" = @{ Hostname = "demo-postgres"; Port = 5432; Display = "PostgreSQL"  }
    "mysql"    = @{ Hostname = "demo-mysql";    Port = 3306; Display = "MySQL"       }
    "oracle"   = @{ Hostname = "demo-oracle";   Port = 1521; Display = "Oracle"      }
}

$Session         = Get-Content $SessionFile -Raw | ConvertFrom-Json
$SelectedEngines = $Session.SelectedEngines

Write-Log "===== Verifying connectivity ====="
Write-Host "  >>  " -NoNewline -ForegroundColor Red
Write-Host "Verifying database connectivity..."

$MaxRetries = 5

foreach ($Engine in $SelectedEngines) {
    if (-not $EngineMap.ContainsKey($Engine)) { continue }

    $EngineHostname = $EngineMap[$Engine].Hostname
    $EnginePort     = $EngineMap[$Engine].Port
    $EngineDisplay  = $EngineMap[$Engine].Display
    $Connected      = $false

    for ($i = 1; $i -le $MaxRetries; $i++) {
        try {
            $tcp = New-Object System.Net.Sockets.TcpClient
            $tcp.Connect($EngineHostname, $EnginePort)
            $tcp.Close()
            $Connected = $true
            break
        } catch {
            if ($i -lt $MaxRetries) {
                Write-Host "      $EngineDisplay warming up... ($i of $MaxRetries)" -ForegroundColor DarkGray
                Start-Sleep -Seconds 10
            }
        }
    }

    if ($Connected) {
        Write-Host "  OK  " -NoNewline -ForegroundColor Green
        Write-Host "$EngineDisplay is ready" -ForegroundColor Gray
        Write-Log "OK: $Engine on $EngineHostname`:$EnginePort"
    } else {
        Write-Host "  !!  " -NoNewline -ForegroundColor Yellow
        Write-Host "$EngineDisplay not responding yet — may still be restoring" -ForegroundColor Yellow
        Write-Log "WARN: $Engine not responding"
    }
}

Write-Host ""
Write-Log "===== Connectivity check complete ====="