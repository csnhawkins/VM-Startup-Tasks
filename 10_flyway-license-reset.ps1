# VM config check
if ($env:VM_CONFIG -ne 'SalesDemo_Containerized') {
    Write-Host "  !!  " -NoNewline -ForegroundColor Yellow
    Write-Host "VM_CONFIG is '$env:VM_CONFIG' — expected 'SalesDemo_Containerized'" -ForegroundColor Yellow
    Write-Host "        Set VM_CONFIG and reboot, then try again." -ForegroundColor DarkGray
    Write-Log "Wrong VM_CONFIG: '$env:VM_CONFIG'"
    exit 0
}

Write-Host "Running cleanup on approved machine: $env:VM_CONFIG"
Write-Host ""

Write-Host "Deleting environment variable REDGATE_LICENSING_PERMIT_PATH..."

$varName = "REDGATE_LICENSING_PERMIT_PATH"

# User-level variable
try {
    [Environment]::SetEnvironmentVariable($varName, $null, "User")
    Write-Host "User environment variable removed (if it existed)."
}
catch {
    Write-Warning "Could not remove User environment variable: $($_.Exception.Message)"
}

# Machine-level variable (may require admin)
try {
    [Environment]::SetEnvironmentVariable($varName, $null, "Machine")
    Write-Host "Machine environment variable removed (if it existed)."
}
catch {
    Write-Warning "Could not remove Machine environment variable (requires admin)."
}

function Remove-FileSafely($path) {
    if (Test-Path $path) {
        try {
            Remove-Item $path -Force
            Write-Host "Deleted: $path"
        }
        catch {
            Write-Warning "Failed to delete: $path"
        }
    }
    else {
        Write-Host "Not found: $path"
    }
}

Write-Host ""
Write-Host "Checking license files..."

Remove-FileSafely "C:\Program Files\Red Gate\Permits\permit.dat"
Remove-FileSafely "C:\Users\redgate\AppData\Roaming\Redgate\Flyway Desktop\permit.offline.jwt"
Remove-FileSafely "C:\Users\redgate\AppData\Roaming\Redgate\Flyway Desktop\permit.jwt"

Write-Host ""
Write-Host "Task completed."
