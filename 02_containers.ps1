# ============================================================
# 02_containers.ps1
# Finds ECS containers for this stack and captures their IPs.
# Reads from session.json, writes results back to session.json.
# ============================================================

$LogFile     = "C:\git\Admin\logs\02_containers.log"
$SessionFile = "C:\git\Admin\logs\session.json"
$Region      = "eu-west-1"
$Cluster     = "rg-se-demo-cluster"

New-Item -Path "C:\git\Admin\logs" -ItemType Directory -Force | Out-Null

function Write-Log {
    param([string]$Message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts  $Message" | Out-File -FilePath $LogFile -Append
}

function Test-AwsCredentials {
    try {
        $creds = aws sts get-caller-identity --query "Account" --output text 2>$null
        if ($creds) {
            return $true
        }
        return $false
    } catch {
        return $false
    }
}

# Read session.json
$Session = Get-Content $SessionFile -Raw | ConvertFrom-Json
$StackName        = $Session.StackName
$IsBuildEc2       = $Session.IsBuildEc2
$BuildContainerArns = $Session.BuildContainerArns
$SelectedEngines  = $Session.SelectedEngines

# Check AWS credentials are available
if (-not (Test-AwsCredentials)) {
    Write-Host "  !!  " -NoNewline -ForegroundColor Yellow
    Write-Host "AWS credentials not available — cannot look up container IPs" -ForegroundColor Yellow
    Write-Host "        Attach an IAM role with ECS/EC2 permissions, then rerun scripts." -ForegroundColor DarkGray
    Write-Log "AWS credentials not available — cannot proceed"
    exit 1
}

$EngineIpMap  = @{}
$EngineArnMap = @{}

# ── Build EC2 scenario: use pre-recorded task ARNs ──────────────────────────
if ($IsBuildEc2 -and $BuildContainerArns -and $BuildContainerArns.PSObject.Properties.Count -gt 0) {
    Write-Log "===== Lookup mode: Build EC2 (using BuildContainerArns) ====="
    Write-Host "  >>  " -NoNewline -ForegroundColor Red
    Write-Host "Finding database containers (Build EC2)..."

    foreach ($Engine in $BuildContainerArns.PSObject.Properties.Name) {
        $Arn = $BuildContainerArns.$Engine

        try {
            $Details = aws ecs describe-tasks `
                --cluster $Cluster `
                --tasks $Arn `
                --region $Region `
                --query "tasks[0].attachments[0].details" `
                --output json 2>$null | ConvertFrom-Json

            $IpDetail = $Details | Where-Object { $_.name -eq "privateIPv4Address" }

            if ($IpDetail) {
                $EngineIpMap[$Engine]  = $IpDetail.value
                $EngineArnMap[$Engine] = $Arn
                Write-Host "  OK  " -NoNewline -ForegroundColor Green
                Write-Host "$Engine container found  ($($IpDetail.value))" -ForegroundColor Gray
                Write-Log "$Engine -> $($IpDetail.value)"
            }
        } catch {
            Write-Host "  !!  " -NoNewline -ForegroundColor Yellow
            Write-Host "Failed to describe task for $Engine" -ForegroundColor Yellow
            Write-Log "Error describing task $Arn for $Engine : $($_.Exception.Message)"
        }
    }
}
# ── Normal stack scenario: search by StackName tag ────────────────────────────
elseif ($StackName -and $StackName -ne "unknown") {
    Write-Log "===== Lookup mode: CloudFormation Stack ($StackName) ====="
    Write-Host "  >>  " -NoNewline -ForegroundColor Red
    Write-Host "Finding database containers..."

    $TaskArns = aws ecs list-tasks `
        --cluster $Cluster `
        --region $Region `
        --desired-status RUNNING `
        --query "taskArns" `
        --output json 2>$null | ConvertFrom-Json

    foreach ($Arn in $TaskArns) {
        $Tags = aws ecs list-tags-for-resource `
            --resource-arn $Arn `
            --region $Region `
            --query "tags" `
            --output json 2>$null | ConvertFrom-Json

        $StackTag  = $Tags | Where-Object { $_.key -eq "StackName" -and $_.value -eq $StackName }
        $EngineTag = $Tags | Where-Object { $_.key -eq "Engine" }

        if ($StackTag -and $EngineTag) {
            $Details  = aws ecs describe-tasks `
                --cluster $Cluster `
                --tasks $Arn `
                --region $Region `
                --query "tasks[0].attachments[0].details" `
                --output json 2>$null | ConvertFrom-Json

            $IpDetail = $Details | Where-Object { $_.name -eq "privateIPv4Address" }

            if ($IpDetail) {
                $Engine              = $EngineTag.value
                $EngineIpMap[$Engine]  = $IpDetail.value
                $EngineArnMap[$Engine] = $Arn
                Write-Host "  OK  " -NoNewline -ForegroundColor Green
                Write-Host "$Engine container found  ($($IpDetail.value))" -ForegroundColor Gray
                Write-Log "$Engine -> $($IpDetail.value)"
            }
        }
    }
} else {
    Write-Host "  !!  " -NoNewline -ForegroundColor Yellow
    Write-Host "Stack name not found and not a Build EC2 — skipping container lookup" -ForegroundColor Yellow
    Write-Log "No stack name available and IsBuildEc2 is false"
    exit 0
}

if ($EngineIpMap.Count -eq 0) {
    Write-Host "  XX  " -NoNewline -ForegroundColor Red
    Write-Host "Could not find any containers" -ForegroundColor Red
    Write-Log "ERROR: No containers found"
    exit 1
}

# Update session.json with discovered IPs and ARNs
$Session | Add-Member -NotePropertyName "EngineIpMap"  -NotePropertyValue $EngineIpMap  -Force
$Session | Add-Member -NotePropertyName "EngineArnMap" -NotePropertyValue $EngineArnMap -Force
$Session | ConvertTo-Json -Depth 5 | Out-File -FilePath $SessionFile -Encoding UTF8

Write-Host ""
Write-Log "===== Container lookup complete ====="