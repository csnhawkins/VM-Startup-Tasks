# ============================================================
# 04_services.ps1
# Starts local Windows services required for the demo.
# Add new services to the $Services array as needed.
# ============================================================

$LogFile = "C:\git\Admin\logs\04_services.log"

New-Item -Path "C:\git\Admin\logs" -ItemType Directory -Force | Out-Null

function Write-Log {
    param([string]$Message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts  $Message" | Out-File -FilePath $LogFile -Append
}

Write-Log "===== Starting services ====="
Write-Host "  >>  " -NoNewline -ForegroundColor Red
Write-Host "Starting local services..."

$Services = @(
    @{ Name = "W3SVC";       Display = "IIS"        },
    @{ Name = "TfsJobAgent"; Display = "ADO Server"  }
    # Add more services here as needed:
    # @{ Name = "jenkins";   Display = "Jenkins"     }
    # @{ Name = "OctopusDeploy"; Display = "Octopus" }
)

foreach ($Svc in $Services) {
    $s = Get-Service -Name $Svc.Name -ErrorAction SilentlyContinue
    if ($s) {
        if ($s.Status -ne "Running") {
            Start-Service -Name $Svc.Name -ErrorAction SilentlyContinue
            Write-Host "  OK  " -NoNewline -ForegroundColor Green
            Write-Host "$($Svc.Display) started" -ForegroundColor Gray
            Write-Log "Started: $($Svc.Name)"
        } else {
            Write-Host "  OK  " -NoNewline -ForegroundColor Green
            Write-Host "$($Svc.Display) already running" -ForegroundColor Gray
            Write-Log "Already running: $($Svc.Name)"
        }
    } else {
        Write-Host "  !!  " -NoNewline -ForegroundColor Yellow
        Write-Host "$($Svc.Display) service not found" -ForegroundColor Yellow
        Write-Log "Not found: $($Svc.Name)"
    }
}

Write-Host ""
Write-Log "===== Services complete ====="