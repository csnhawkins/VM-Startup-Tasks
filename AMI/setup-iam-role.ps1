# ============================================================
# setup-iam-role.ps1
# Creates and attaches IAM role for Build EC2 instance
# Run this ONCE to set up permissions for AWS CLI access
# ============================================================

$RoleName           = "rg-se-demo-build-ec2-role"
$InstanceProfileName = "rg-se-demo-build-ec2-profile"
$DefaultRegion      = "eu-west-1"
$DefaultInstanceId  = "i-09852319a236f4175"
$Cluster            = "rg-se-demo-cluster"

Write-Host "Setting up IAM role for Build EC2..." -ForegroundColor Cyan
Write-Host ""

# ── Step 1: Get Instance ID and Region from user ──────────────────────────────
Write-Host "  >>  " -NoNewline -ForegroundColor White
Write-Host "Instance Details"

$InstanceIdInput = Read-Host "Enter Build EC2 Instance ID (default: $DefaultInstanceId)"
$InstanceId = if ($InstanceIdInput) { $InstanceIdInput } else { $DefaultInstanceId }

$RegionInput = Read-Host "Enter AWS Region (default: $DefaultRegion)"
$Region = if ($RegionInput) { $RegionInput } else { $DefaultRegion }

Write-Host "  OK  " -NoNewline -ForegroundColor Green
Write-Host "Using Instance: $InstanceId in region: $Region" -ForegroundColor Gray
Write-Host ""

# ── Step 2: Check if role already exists ──────────────────────────────────────
Write-Host "  >>  " -NoNewline -ForegroundColor White
Write-Host "Checking if role already exists..."

$RoleExists = $false

$roleCheck = aws iam get-role `
    --role-name $RoleName `
    --output json 2>&1

if ($LASTEXITCODE -eq 0) {
    $RoleExists = $true
    Write-Host "  OK  " -NoNewline -ForegroundColor Green
    Write-Host "Role already exists" -ForegroundColor Gray
} else {
    Write-Host "  ..  " -NoNewline -ForegroundColor Gray
    Write-Host "Role does not exist — creating..." -ForegroundColor Gray
}

