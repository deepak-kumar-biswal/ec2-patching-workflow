# EC2 Patching Workflow - CloudFormation Deployment with Custom Documents
# This script deploys the hub stack with custom SSM documents and automatic sharing

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("dev", "test", "stage", "prod")]
    [string]$Environment,
    
    [string]$Region = "us-east-1",
    [string]$ParamsFile,
    [string]$SpokeAccounts,
    [string]$LambdaBucket,
    [string]$LambdaKey,
    [string]$ExternalId,
    [string]$NotificationEmail,
    [switch]$EnableScheduler,
    [switch]$DryRun,
    [switch]$Help
)

# Script directory and template path
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$TemplateFile = Join-Path $ScriptDir "..\cloudformation\hub-cfn.yaml"
$StackNamePrefix = "ec2-patch-hub"

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Blue
}

function Write-Success {
    param([string]$Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

function Show-Usage {
    @"
EC2 Patching Workflow - CloudFormation Deployment with Custom Documents

USAGE:
    .\deploy-with-custom-documents.ps1 -Environment <ENV> [OPTIONS]

PARAMETERS:
    -Environment          Environment (dev, test, stage, prod) [required]
    -Region              AWS region (default: us-east-1)
    -ParamsFile          Parameter file path
    -SpokeAccounts       Comma-separated spoke account IDs
    -LambdaBucket        Lambda artifacts S3 bucket [required for new deployments]
    -LambdaKey           Lambda artifacts S3 key [required for new deployments]
    -ExternalId          Cross-account external ID [required for new deployments]
    -NotificationEmail   Notification email address
    # Custom SSM documents are always enabled by the stack
    -EnableScheduler     Enable scheduled execution
    -DryRun              Show what would be deployed without executing
    -Help                Show this help message

EXAMPLES:
    # Deploy production stack with custom documents
    .\deploy-with-custom-documents.ps1 -Environment prod -ParamsFile "params\prod-hub.json" `
        -SpokeAccounts "222222,333333" -LambdaBucket "my-artifacts-bucket" `
        -LambdaKey "lambda-code.zip" -ExternalId "my-secure-external-id" -EnableCustomDocs

    # Deploy development stack without custom documents
    .\deploy-with-custom-documents.ps1 -Environment dev -ParamsFile "params\dev-hub.json" `
        -LambdaBucket "my-artifacts-bucket" -LambdaKey "lambda-code.zip" -ExternalId "dev-external-id"

    # Dry run to see what would be deployed
    .\deploy-with-custom-documents.ps1 -Environment prod -ParamsFile "params\prod-hub.json" -DryRun
"@
}

# Show help if requested
if ($Help) {
    Show-Usage
    exit 0
}

# Validate template file exists
if (-not (Test-Path $TemplateFile)) {
    Write-Error "CloudFormation template not found: $TemplateFile"
    exit 1
}

# Set stack name
$StackName = "$StackNamePrefix-$Environment"

# Build parameter overrides
$ParamOverrides = @()

# Add required parameters
$ParamOverrides += "Environment=$Environment"

if ($LambdaBucket) {
    $ParamOverrides += "LambdaArtifactBucket=$LambdaBucket"
}

if ($LambdaKey) {
    $ParamOverrides += "LambdaArtifactKey=$LambdaKey"
}

if ($ExternalId) {
    $ParamOverrides += "CrossAccountExternalId=$ExternalId"
}

if ($NotificationEmail) {
    $ParamOverrides += "NotificationEmail=$NotificationEmail"
}

if ($SpokeAccounts) {
    $ParamOverrides += "SpokeAccountIds=$SpokeAccounts"
}

# Custom documents are always created and used by the template (no toggle required)

# Scheduler configuration
if ($EnableScheduler) {
    $ParamOverrides += "EnableScheduledExecution=ENABLED"
} else {
    $ParamOverrides += "EnableScheduledExecution=DISABLED"
}

# Build the deployment command
$DeployArgs = @(
    "cloudformation", "deploy",
    "--template-file", $TemplateFile,
    "--stack-name", $StackName,
    "--capabilities", "CAPABILITY_NAMED_IAM",
    "--region", $Region
)

# Add parameter overrides
if ($ParamOverrides.Count -gt 0) {
    $DeployArgs += "--parameter-overrides"
    $DeployArgs += $ParamOverrides
}

# Add parameter file if specified
if ($ParamsFile) {
    if (-not (Test-Path $ParamsFile)) {
        Write-Error "Parameter file not found: $ParamsFile"
        exit 1
    }
    $DeployArgs += "file://$ParamsFile"
}

# Show deployment summary
Write-Info "=== Deployment Summary ==="
Write-Info "Stack Name: $StackName"
Write-Info "Environment: $Environment"
Write-Info "Region: $Region"
Write-Info "Template: $TemplateFile"
if ($ParamsFile) {
    Write-Info "Parameter File: $ParamsFile"
}
Write-Info "Custom Documents: ENABLED (always-on)"
Write-Info "Scheduled Execution: $(if ($EnableScheduler) { 'ENABLED' } else { 'DISABLED' })"
if ($SpokeAccounts) {
    Write-Info "Spoke Accounts: $SpokeAccounts"
}

# Show parameter overrides
if ($ParamOverrides.Count -gt 0) {
    Write-Info "Parameter Overrides:"
    foreach ($param in $ParamOverrides) {
        Write-Info "  - $param"
    }
}

Write-Host ""

# Execute or show dry run
if ($DryRun) {
    Write-Warning "DRY RUN MODE - Command that would be executed:"
    Write-Host "aws $($DeployArgs -join ' ')"
    exit 0
}

# Check AWS CLI configuration
try {
    $null = aws sts get-caller-identity --region $Region 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "AWS CLI error"
    }
} catch {
    Write-Error "AWS CLI not configured or invalid credentials"
    exit 1
}

# Pre-deployment checks
Write-Info "Performing pre-deployment checks..."

# Check if Lambda artifacts exist
if ($LambdaBucket -and $LambdaKey) {
    try {
        $null = aws s3api head-object --bucket $LambdaBucket --key $LambdaKey --region $Region 2>$null
        if ($LASTEXITCODE -ne 0) {
            throw "Object not found"
        }
        Write-Success "Lambda artifact verified"
    } catch {
        Write-Error "Lambda artifact not found: s3://$LambdaBucket/$LambdaKey"
        exit 1
    }
}

# Check if stack already exists
try {
    $null = aws cloudformation describe-stacks --stack-name $StackName --region $Region 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Warning "Stack $StackName already exists - this will be an update"
        $response = Read-Host "Continue with stack update? (y/N)"
        if ($response -notmatch '^[Yy]$') {
            Write-Info "Deployment cancelled"
            exit 0
        }
    } else {
        Write-Info "Creating new stack: $StackName"
    }
} catch {
    Write-Info "Creating new stack: $StackName"
}

# Execute deployment
Write-Info "Starting deployment..."
Write-Info "Command: aws $($DeployArgs -join ' ')"
Write-Host ""

try {
    & aws @DeployArgs
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Deployment completed successfully!"
        
        # Show stack outputs
        Write-Info "Stack outputs:"
        aws cloudformation describe-stacks --stack-name $StackName --region $Region --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' --output table
        
        # Show custom document information
        Write-Host ""
        Write-Info "Custom SSM Documents (created by stack):"
        Write-Info "  - Windows: ec2-patch-$Environment-WindowsCustomPatch"
        Write-Info "  - Linux: ec2-patch-$Environment-LinuxCustomPatch"
        
        if ($SpokeAccounts) {
            Write-Info "Documents shared with spoke accounts: $SpokeAccounts"
        }
        
        Write-Host ""
        Write-Info "To verify document sharing:"
        Write-Host "aws ssm describe-document-permission --name ec2-patch-$Environment-WindowsCustomPatch --permission-type Share --region $Region"
    } else {
        throw "AWS CLI deployment failed"
    }
} catch {
    Write-Error "Deployment failed!"
    exit 1
}