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
    @{ InstanceId = "unknown"; StackName = "unknown"; EnginesCsv = "mssql"; SelectedEngines = @("mssql"); IsBuildEc2 = $false; BuildContainerArns = @{} } `
        | ConvertTo-Json | Out-File $SessionFile
    exit 0
}

Write-Log "===== Reading instance metadata ====="
Write-Host "  >>  " -NoNewline -ForegroundColor Cyan
Write-Host "Reading instance metadata..."

$InstanceId        = "unknown"
$StackName         = "unknown"
$EnginesCsv        = "mssql"
$IsBuildEc2        = $false
$BuildContainerArns = @{}

# ── Step 1: Instance ID (own try — always works if IMDS is reachable) ─────────
try {
    $Token = Invoke-RestMethod `
        -Uri    "http://169.254.169.254/latest/api/token" `
        -Method PUT `
        -Headers @{ "X-aws-ec2-metadata-token-ttl-seconds" = "60" } `
        -TimeoutSec 5

    $imdsHeaders = @{ "X-aws-ec2-metadata-token" = $Token }

    $InstanceId = Invoke-RestMethod `
        -Uri     "http://169.254.169.254/latest/meta-data/instance-id" `
        -Headers $imdsHeaders -TimeoutSec 5

    Write-Log "Instance ID: $InstanceId"

    # ── Step 2: CFN stack name tag (only present on demo environment EC2s) ──
    try {
        $StackName = Invoke-RestMethod `
            -Uri     "http://169.254.169.254/latest/meta-data/tags/instance/aws:cloudformation:stack-name" `
            -Headers $imdsHeaders -TimeoutSec 5
    } catch { $StackName = "unknown" }

    # ── Step 3: Engines tag (only present on demo environment EC2s) ─────────
    try {
        $EnginesCsv = Invoke-RestMethod `
            -Uri     "http://169.254.169.254/latest/meta-data/tags/instance/Engines" `
            -Headers $imdsHeaders -TimeoutSec 5
    } catch { $EnginesCsv = "unknown" }

} catch {
    Write-Host "  !!  " -NoNewline -ForegroundColor Yellow
    Write-Host "IMDS not reachable — cannot read instance metadata" -ForegroundColor Yellow
    Write-Log "IMDS error: $($_.Exception.Message)"
}

# ── Step 4: If no CFN stack tag, check whether this is the Build EC2 ─────────
if ($StackName -eq "unknown" -and $InstanceId -ne "unknown") {
    Write-Log "No CFN stack tag — checking for Build EC2 via AWS CLI..."

    try {
        $allTags = aws ec2 describe-tags `
            --filters "Name=resource-id,Values=$InstanceId" `
            --query   "Tags" `
            --output  json | ConvertFrom-Json

        $namTag = ($allTags | Where-Object { $_.Key -eq "Name" }).Value

        if ($namTag -eq "rg-se-demo-build-ec2") {
            $IsBuildEc2 = $true
            $StackName  = "build"
            Write-Log "Build EC2 confirmed"

            # Discover which engines have active containers tracked on this instance
            $knownEngines = @("mssql", "postgres", "mysql", "oracle")
            $activeEngines = @()
            foreach ($engine in $knownEngines) {
                $arn = ($allTags | Where-Object { $_.Key -eq "BuildContainer-$engine" }).Value
                if ($arn) {
                    $activeEngines    += $engine
                    $BuildContainerArns[$engine] = $arn
                }
            }

            $EnginesCsv = if ($activeEngines.Count -gt 0) { $activeEngines -join "," } else { "none" }
            Write-Log "Active build containers: $EnginesCsv"
        } else {
            Write-Log "Name tag is '$namTag' — not a known Build EC2, no stack tag found"
        }
    } catch {
        Write-Log "AWS CLI tag lookup failed: $($_.Exception.Message)"
    }
}

# ── Step 5: Resolve engine list ───────────────────────────────────────────────
$SelectedEngines = switch ($EnginesCsv) {
    "all"  { @("mssql", "postgres", "mysql", "oracle") }
    "none" { @() }
    default { @($EnginesCsv.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
}

if ($StackName -ne "unknown") {
    Write-Host "  OK  " -NoNewline -ForegroundColor Green
    Write-Host "Instance: $InstanceId  |  Stack: $StackName  |  Engines: $EnginesCsv" -ForegroundColor Gray
    Write-Log  "Instance: $InstanceId  |  Stack: $StackName  |  Engines: $EnginesCsv"
} else {
    Write-Host "  !!  " -NoNewline -ForegroundColor Yellow
    Write-Host "Stack name not found — container IPs cannot be looked up" -ForegroundColor Yellow
    Write-Log "Stack name unknown after all lookups"
}

# ── Step 6: Write session.json ────────────────────────────────────────────────
@{
    InstanceId          = $InstanceId
    StackName           = $StackName
    EnginesCsv          = $EnginesCsv
    SelectedEngines     = $SelectedEngines
    IsBuildEc2          = $IsBuildEc2
    BuildContainerArns  = $BuildContainerArns   # task ARNs keyed by engine, for IP lookup
} | ConvertTo-Json -Depth 3 | Out-File -FilePath $SessionFile -Encoding UTF8

Write-Host ""
Write-Log "===== Metadata complete — session.json written ====="