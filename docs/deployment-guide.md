# EC2 Patching Workflow - Deployment Guide

## Overview

This guide provides step-by-step instructions for deploying the Enterprise EC2 Multi-Account Patching Platform across your AWS organization.

## Prerequisites

### Required Tools

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

## Step 1: Hub Account Deployment (CloudFormation)

### 1.1 Prepare Lambda Artifact

```bash
zip -r lambda.zip lambda -x "**/__pycache__/**"
aws s3 cp lambda.zip s3://<artifact-bucket>/ec2-patch/<sha>/lambda.zip
```

### 1.2 Configure Parameters

Edit `cloudformation/params/dev-hub.json` (or your env variant) to set values for:

- `CrossAccountExternalId`
- `LambdaArtifactBucket`
- `LambdaArtifactKey`

### 1.3 Deploy Hub Stack

```bash
aws cloudformation deploy \
    --template-file cloudformation/hub-cfn.yaml \
    --stack-name ec2-patch-hub \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameter-overrides file://cloudformation/params/dev-hub.json
```

## Step 2: Spoke Account Deployment (CloudFormation)

For each target account, update `cloudformation/params/dev-spoke.json` with:

- `HubAccountId`
- `ExternalId`

Then deploy the Spoke stack:

```bash
aws cloudformation deploy \
    --template-file cloudformation/spoke-cfn.yaml \
    --stack-name ec2-patch-spoke \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameter-overrides file://cloudformation/params/dev-spoke.json
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

### 4.2 Approval Callback and Notifications

Ensure the approval callback API and notification email (if used) are configured via hub parameters.

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

# Rollback CloudFormation if needed
aws cloudformation delete-stack --stack-name ec2-patch-hub
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
