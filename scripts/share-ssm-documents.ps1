# PowerShell script to share SSM documents from hub account to spoke accounts

param(
    [Parameter(Mandatory=$true)]
    [string]$HubAccountId,
    
    [Parameter(Mandatory=$true)]
    [string[]]$SpokeAccounts,
    
    [string]$Region = "us-east-1"
)

# SSM Documents to share
$Documents = @(
    "WindowsCustomPatch",
    "LinuxCustomPatch", 
    "WindowsPrePatch",
    "WindowsPostPatch",
    "LinuxPrePatch",
    "LinuxPostPatch"
)

Write-Host "Starting SSM document sharing from hub account $HubAccountId" -ForegroundColor Green

# Function to share a document with spoke accounts
function Share-Document {
    param(
        [string]$DocumentName,
        [string[]]$AccountIds
    )
    
    Write-Host "Sharing document: $DocumentName" -ForegroundColor Yellow
    
    # Build account ID list for sharing
    $accountList = $AccountIds -join ","
    
    try {
        # Share the document
        aws ssm modify-document-permission `
            --name $DocumentName `
            --permission-type "Share" `
            --account-ids-to-add $accountList `
            --region $Region
        
        Write-Host "✅ Document $DocumentName shared with accounts: $accountList" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to share document $DocumentName`: $_"
    }
}

# Create documents in hub account first
Write-Host "Creating SSM documents in hub account..." -ForegroundColor Cyan

$documentFiles = @{
    "WindowsCustomPatch" = "WindowsCustomPatch.json"
    "LinuxCustomPatch" = "LinuxCustomPatch.json"
    "WindowsPrePatch" = "WindowsPrePatch.json"
    "WindowsPostPatch" = "WindowsPostPatch.json"
    "LinuxPrePatch" = "LinuxPrePatch.json"
    "LinuxPostPatch" = "LinuxPostPatch.json"
}

foreach ($doc in $documentFiles.GetEnumerator()) {
    try {
        aws ssm create-document `
            --name $doc.Key `
            --document-type "Command" `
            --document-format JSON `
            --content "file://$($doc.Value)" `
            --region $Region
        
        Write-Host "Created document: $($doc.Key)" -ForegroundColor Green
    }
    catch {
        Write-Warning "Document $($doc.Key) may already exist: $_"
    }
}

Write-Host "Documents created in hub account" -ForegroundColor Green

# Share each document with all spoke accounts
foreach ($doc in $Documents) {
    Share-Document -DocumentName $doc -AccountIds $SpokeAccounts
}

Write-Host ""
Write-Host "🎉 All SSM documents have been shared successfully!" -ForegroundColor Green
Write-Host ""

Write-Host "Verification commands:" -ForegroundColor Cyan
Write-Host "To verify sharing from hub account:"
foreach ($doc in $Documents) {
    Write-Host "  aws ssm describe-document-permission --name $doc --permission-type Share --region $Region" -ForegroundColor Gray
}

Write-Host ""
Write-Host "To verify access from spoke accounts:"
Write-Host "  aws ssm list-documents --filters Key=Owner,Values=Amazon,Self,Shared --region $Region" -ForegroundColor Gray

Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "1. Update hub CloudFormation stack to use these shared documents"
Write-Host "2. Test execution with custom documents enabled"

# Example usage at the end of the script
Write-Host ""
Write-Host "Example usage:" -ForegroundColor Yellow
Write-Host ".\share-ssm-documents.ps1 -HubAccountId '111111111111' -SpokeAccounts @('222222222222','333333333333') -Region 'us-east-1'"