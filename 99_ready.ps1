# ============================================================
# 99_ready.ps1
# Shows the ready summary and waits for keypress.
# Reads everything from session.json.
# ============================================================

$SessionFile = "C:\git\Admin\logs\session.json"

$EngineMap = @{
    "mssql"    = @{ Hostname = "demo-mssql";    Port = 1433; Display = "SQL Server"  }
    "postgres" = @{ Hostname = "demo-postgres"; Port = 5432; Display = "PostgreSQL"  }
    "mysql"    = @{ Hostname = "demo-mysql";    Port = 3306; Display = "MySQL"       }
    "oracle"   = @{ Hostname = "demo-oracle";   Port = 1521; Display = "Oracle"      }
}

$Session         = Get-Content $SessionFile -Raw | ConvertFrom-Json
$SelectedEngines = $Session.SelectedEngines
$EngineIpMap     = $Session.EngineIpMap
$SessionId       = $Session.SessionId
if (-not $SessionId) { $SessionId = "unknown" }

Write-Host ("  " + ("─" * 62)) -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Your environment is ready!" -ForegroundColor Green
Write-Host ""

foreach ($Engine in $SelectedEngines) {
    if (-not $EngineMap.ContainsKey($Engine)) { continue }

    $EngineHostname = $EngineMap[$Engine].Hostname
    $EnginePort     = $EngineMap[$Engine].Port
    $EngineDisplay  = $EngineMap[$Engine].Display
    $EngineIp       = $EngineIpMap.$Engine
    if (-not $EngineIp) { $EngineIp = "not found" }
    $Pad            = " " * [Math]::Max(0, 12 - $EngineDisplay.Length)

    Write-Host "  $EngineDisplay$Pad" -ForegroundColor DarkGray -NoNewline
    Write-Host "$EngineHostname,$EnginePort" -ForegroundColor White -NoNewline
    Write-Host "  ($EngineIp)" -ForegroundColor DarkGray
}

Write-Host "  ADO Server  " -ForegroundColor DarkGray -NoNewline
Write-Host "http://rg-app01:8080" -ForegroundColor White

Write-Host "  Session ID  " -ForegroundColor DarkGray -NoNewline
Write-Host $SessionId -ForegroundColor White

Write-Host ""
Write-Host ("  " + ("─" * 62)) -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Good luck with your demo!" -ForegroundColor DarkGray
Write-Host ""

$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")