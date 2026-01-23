#!/bin/bash
# =============================================================================
# AgentCore IAM Deployment Script
# Deploys modular IAM roles and policies for AWS AgentCore multi-agent platform
# =============================================================================

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="${SCRIPT_DIR}/../cloudformation"
POLICY_DIR="${SCRIPT_DIR}/.."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
ENVIRONMENT="dev"
APPLICATION_NAME=""
AWS_REGION="${AWS_REGION:-us-east-1}"
STACK_NAME=""
DRY_RUN=false

# Functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Deploy AgentCore IAM roles and policies using CloudFormation.

Options:
    -a, --application NAME    Application name (required)
    -e, --environment ENV     Environment: dev, staging, prod (default: dev)
    -r, --region REGION       AWS region (default: us-east-1)
    -s, --stack-name NAME     CloudFormation stack name (default: agentcore-iam-{app}-{env})
    -d, --dry-run             Validate template without deploying
    -h, --help                Show this help message

Examples:
    $(basename "$0") -a my-agent-platform -e dev
    $(basename "$0") -a enterprise-agents -e prod -r us-west-2
    $(basename "$0") -a test-platform -e staging --dry-run

EOF
    exit 1
}

validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Run 'aws configure' first."
        exit 1
    fi
    
    log_info "AWS CLI configured. Account: $(aws sts get-caller-identity --query 'Account' --output text)"
}

validate_template() {
    log_info "Validating CloudFormation template..."
    
    aws cloudformation validate-template \
        --template-body "file://${TEMPLATE_DIR}/agentcore-iam-roles.yaml" \
        --region "${AWS_REGION}" > /dev/null
    
    log_info "Template validation successful"
}

deploy_stack() {
    local params_file="${TEMPLATE_DIR}/params/${ENVIRONMENT}.json"
    
    # Check if params file exists
    if [[ ! -f "${params_file}" ]]; then
        log_warn "Parameter file ${params_file} not found. Using defaults."
        params_file=""
    fi
    
    log_info "Deploying CloudFormation stack: ${STACK_NAME}"
    
    local deploy_cmd="aws cloudformation deploy \
        --template-file ${TEMPLATE_DIR}/agentcore-iam-roles.yaml \
        --stack-name ${STACK_NAME} \
        --capabilities CAPABILITY_NAMED_IAM \
        --region ${AWS_REGION} \
        --parameter-overrides \
            ApplicationName=${APPLICATION_NAME} \
            Environment=${ENVIRONMENT}"
    
    if [[ -n "${params_file}" ]]; then
        log_info "Using parameters from: ${params_file}"
    fi
    
    log_info "Executing deployment..."
    eval "${deploy_cmd}"
    
    log_info "Stack deployed successfully!"
    
    # Get outputs
    log_info "Stack Outputs:"
    aws cloudformation describe-stacks \
        --stack-name "${STACK_NAME}" \
        --region "${AWS_REGION}" \
        --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' \
        --output table
}

create_standalone_policies() {
    log_info "Creating standalone IAM policies..."
    
    local policies=(
        "base-policy.json:AgentCoreBase"
        "model-access-policy.json:AgentCoreModelAccess"
        "knowledge-base-policy.json:AgentCoreKnowledgeBase"
        "action-groups-policy.json:AgentCoreActionGroups"
        "s3-data-policy.json:AgentCoreS3Data"
        "secrets-manager-policy.json:AgentCoreSecretsManager"
        "opensearch-policy.json:AgentCoreOpenSearch"
        "guardrails-policy.json:AgentCoreGuardrails"
        "multi-agent-policy.json:AgentCoreMultiAgent"
        "cloudwatch-policy.json:AgentCoreCloudWatch"
        "cross-account-policy.json:AgentCoreCrossAccount"
        "kms-policy.json:AgentCoreKMS"
        "network-policy.json:AgentCoreNetwork"
    )
    
    for policy_entry in "${policies[@]}"; do
        IFS=':' read -r policy_file policy_name <<< "${policy_entry}"
        local full_policy_name="${policy_name}-${APPLICATION_NAME}-${ENVIRONMENT}"
        local policy_path="${POLICY_DIR}/${policy_file}"
        
        if [[ -f "${policy_path}" ]]; then
            log_info "Creating policy: ${full_policy_name}"
            
            # Substitute variables in policy
            local policy_doc=$(cat "${policy_path}" | \
                sed "s/\${AWS::AccountId}/$(aws sts get-caller-identity --query 'Account' --output text)/g" | \
                sed "s/\${BucketPrefix}/agentcore/g")
            
            # Check if policy exists
            if aws iam get-policy --policy-arn "arn:aws:iam::$(aws sts get-caller-identity --query 'Account' --output text):policy/${full_policy_name}" &> /dev/null; then
                log_warn "Policy ${full_policy_name} already exists. Skipping."
            else
                echo "${policy_doc}" | aws iam create-policy \
                    --policy-name "${full_policy_name}" \
                    --policy-document file:///dev/stdin \
                    --description "AgentCore ${policy_name} policy for ${APPLICATION_NAME}" \
                    --tags Key=AgentCore:Application,Value="${APPLICATION_NAME}" \
                           Key=AgentCore:Environment,Value="${ENVIRONMENT}" \
                    > /dev/null
                log_info "Created policy: ${full_policy_name}"
            fi
        fi
    done
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -a|--application)
            APPLICATION_NAME="$2"
            shift 2
            ;;
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -r|--region)
            AWS_REGION="$2"
            shift 2
            ;;
        -s|--stack-name)
            STACK_NAME="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            ;;
    esac
done

# Validate required parameters
if [[ -z "${APPLICATION_NAME}" ]]; then
    log_error "Application name is required."
    usage
fi

# Set default stack name
if [[ -z "${STACK_NAME}" ]]; then
    STACK_NAME="agentcore-iam-${APPLICATION_NAME}-${ENVIRONMENT}"
fi

# Main execution
log_info "AgentCore IAM Deployment"
log_info "========================"
log_info "Application: ${APPLICATION_NAME}"
log_info "Environment: ${ENVIRONMENT}"
log_info "Region: ${AWS_REGION}"
log_info "Stack Name: ${STACK_NAME}"
log_info ""

validate_prerequisites
validate_template

if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "Dry run completed. Template is valid."
    exit 0
fi

deploy_stack

log_info ""
log_info "Deployment complete!"
log_info ""
log_info "Next steps:"
log_info "1. Copy the ExecutionRoleArn from the outputs above"
log_info "2. Use this role when creating Bedrock Agents"
log_info "3. Tag your resources with AgentCore:Application=${APPLICATION_NAME}"
