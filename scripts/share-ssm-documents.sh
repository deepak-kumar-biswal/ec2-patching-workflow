#!/bin/bash
# Script to share SSM documents from hub account to spoke accounts

set -e

# Configuration
HUB_ACCOUNT_ID="111111111111"
SPOKE_ACCOUNTS=("222222222222" "333333333333" "444444444444")
AWS_REGION="us-east-1"

# SSM Documents to share
DOCUMENTS=(
    "WindowsCustomPatch"
    "LinuxCustomPatch" 
    "WindowsPrePatch"
    "WindowsPostPatch"
    "LinuxPrePatch"
    "LinuxPostPatch"
)

echo "Starting SSM document sharing from hub account $HUB_ACCOUNT_ID"

# Function to share a document with spoke accounts
share_document() {
    local doc_name=$1
    local account_ids=("${@:2}")
    
    echo "Sharing document: $doc_name"
    
    # Build account ID list for sharing
    local account_list=""
    for account in "${account_ids[@]}"; do
        if [ -z "$account_list" ]; then
            account_list="$account"
        else
            account_list="$account_list,$account"
        fi
    done
    
    # Share the document
    aws ssm modify-document-permission \
        --name "$doc_name" \
        --permission-type "Share" \
        --account-ids-to-add "$account_list" \
        --region "$AWS_REGION"
    
    echo "✅ Document $doc_name shared with accounts: $account_list"
}

# Create documents in hub account first
echo "Creating SSM documents in hub account..."

aws ssm create-document \
    --name "WindowsCustomPatch" \
    --document-type "Command" \
    --document-format JSON \
    --content file://WindowsCustomPatch.json \
    --region "$AWS_REGION" || echo "Document may already exist"

aws ssm create-document \
    --name "LinuxCustomPatch" \
    --document-type "Command" \
    --document-format JSON \
    --content file://LinuxCustomPatch.json \
    --region "$AWS_REGION" || echo "Document may already exist"

aws ssm create-document \
    --name "WindowsPrePatch" \
    --document-type "Command" \
    --document-format JSON \
    --content file://WindowsPrePatch.json \
    --region "$AWS_REGION" || echo "Document may already exist"

aws ssm create-document \
    --name "WindowsPostPatch" \
    --document-type "Command" \
    --document-format JSON \
    --content file://WindowsPostPatch.json \
    --region "$AWS_REGION" || echo "Document may already exist"

aws ssm create-document \
    --name "LinuxPrePatch" \
    --document-type "Command" \
    --document-format JSON \
    --content file://LinuxPrePatch.json \
    --region "$AWS_REGION" || echo "Document may already exist"

aws ssm create-document \
    --name "LinuxPostPatch" \
    --document-type "Command" \
    --document-format JSON \
    --content file://LinuxPostPatch.json \
    --region "$AWS_REGION" || echo "Document may already exist"

echo "Documents created in hub account"

# Share each document with all spoke accounts
for doc in "${DOCUMENTS[@]}"; do
    share_document "$doc" "${SPOKE_ACCOUNTS[@]}"
done

echo ""
echo "🎉 All SSM documents have been shared successfully!"
echo ""
echo "Verification commands:"
echo "To verify sharing from hub account:"
for doc in "${DOCUMENTS[@]}"; do
    echo "  aws ssm describe-document-permission --name $doc --permission-type Share --region $AWS_REGION"
done

echo ""
echo "To verify access from spoke accounts:"
echo "  aws ssm list-documents --filters Key=Owner,Values=Amazon,Self,Shared --region $AWS_REGION"

echo ""
echo "Next steps:"
echo "1. Update hub CloudFormation stack to use these shared documents"
echo "2. Test execution with custom documents enabled"