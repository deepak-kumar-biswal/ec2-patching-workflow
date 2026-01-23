<#
.SYNOPSIS
    Deploys AgentCore IAM roles and policies using CloudFormation.

.DESCRIPTION
    This script deploys modular IAM roles and policies for AWS AgentCore 
    multi-agent platform using CloudFormation.

.PARAMETER ApplicationName
    The name of the application using AgentCore. Required.

.PARAMETER Environment
    Deployment environment: dev, staging, or prod. Default: dev

.PARAMETER Region
    AWS region for deployment. Default: us-east-1

.PARAMETER StackName
    CloudFormation stack name. Default: agentcore-iam-{app}-{env}

.PARAMETER DryRun
    Validate template without deploying.

.EXAMPLE
    .\deploy-iam.ps1 -ApplicationName "my-agent-platform" -Environment "dev"

.EXAMPLE
    .\deploy-iam.ps1 -ApplicationName "enterprise-agents" -Environment "prod" -Region "us-west-2"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-zA-Z][a-zA-Z0-9-]{2,63}$')]
    [string]$ApplicationName,

    [Parameter(Mandatory = $false)]
    [ValidateSet('dev', 'staging', 'prod')]
    [string]$Environment = 'dev',

    [Parameter(Mandatory = $false)]
    [string]$Region = 'us-east-1',

    [Parameter(Mandatory = $false)]
    [string]$StackName = '',

    [Parameter(Mandatory = $false)]
    [switch]$DryRun
)

# Script configuration
$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$TemplateDir = Join-Path (Split-Path -Parent $ScriptDir) 'cloudformation'
$PolicyDir = Split-Path -Parent $ScriptDir

# Functions
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )
    
    $color = switch ($Level) {
        'INFO'  { 'Green' }
        'WARN'  { 'Yellow' }
        'ERROR' { 'Red' }
    }
    
    Write-Host "[$Level] $Message" -ForegroundColor $color
}

function Test-Prerequisites {
    Write-Log "Validating prerequisites..."
    
    # Check AWS CLI
    try {
        $null = aws --version
    }
    catch {
        Write-Log "AWS CLI is not installed. Please install it first." -Level ERROR
        exit 1
    }
    
    # Check AWS credentials
    try {
        $identity = aws sts get-caller-identity --output json | ConvertFrom-Json
        Write-Log "AWS CLI configured. Account: $($identity.Account)"
    }
    catch {
        Write-Log "AWS credentials not configured. Run 'aws configure' first." -Level ERROR
        exit 1
    }
}

function Test-Template {
    Write-Log "Validating CloudFormation template..."
    
    $templatePath = Join-Path $TemplateDir 'agentcore-iam-roles.yaml'
    
    try {
        aws cloudformation validate-template `
            --template-body "file://$templatePath" `
            --region $Region | Out-Null
        
        Write-Log "Template validation successful"
    }
    catch {
        Write-Log "Template validation failed: $_" -Level ERROR
        exit 1
    }
}

function Deploy-Stack {
    $templatePath = Join-Path $TemplateDir 'agentcore-iam-roles.yaml'
    $paramsFile = Join-Path $TemplateDir "params\$Environment.json"
    
    Write-Log "Deploying CloudFormation stack: $StackName"
    
    # Build parameter overrides
    $paramOverrides = @(
        "ApplicationName=$ApplicationName",
        "Environment=$Environment"
    )
    
    # Check if params file exists and merge parameters
    if (Test-Path $paramsFile) {
        Write-Log "Using parameters from: $paramsFile"
        $params = Get-Content $paramsFile | ConvertFrom-Json
        foreach ($prop in $params.PSObject.Properties) {
            if ($prop.Value -and $prop.Name -notin @('ApplicationName', 'Environment')) {
                $paramOverrides += "$($prop.Name)=$($prop.Value)"
            }
        }
    }
    else {
        Write-Log "Parameter file $paramsFile not found. Using defaults." -Level WARN
    }
    
    Write-Log "Executing deployment..."
    
    try {
        aws cloudformation deploy `
            --template-file $templatePath `
            --stack-name $StackName `
            --capabilities CAPABILITY_NAMED_IAM `
            --region $Region `
            --parameter-overrides $paramOverrides
        
        Write-Log "Stack deployed successfully!"
        
        # Get outputs
        Write-Log "Stack Outputs:"
        aws cloudformation describe-stacks `
            --stack-name $StackName `
            --region $Region `
            --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' `
            --output table
    }
    catch {
        Write-Log "Deployment failed: $_" -Level ERROR
        exit 1
    }
}

# Main execution
if ([string]::IsNullOrEmpty($StackName)) {
    $StackName = "agentcore-iam-$ApplicationName-$Environment"
}

Write-Log "AgentCore IAM Deployment"
Write-Log "========================"
Write-Log "Application: $ApplicationName"
Write-Log "Environment: $Environment"
Write-Log "Region: $Region"
Write-Log "Stack Name: $StackName"
Write-Log ""

Test-Prerequisites
Test-Template

if ($DryRun) {
    Write-Log "Dry run completed. Template is valid."
    exit 0
}

Deploy-Stack

Write-Log ""
Write-Log "Deployment complete!"
Write-Log ""
Write-Log "Next steps:"
Write-Log "1. Copy the ExecutionRoleArn from the outputs above"
Write-Log "2. Use this role when creating Bedrock Agents"
Write-Log "3. Tag your resources with AgentCore:Application=$ApplicationName"
