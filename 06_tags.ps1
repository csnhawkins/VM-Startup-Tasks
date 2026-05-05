# ============================================================
# 06_tags.ps1
# Applies session tags to EC2 instance and ECS tasks.
# Reads from session.json, writes SessionId back to it.
# ============================================================

$LogFile     = "C:\git\Admin\logs\06_tags.log"
$SessionFile = "C:\git\Admin\logs\session.json"
$Region      = "eu-west-1"

New-Item -Path "C:\git\Admin\logs" -ItemType Directory -Force | Out-Null

function Write-Log {
    param([string]$Message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts  $Message" | Out-File -FilePath $LogFile -Append
}

$Session         = Get-Content $SessionFile -Raw | ConvertFrom-Json
$InstanceId      = $Session.InstanceId
$StackName       = $Session.StackName
$SelectedEngines = $Session.SelectedEngines
$EngineArnMap    = $Session.EngineArnMap

Write-Log "===== Applying session tags ====="
Write-Host "  >>  " -NoNewline -ForegroundColor Red
Write-Host "Applying session tags..."

$LaunchDate = Get-Date -Format "yyyyMMdd-HHmm"
$SessionId  = if ($StackName -and $StackName -ne "unknown") {
    "$StackName-$LaunchDate"
} else {
    "session-$LaunchDate"
}

try {
    if ($InstanceId -and $InstanceId -ne "unknown") {
        aws ec2 create-tags `
            --resources $InstanceId `
            --tags Key=SessionId,Value=$SessionId Key=LaunchDate,Value=$LaunchDate `
            --region $Region 2>$null
        Write-Log "EC2 tagged: $SessionId"
    }

    foreach ($Engine in $SelectedEngines) {
        $Arn = $EngineArnMap.$Engine
        if ($Arn) {
            aws ecs tag-resource `
                --resource-arn $Arn `
                --tags key=SessionId,value=$SessionId key=LaunchDate,value=$LaunchDate `
                --region $Region 2>$null
            Write-Log "$Engine task tagged: $SessionId"
        }
    }

    Write-Host "  OK  " -NoNewline -ForegroundColor Green
    Write-Host "Session tags applied" -ForegroundColor Gray
} catch {
    Write-Host "  !!  " -NoNewline -ForegroundColor Yellow
    Write-Host "Could not apply session tags — non-critical" -ForegroundColor Yellow
    Write-Log "WARN: $($_.Exception.Message)"
}

# Write SessionId back to session.json for 99_ready
$Session | Add-Member -NotePropertyName "SessionId" -NotePropertyValue $SessionId -Force
$Session | ConvertTo-Json -Depth 5 | Out-File -FilePath $SessionFile -Encoding UTF8

Write-Host ""
Write-Log "===== Tags complete ====="