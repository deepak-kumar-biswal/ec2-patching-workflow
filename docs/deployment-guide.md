# EC2 Patching Workflow - Deployment Guide

## Overview

This guide provides step-by-step instructions for deploying the Enterprise EC2 Multi-Account Patching Platform across your AWS organization.

## Prerequisites

### Required Tools
- Terraform >= 1.5.0
- AWS CLI >= 2.0
- Python >= 3.9 (for testing)
- Git

### AWS Permissions
- Administrative access to hub account
- Cross-account role creation permissions in spoke accounts
- EventBridge, Step Functions, Lambda, and Systems Manager permissions

### Account Setup
```bash
# Verify AWS CLI configuration
aws sts get-caller-identity

# Set required environment variables
export HUB_ACCOUNT_ID=111111111111
export AWS_DEFAULT_REGION=us-east-1
```

## Step 1: Hub Account Deployment

### 1.1 Initialize Terraform

```bash
cd terraform/hub
terraform init -backend-config="bucket=your-terraform-state-bucket"
```

### 1.2 Configure Variables

Create `terraform.tfvars`:

```hcl
region                    = "us-east-1"
orchestrator_account_id   = "111111111111"
name_prefix              = "ec2patch"
bedrock_agent_id         = "YOUR_BEDROCK_AGENT_ID"
bedrock_agent_alias_id   = "YOUR_BEDROCK_ALIAS_ID"

wave_rules = [
  {
    name                = "critical-production"
    schedule_expression = "cron(0 2 ? * SUN *)"
    accounts           = ["222222222222", "333333333333"]
    regions            = ["us-east-1", "us-west-2"]
  },
  {
    name                = "development-staging"
    schedule_expression = "cron(0 3 ? * SUN *)"
    accounts           = ["444444444444", "555555555555"] 
    regions            = ["us-east-1"]
  }
]

sns_email_subscriptions = [
  "ops-team@company.com",
  "security-team@company.com"
]

wave_pause_seconds = 300
abort_on_issues   = true
```

### 1.3 Deploy Hub Infrastructure

```bash
# Plan deployment
terraform plan -out=hub.tfplan

# Apply changes
terraform apply hub.tfplan

# Save outputs for spoke deployment
terraform output -json > ../spoke/hub_outputs.json
```

## Step 2: Spoke Account Deployment

### 2.1 Deploy to Each Spoke Account

For each target account:

```bash
cd terraform/spoke

# Configure AWS credentials for spoke account
aws configure set profile spoke-account-222222222222

# Initialize Terraform
terraform init

# Deploy spoke resources
terraform apply \
  -var="region=us-east-1" \
  -var="orchestrator_account_id=111111111111" \
  -var="role_name=PatchExecRole"
```

### 2.2 Automated Spoke Deployment Script

```bash
#!/bin/bash
# deploy-spokes.sh

SPOKE_ACCOUNTS=("222222222222" "333333333333" "444444444444" "555555555555")
HUB_ACCOUNT="111111111111"
REGION="us-east-1"

for account in "${SPOKE_ACCOUNTS[@]}"; do
    echo "Deploying to spoke account: $account"
    
    # Assume role in spoke account
    aws sts assume-role \
        --role-arn "arn:aws:iam::${account}:role/OrganizationAccountAccessRole" \
        --role-session-name "ec2-patch-deploy" \
        --output json > /tmp/creds-${account}.json
    
    # Extract credentials
    export AWS_ACCESS_KEY_ID=$(jq -r '.Credentials.AccessKeyId' /tmp/creds-${account}.json)
    export AWS_SECRET_ACCESS_KEY=$(jq -r '.Credentials.SecretAccessKey' /tmp/creds-${account}.json)
    export AWS_SESSION_TOKEN=$(jq -r '.Credentials.SessionToken' /tmp/creds-${account}.json)
    
    # Deploy spoke
    cd terraform/spoke
    terraform init
    terraform apply -auto-approve \
        -var="region=${REGION}" \
        -var="orchestrator_account_id=${HUB_ACCOUNT}"
    
    cd ../..
    
    # Cleanup
    rm /tmp/creds-${account}.json
    unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
done
```

## Step 3: Verification

### 3.1 Verify Hub Deployment

```bash
# Check Step Functions
aws stepfunctions list-state-machines \
    --query 'stateMachines[?contains(name,`ec2patch`)]'

# Check EventBridge rules
aws events list-rules --name-prefix ec2patch

# Verify Lambda functions
aws lambda list-functions \
    --query 'Functions[?contains(FunctionName,`ec2patch`)]'
```

### 3.2 Test Cross-Account Access

```bash
# Test assume role to each spoke account
for account in 222222222222 333333333333; do
    echo "Testing access to account: $account"
    aws sts assume-role \
        --role-arn "arn:aws:iam::${account}:role/PatchExecRole" \
        --role-session-name "connectivity-test"
done
```

