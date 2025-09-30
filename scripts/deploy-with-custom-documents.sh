#!/bin/bash

# EC2 Patching Workflow - CloudFormation Deployment with Custom Documents
# This script deploys the hub stack with custom SSM documents and automatic sharing

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="$SCRIPT_DIR/../cloudformation/hub-cfn.yaml"
STACK_NAME_PREFIX="ec2-patch-hub"
DEFAULT_REGION="us-east-1"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy EC2 Patching Workflow with Custom SSM Documents

OPTIONS:
    -e, --environment ENV       Environment (dev, test, stage, prod) [required]
    -r, --region REGION         AWS region (default: us-east-1)
    -p, --params-file FILE      Parameter file path [required]
    -s, --spoke-accounts IDS    Comma-separated spoke account IDs
    -b, --bucket BUCKET         Lambda artifacts S3 bucket [required]
    -k, --key KEY               Lambda artifacts S3 key [required]
    -x, --external-id ID        Cross-account external ID [required]
    -n, --notification EMAIL    Notification email address
    # (Removed) Custom documents are always enabled by the stack
    --enable-scheduler          Enable scheduled execution (default: disabled)
    --dry-run                   Show what would be deployed without executing
    -h, --help                  Show this help message

EXAMPLES:
    # Deploy production stack with custom documents
    $0 -e prod -p params/prod-hub.json -s "222222,333333" \\
       -b my-artifacts-bucket -k lambda-code.zip \\
       -x my-secure-external-id --enable-custom-docs

    # Deploy development stack without custom documents  
    $0 -e dev -p params/dev-hub.json \\
       -b my-artifacts-bucket -k lambda-code.zip \\
       -x dev-external-id

    # Dry run to see what would be deployed
    $0 -e prod -p params/prod-hub.json --dry-run
EOF
}

# Parse command line arguments
ENVIRONMENT=""
REGION="$DEFAULT_REGION"
PARAMS_FILE=""
SPOKE_ACCOUNTS=""
LAMBDA_BUCKET=""
LAMBDA_KEY=""
EXTERNAL_ID=""
NOTIFICATION_EMAIL=""
ENABLE_CUSTOM_DOCS="true" # Always-on in template (kept for backward CLI compatibility, ignored)
ENABLE_SCHEDULER="false"
DRY_RUN="false"

while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        -p|--params-file)
            PARAMS_FILE="$2"
            shift 2
            ;;
        -s|--spoke-accounts)
            SPOKE_ACCOUNTS="$2"
            shift 2
            ;;
        -b|--bucket)
            LAMBDA_BUCKET="$2"
            shift 2
            ;;
        -k|--key)
            LAMBDA_KEY="$2"
            shift 2
            ;;
        -x|--external-id)
            EXTERNAL_ID="$2"
            shift 2
            ;;
        -n|--notification)
            NOTIFICATION_EMAIL="$2"
            shift 2
            ;;
        # --enable-custom-docs (deprecated; no-op)
        --enable-custom-docs)
            ENABLE_CUSTOM_DOCS="true"
            shift
            ;;
        --enable-scheduler)
            ENABLE_SCHEDULER="true"
            shift
            ;;
        --dry-run)
            DRY_RUN="true"
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "$ENVIRONMENT" ]]; then
    log_error "Environment is required (-e|--environment)"
    exit 1
fi

if [[ ! "$ENVIRONMENT" =~ ^(dev|test|stage|prod)$ ]]; then
    log_error "Environment must be one of: dev, test, stage, prod"
    exit 1
fi

# Set stack name
STACK_NAME="$STACK_NAME_PREFIX-$ENVIRONMENT"

# Validate template file exists
if [[ ! -f "$TEMPLATE_FILE" ]]; then
    log_error "CloudFormation template not found: $TEMPLATE_FILE"
    exit 1
fi

# Build parameter overrides
PARAM_OVERRIDES=()

# Add required parameters
PARAM_OVERRIDES+=("Environment=$ENVIRONMENT")

if [[ -n "$LAMBDA_BUCKET" ]]; then
    PARAM_OVERRIDES+=("LambdaArtifactBucket=$LAMBDA_BUCKET")
fi

if [[ -n "$LAMBDA_KEY" ]]; then
    PARAM_OVERRIDES+=("LambdaArtifactKey=$LAMBDA_KEY")
fi

if [[ -n "$EXTERNAL_ID" ]]; then
    PARAM_OVERRIDES+=("CrossAccountExternalId=$EXTERNAL_ID")
fi

if [[ -n "$NOTIFICATION_EMAIL" ]]; then
    PARAM_OVERRIDES+=("NotificationEmail=$NOTIFICATION_EMAIL")
fi

if [[ -n "$SPOKE_ACCOUNTS" ]]; then
    PARAM_OVERRIDES+=("SpokeAccountIds=$SPOKE_ACCOUNTS")
