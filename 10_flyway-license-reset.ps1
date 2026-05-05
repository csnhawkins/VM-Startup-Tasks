$allowedMachine = "WIN2016"
$currentMachine = $env:COMPUTERNAME

if ($currentMachine -ne $allowedMachine) {
    Write-Host "Not running cleanup. Machine name = $currentMachine"
    Write-Host "Press any key to exit..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    return
}

Write-Host "Running cleanup on approved machine: $currentMachine"
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