# ── Step 3: Create IAM role if needed ─────────────────────────────────────────
if (-not $RoleExists) {
    $TrustPolicy = @{
        Version = "2012-10-17"
        Statement = @(
            @{
                Effect = "Allow"
                Principal = @{
                    Service = "ec2.amazonaws.com"
                }
                Action = "sts:AssumeRole"
            }
        )
    } | ConvertTo-Json -Depth 10

    Write-Host "  >>  " -NoNewline -ForegroundColor White
    Write-Host "Creating IAM role..."

    try {
        $createRoleResult = aws iam create-role `
            --role-name $RoleName `
            --assume-role-policy-document $TrustPolicy `
            --output json 2>&1

        if ($LASTEXITCODE -eq 0) {
            Write-Host "  OK  " -NoNewline -ForegroundColor Green
            Write-Host "Role created" -ForegroundColor Gray
        } else {
            Write-Host "  !!  " -NoNewline -ForegroundColor Red
            Write-Host "Failed to create role (exit code: $LASTEXITCODE)" -ForegroundColor Red
            Write-Host "       Output: $createRoleResult" -ForegroundColor Red
            exit 1
        }
    } catch {
        Write-Host "  !!  " -NoNewline -ForegroundColor Red
        Write-Host "Failed to create role: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

# ── Step 4: Create inline policy for ECS/EC2 access ──────────────────────────
Write-Host "  >>  " -NoNewline -ForegroundColor White
Write-Host "Attaching ECS/EC2 permissions..."

$InlinePolicy = @{
    Version = "2012-10-17"
    Statement = @(
        @{
            Effect = "Allow"
            Action = @(
                "ecs:DescribeTasks",
                "ecs:ListTasks",
                "ecs:ListTagsForResource"
            )
            Resource = "*"
        },
        @{
            Effect = "Allow"
            Action = @(
                "ec2:DescribeTags",
                "ec2:DescribeInstances"
            )
            Resource = "*"
        },
        @{
            Effect = "Allow"
            Action = @(
                "cloudformation:DescribeStacks",
                "cloudformation:ListStackResources"
            )
            Resource = "*"
        }
    )
} | ConvertTo-Json -Depth 10

try {
    $putPolicyResult = aws iam put-role-policy `
        --role-name $RoleName `
        --policy-name "EcsEc2Access" `
        --policy-document $InlinePolicy 2>&1

    if ($LASTEXITCODE -ne 0) {
        Write-Host "  !!  " -NoNewline -ForegroundColor Red
        Write-Host "Failed to attach policy (exit code: $LASTEXITCODE)" -ForegroundColor Red
        Write-Host "       Output: $putPolicyResult" -ForegroundColor Red
        exit 1
    }

    Write-Host "  OK  " -NoNewline -ForegroundColor Green
    Write-Host "Permissions attached" -ForegroundColor Gray
} catch {
    Write-Host "  !!  " -NoNewline -ForegroundColor Red
    Write-Host "Failed to attach policy: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# ── Step 5: Create instance profile ───────────────────────────────────────────
Write-Host "  >>  " -NoNewline -ForegroundColor White
Write-Host "Creating instance profile..."

$ProfileExists = $false

# First, try to get the profile to see if it exists
$profileCheck = aws iam get-instance-profile `
    --instance-profile-name $InstanceProfileName `
    --output json 2>&1

if ($LASTEXITCODE -eq 0) {
    $ProfileExists = $true
    Write-Host "  OK  " -NoNewline -ForegroundColor Green
    Write-Host "Profile already exists" -ForegroundColor Gray
} else {
    Write-Host "  ..  " -NoNewline -ForegroundColor Gray
    Write-Host "Profile does not exist — creating..." -ForegroundColor Gray

    $createResult = aws iam create-instance-profile `
        --instance-profile-name $InstanceProfileName `
        --output json 2>&1

    if ($LASTEXITCODE -eq 0) {
        Write-Host "  OK  " -NoNewline -ForegroundColor Green
        Write-Host "Profile created" -ForegroundColor Gray
        $ProfileExists = $true
        
        # Wait for profile to be available in IAM (propagation delay)
        Write-Host "        Waiting for profile propagation..." -ForegroundColor DarkGray
        Start-Sleep -Seconds 3
    } else {
        Write-Host "  !!  " -NoNewline -ForegroundColor Red
        Write-Host "Failed to create profile (exit code: $LASTEXITCODE)" -ForegroundColor Red
        Write-Host "       Output: $createResult" -ForegroundColor Red
        exit 1
    }
}

# ── Step 6: Add role to instance profile ──────────────────────────────────────
Write-Host "  >>  " -NoNewline -ForegroundColor White
Write-Host "Adding role to instance profile..."

# Check if role is already in profile
$profile = aws iam get-instance-profile `
    --instance-profile-name $InstanceProfileName `
    --output json 2>&1 | ConvertFrom-Json

if ($LASTEXITCODE -ne 0) {
    Write-Host "  !!  " -NoNewline -ForegroundColor Red
    Write-Host "Failed to get instance profile (exit code: $LASTEXITCODE)" -ForegroundColor Red
    exit 1
}

$roleInProfile = $profile.InstanceProfile.Roles | Where-Object { $_.RoleName -eq $RoleName }

if (-not $roleInProfile) {
    $addResult = aws iam add-role-to-instance-profile `
        --instance-profile-name $InstanceProfileName `
        --role-name $RoleName 2>&1

    if ($LASTEXITCODE -ne 0) {
        Write-Host "  !!  " -NoNewline -ForegroundColor Red
        Write-Host "Failed to add role to profile (exit code: $LASTEXITCODE)" -ForegroundColor Red
        Write-Host "       Output: $addResult" -ForegroundColor Red
        exit 1
    }
}

Write-Host "  OK  " -NoNewline -ForegroundColor Green
Write-Host "Role added to profile" -ForegroundColor Gray

# ── Step 7: Attach instance profile to this EC2 instance ──────────────────────
Write-Host "  >>  " -NoNewline -ForegroundColor White
Write-Host "Attaching profile to instance..."

# Give IAM a moment to fully propagate the profile
Write-Host "        Waiting before attachment..." -ForegroundColor DarkGray
Start-Sleep -Seconds 2

try {
    $attachResult = aws ec2 associate-iam-instance-profile `
        --iam-instance-profile Name=$InstanceProfileName `
        --instance-id $InstanceId `
        --region $Region `
        --output json 2>&1

    if ($LASTEXITCODE -ne 0) {
        Write-Host "  !!  " -NoNewline -ForegroundColor Red
        Write-Host "Failed to attach profile (exit code: $LASTEXITCODE)" -ForegroundColor Red
        Write-Host "       Output: $attachResult" -ForegroundColor Red
        exit 1
    }

    Write-Host "  OK  " -NoNewline -ForegroundColor Green
    Write-Host "Profile attached to instance" -ForegroundColor Gray
} catch {
    Write-Host "  !!  " -NoNewline -ForegroundColor Red
    Write-Host "Failed to attach profile: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# ── Step 8: Verify credentials work ──────────────────────────────────────────
Write-Host "  >>  " -NoNewline -ForegroundColor White
Write-Host "Verifying AWS credentials..."

# Give the credentials a moment to propagate
Start-Sleep -Seconds 2

try {
    $accountId = aws sts get-caller-identity `
        --query "Account" `
        --output text 2>&1

    if ($LASTEXITCODE -eq 0) {
        Write-Host "  OK  " -NoNewline -ForegroundColor Green
        Write-Host "AWS credentials working (Account: $accountId)" -ForegroundColor Gray
    } else {
        Write-Host "  !!  " -NoNewline -ForegroundColor Yellow
        Write-Host "Credentials not yet available — wait 30 seconds then verify manually" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  !!  " -NoNewline -ForegroundColor Yellow
    Write-Host "Credentials not yet available — wait 30 seconds then rerun scripts" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Setup complete! You can now run the VM startup scripts." -ForegroundColor Green