fi

# Custom documents are always created and used by the template.
# No parameter toggle is required or supported anymore.

# Scheduler configuration
if [[ "$ENABLE_SCHEDULER" == "true" ]]; then
    PARAM_OVERRIDES+=("EnableScheduledExecution=ENABLED")
else
    PARAM_OVERRIDES+=("EnableScheduledExecution=DISABLED")
fi

# Build the deployment command
DEPLOY_CMD="aws cloudformation deploy"
DEPLOY_CMD+=" --template-file $TEMPLATE_FILE"
DEPLOY_CMD+=" --stack-name $STACK_NAME"
DEPLOY_CMD+=" --capabilities CAPABILITY_NAMED_IAM"
DEPLOY_CMD+=" --region $REGION"

# Add parameter overrides
if [[ ${#PARAM_OVERRIDES[@]} -gt 0 ]]; then
    DEPLOY_CMD+=" --parameter-overrides"
    for param in "${PARAM_OVERRIDES[@]}"; do
        DEPLOY_CMD+=" $param"
    done
fi

# Add parameter file if specified
if [[ -n "$PARAMS_FILE" ]]; then
    if [[ ! -f "$PARAMS_FILE" ]]; then
        log_error "Parameter file not found: $PARAMS_FILE"
        exit 1
    fi
    DEPLOY_CMD+=" --parameter-overrides file://$PARAMS_FILE"
fi

# Show deployment summary
log_info "=== Deployment Summary ==="
log_info "Stack Name: $STACK_NAME"
log_info "Environment: $ENVIRONMENT"
log_info "Region: $REGION"
log_info "Template: $TEMPLATE_FILE"
if [[ -n "$PARAMS_FILE" ]]; then
    log_info "Parameter File: $PARAMS_FILE"
fi
log_info "Custom Documents: ENABLED (always-on)"
log_info "Scheduled Execution: $([[ "$ENABLE_SCHEDULER" == "true" ]] && echo "ENABLED" || echo "DISABLED")"
if [[ -n "$SPOKE_ACCOUNTS" ]]; then
    log_info "Spoke Accounts: $SPOKE_ACCOUNTS"
fi

# Show parameter overrides
if [[ ${#PARAM_OVERRIDES[@]} -gt 0 ]]; then
    log_info "Parameter Overrides:"
    for param in "${PARAM_OVERRIDES[@]}"; do
        log_info "  - $param"
    done
fi

echo

# Execute or show dry run
if [[ "$DRY_RUN" == "true" ]]; then
    log_warning "DRY RUN MODE - Command that would be executed:"
    echo "$DEPLOY_CMD"
    exit 0
fi

# Check AWS CLI configuration
if ! aws sts get-caller-identity --region "$REGION" &>/dev/null; then
    log_error "AWS CLI not configured or invalid credentials"
    exit 1
fi

# Pre-deployment checks
log_info "Performing pre-deployment checks..."

# Check if Lambda artifacts exist
if [[ -n "$LAMBDA_BUCKET" ]] && [[ -n "$LAMBDA_KEY" ]]; then
    if ! aws s3api head-object --bucket "$LAMBDA_BUCKET" --key "$LAMBDA_KEY" --region "$REGION" &>/dev/null; then
        log_error "Lambda artifact not found: s3://$LAMBDA_BUCKET/$LAMBDA_KEY"
        exit 1
    fi
    log_success "Lambda artifact verified"
fi

# Check if stack already exists
if aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" &>/dev/null; then
    log_warning "Stack $STACK_NAME already exists - this will be an update"
    read -p "Continue with stack update? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Deployment cancelled"
        exit 0
    fi
else
    log_info "Creating new stack: $STACK_NAME"
fi

# Execute deployment
log_info "Starting deployment..."
log_info "Command: $DEPLOY_CMD"
echo

if eval "$DEPLOY_CMD"; then
    log_success "Deployment completed successfully!"
    
    # Show stack outputs
    log_info "Stack outputs:"
    aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' \
        --output table
    
    # Show custom document information
    echo
    log_info "Custom SSM Documents (created by stack):"
    log_info "  - Windows: ec2-patch-$ENVIRONMENT-WindowsCustomPatch"
    log_info "  - Linux: ec2-patch-$ENVIRONMENT-LinuxCustomPatch"
    if [[ -n "$SPOKE_ACCOUNTS" ]]; then
        log_info "Documents shared with spoke accounts: $SPOKE_ACCOUNTS"
    fi
    echo
    log_info "To verify document sharing:"
    echo "aws ssm describe-document-permission --name ec2-patch-$ENVIRONMENT-WindowsCustomPatch --permission-type Share --region $REGION"
    
else
    log_error "Deployment failed!"
    exit 1
fi