### 3.3 Validate Instance Discovery

```bash
# Test instance inventory
aws stepfunctions start-execution \
    --state-machine-arn "arn:aws:states:${AWS_DEFAULT_REGION}:${HUB_ACCOUNT_ID}:stateMachine:ec2patch-orchestrator" \
    --name "test-inventory-$(date +%s)" \
    --input '{
        "dryRun": true,
        "accounts": ["222222222222"],
        "regions": ["us-east-1"],
        "tagFilters": {"PatchGroup": "default"}
    }'
```

## Step 4: Configuration

### 4.1 Tag EC2 Instances

Ensure target instances have required tags:

```bash
# Tag instances for patching
aws ec2 create-tags \
    --resources i-1234567890abcdef0 \
    --tags Key=PatchGroup,Value=default \
           Key=Environment,Value=production \
           Key=MaintenanceWindow,Value=sunday-2am
```

### 4.2 Configure Bedrock Agent

1. Create Bedrock Agent with patch analysis capabilities
2. Configure knowledge base with patch documentation
3. Set up action groups for analysis functions
4. Update Terraform variables with agent IDs

### 4.3 Set Up Monitoring

```bash
# Create CloudWatch dashboard
aws cloudwatch put-dashboard \
    --dashboard-name "EC2-Patching-Overview" \
    --dashboard-body file://monitoring/dashboard.json

# Configure SNS subscriptions
aws sns subscribe \
    --topic-arn "arn:aws:sns:us-east-1:111111111111:ec2patch-notifications" \
    --protocol email \
    --notification-endpoint ops-team@company.com
```

## Step 5: Testing

### 5.1 Dry Run Test

```bash
# Execute dry run
aws stepfunctions start-execution \
    --state-machine-arn "$STATE_MACHINE_ARN" \
    --name "dryrun-test-$(date +%s)" \
    --input '{
        "dryRun": true,
        "waveId": "development-staging",
        "accounts": ["444444444444"],
        "regions": ["us-east-1"]
    }'
```

### 5.2 Single Instance Test

```bash
# Test on single development instance
aws stepfunctions start-execution \
    --state-machine-arn "$STATE_MACHINE_ARN" \
    --name "single-instance-test" \
    --input '{
        "dryRun": false,
        "accounts": ["444444444444"],
        "regions": ["us-east-1"],
        "instanceIds": ["i-dev123456789abcdef0"]
    }'
```

## Step 6: Production Rollout

### 6.1 Gradual Rollout Plan

1. **Week 1**: Deploy to development accounts only
2. **Week 2**: Add staging accounts with manual approval
3. **Week 3**: Include non-critical production accounts
4. **Week 4**: Full production rollout with all safety measures

### 6.2 Rollback Plan

```bash
# Disable EventBridge rules
aws events disable-rule --name ec2patch-wave1-critical

# Stop running executions
aws stepfunctions stop-execution --execution-arn "$EXECUTION_ARN"

# Rollback Terraform if needed
terraform apply -target=resource.to.rollback
```

## Step 7: Monitoring Setup

### 7.1 CloudWatch Alarms

```bash
# High failure rate alarm
aws cloudwatch put-metric-alarm \
    --alarm-name "EC2Patch-HighFailureRate" \
    --alarm-description "Patch failure rate exceeds 5%" \
    --metric-name "PatchFailures" \
    --namespace "AWS/EC2Patching" \
    --statistic "Average" \
    --period 300 \
    --threshold 5 \
    --comparison-operator "GreaterThanThreshold" \
    --evaluation-periods 2
```

### 7.2 Log Monitoring

```bash
# Set up log insights queries
aws logs start-query \
    --log-group-name "/aws/lambda/ec2patch-orchestrator" \
    --start-time $(date -d "1 hour ago" +%s) \
    --end-time $(date +%s) \
    --query-string 'fields @timestamp, @message | filter @message like /ERROR/'
```

## Troubleshooting

### Common Issues

1. **Permission Errors**: Verify cross-account role trust relationships
2. **Timeout Issues**: Increase Lambda function timeouts
3. **Network Issues**: Check VPC endpoints and security groups
4. **Tagging Issues**: Ensure instances have required tags

### Support Resources

- AWS Systems Manager documentation
- Step Functions troubleshooting guide
- Lambda function logs in CloudWatch
- Terraform state file for resource tracking

## Best Practices

1. **Security**: Use least privilege IAM policies
2. **Testing**: Always test in development first
3. **Monitoring**: Set up comprehensive alerting
4. **Documentation**: Keep runbooks updated
5. **Rollback**: Have clear rollback procedures

## Next Steps

After successful deployment:

1. Set up regular patch cycles
2. Configure compliance reporting
3. Implement automated remediation
4. Set up cost monitoring
5. Plan for disaster recovery

---

For additional support, refer to the [troubleshooting guide](troubleshooting-guide.md) or create an issue in the repository.
