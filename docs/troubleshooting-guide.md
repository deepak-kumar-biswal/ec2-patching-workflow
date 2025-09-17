# EC2 Patching Workflow - Troubleshooting Guide

## Overview

This guide provides comprehensive troubleshooting information for the Enterprise EC2 Multi-Account Patching Platform, including common issues, diagnostic procedures, and resolution steps.

For day-2 operations and procedures (approvals, retries, scaling, monitoring), see the Ops Runbook: `docs/runbook-operations.md`.

## Table of Contents

- [Quick Diagnostics](#quick-diagnostics)
- [Cross-Account Issues](#cross-account-issues)
- [Step Functions Problems](#step-functions-problems)
- [Lambda Function Errors](#lambda-function-errors)
- [Systems Manager Issues](#systems-manager-issues)
- [EventBridge Problems](#eventbridge-problems)
 
- [Performance Problems](#performance-problems)
- [Monitoring and Alerting](#monitoring-and-alerting)

## Quick Diagnostics

### Health Check Script

```bash
#!/bin/bash
# ec2-patch-health-check.sh

HUB_ACCOUNT="111111111111"
REGION="us-east-1"
NAME_PREFIX="ec2patch"

echo "🔍 EC2 Patching Platform Health Check"
echo "======================================"

# Check Step Functions
echo "📊 Checking Step Functions..."
SF_ARN=$(aws stepfunctions list-state-machines \
  --query "stateMachines[?contains(name,'${NAME_PREFIX}')].stateMachineArn" \
  --output text)

if [ -n "$SF_ARN" ]; then
    echo "✅ Step Function found: $SF_ARN"
else
    echo "❌ Step Function not found"
fi

# Check EventBridge rules
echo "⏰ Checking EventBridge rules..."
RULES=$(aws events list-rules --name-prefix ${NAME_PREFIX} --query 'Rules[].Name' --output table)
if [ $? -eq 0 ]; then
    echo "✅ EventBridge rules:"
    echo "$RULES"
else
    echo "❌ No EventBridge rules found"
fi

# Check Lambda functions
echo "⚡ Checking Lambda functions..."
aws lambda list-functions \
  --query "Functions[?contains(FunctionName,'${NAME_PREFIX}')].{Name:FunctionName,Status:State,Runtime:Runtime}" \
  --output table

# Check IAM roles
echo "🔐 Checking IAM roles..."
aws iam get-role --role-name "${NAME_PREFIX}-orchestrator-role" >/dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "✅ Hub orchestrator role exists"
else
    echo "❌ Hub orchestrator role not found"
fi

echo "✅ Health check complete"
```

### System Status Dashboard

```bash
# Quick system status
aws stepfunctions list-executions \
  --state-machine-arn "$SF_ARN" \
  --status-filter RUNNING \
  --max-items 10 \
  --query 'executions[].{Name:name,Status:status,Start:startDate}'
```

## Cross-Account Issues

### Issue: Role Assumption Failed

**Symptoms**:

```text
AccessDenied: Unable to assume role arn:aws:iam::ACCOUNT:role/PatchExecRole
```

**Diagnosis**:

```bash
# Test role assumption
aws sts assume-role \
  --role-arn "arn:aws:iam::222222222222:role/PatchExecRole" \
  --role-session-name "diagnostic-test"
```

**Common Causes**:

1. **Missing Trust Relationship**

```bash
# Check trust policy
aws iam get-role --role-name PatchExecRole --query 'Role.AssumeRolePolicyDocument'
```

**Expected Trust Policy**:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::111111111111:role/ec2patch-orchestrator-role"
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": {
          "sts:ExternalId": "unique-external-id-12345"
        }
      }
    }
  ]
}
```

1. **Incorrect External ID**

```bash
# Verify External ID configured for Hub
aws cloudformation describe-stacks \
  --stack-name ec2-patch-hub \
  --query 'Stacks[0].Parameters[?ParameterKey==`CrossAccountExternalId`].ParameterValue' \
  --output text
```

**Resolution**:

```bash
# Update trust policy
aws iam update-assume-role-policy \
  --role-name PatchExecRole \
  --policy-document file://trust-policy.json
```

### Issue: Cross-Account Network Connectivity

**Symptoms**:

- Lambda functions timing out when accessing spoke accounts
- SSM commands failing to reach instances

**Diagnosis**:

```bash
# Check VPC endpoints
aws ec2 describe-vpc-endpoints \
  --filters Name=service-name,Values=com.amazonaws.region.ssm \
  --query 'VpcEndpoints[].{VpcId:VpcId,State:State}'

# Test network connectivity
aws ssm describe-instance-information \
  --query 'InstanceInformationList[?PingStatus==`Online`]'
```

**Resolution**:

1. Ensure VPC endpoints are configured for SSM
2. Verify security group rules allow HTTPS traffic
3. Check NACLs for blocking rules

## Step Functions Problems

### Issue: Execution Stuck in RUNNING State

**Symptoms**:

```bash
# Execution running for extended period
aws stepfunctions describe-execution \
  --execution-arn "$EXECUTION_ARN" \
  --query '{Status:status,StartDate:startDate}'
```

**Diagnosis**:

```bash
# Get execution history
aws stepfunctions get-execution-history \
  --execution-arn "$EXECUTION_ARN" \
  --reverse-order \
  --max-items 10
```

**Common Causes**:

1. **Waiting for Manual Approval**
   - Check SNS notifications sent
   - Verify approval URL accessibility
   - Check approval timeout settings

2. **Lambda Function Timeout**
   - Review CloudWatch logs for timeout errors
   - Increase function timeout if needed
   - Optimize function code

3. **Infinite Loop in State Machine**
   - Review state machine definition
   - Check loop conditions and counters

**Resolution**:

```bash
# Stop stuck execution
aws stepfunctions stop-execution \
  --execution-arn "$EXECUTION_ARN" \
  --error "ManualStop" \
  --cause "Execution stuck, manual intervention required"

# Start new execution with corrected parameters
aws stepfunctions start-execution \
  --state-machine-arn "$SF_ARN" \
  --name "retry-$(date +%s)" \
  --input "$CORRECTED_INPUT"
```

### Issue: State Machine Execution Failed

**Symptoms**:

```json
{
  "status": "FAILED",
  "error": "States.TaskFailed",
  "cause": "Lambda function failed"
}
```

**Diagnosis Steps**:

1. **Get Error Details**:

```bash
aws stepfunctions describe-execution \
  --execution-arn "$EXECUTION_ARN" \
  --query '{Error:error,Cause:cause,Output:output}'
```

1. **Review Execution History**:

```bash
aws stepfunctions get-execution-history \
  --execution-arn "$EXECUTION_ARN" \
  --query 'events[?type==`TaskFailed`]'
```

1. **Check Lambda Logs**:

```bash
aws logs filter-log-events \
  --log-group-name "/aws/lambda/ec2patch-preec2inventory" \
  --start-time $(date -d "1 hour ago" +%s)000 \
  --filter-pattern "ERROR"
```

## Lambda Function Errors

### Issue: PreEC2Inventory Function Failing

**Symptoms**:

```text
ERROR: Unable to describe instances in account 222222222222
```

**Diagnosis**:

```bash
# Check function logs
aws logs tail /aws/lambda/ec2patch-preec2inventory --follow

# Test function with specific input
aws lambda invoke \
  --function-name ec2patch-preec2inventory \
  --payload '{"accounts":["222222222222"],"regions":["us-east-1"]}' \
  response.json
```

**Common Issues**:

1. **Missing Permissions**:
   - EC2 describe permissions in target account
   - SSM describe instance information permissions

2. **Network Timeouts**:
   - VPC configuration issues
   - Security group restrictions

3. **Tag Filter Problems**:
   - Instances not properly tagged
   - Tag key/value mismatches

**Resolution**:

```python
# Enhanced error handling in Lambda
import boto3
from botocore.exceptions import ClientError, NoCredentialsError

def lambda_handler(event, context):
    try:
        # Assume role with proper error handling
        sts_client = boto3.client('sts')
        assumed_role = sts_client.assume_role(
            RoleArn=f"arn:aws:iam::{account_id}:role/PatchExecRole",
            RoleSessionName="ec2-patch-inventory",
            ExternalId=external_id
        )
        
        credentials = assumed_role['Credentials']
        ec2_client = boto3.client(
            'ec2',
            aws_access_key_id=credentials['AccessKeyId'],
            aws_secret_access_key=credentials['SecretAccessKey'],
            aws_session_token=credentials['SessionToken'],
            region_name=region
        )
        
        # Implementation with retry logic
        
    except ClientError as e:
        error_code = e.response['Error']['Code']
        if error_code == 'AccessDenied':
            return {
                'statusCode': 403,
                'error': 'Cross-account access denied',
                'details': str(e)
            }
        elif error_code == 'Throttling':
            # Implement exponential backoff
            time.sleep(2 ** retry_count)
        raise
```

### Issue: Approval Callback Timeout

**Symptoms**:

```text
Task timed out after 180.00 seconds
```

**Diagnosis**:

```bash
# Check function configuration
aws lambda get-function-configuration \
  --function-name ec2patch-ApprovalCallback \
  --query '{Timeout:Timeout,MemorySize:MemorySize}'

# Review CloudWatch metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Duration \
  --dimensions Name=FunctionName,Value=ec2patch-ApprovalCallback \
  --start-time $(date -d "1 hour ago" --iso-8601) \
  --end-time $(date --iso-8601) \
  --period 300 \
  --statistics Average,Maximum
```

**Resolution**:

```bash
# Increase timeout and memory
aws lambda update-function-configuration \
  --function-name ec2patch-ApprovalCallback \
  --timeout 300 \
  --memory-size 512
```

## Systems Manager Issues

### Issue: SSM Commands Failing

**Symptoms**:

- Commands stuck in "InProgress" status
- High failure rates for patch installation

**Diagnosis**:

```bash
# Check command status
aws ssm list-command-invocations \
  --command-id "$COMMAND_ID" \
  --details

# Check SSM agent status
aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=i-1234567890abcdef0" \
  --query 'InstanceInformationList[0].{PingStatus:PingStatus,LastPingDateTime:LastPingDateTime}'
```

**Common Issues**:

1. **SSM Agent Not Running**:

```bash
# On instance, restart SSM agent
sudo systemctl restart amazon-ssm-agent
sudo systemctl status amazon-ssm-agent
```

1. **Instance Role Missing Permissions**:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ssm:UpdateInstanceInformation",
        "ssm:SendCommand",
        "ssm:ListCommands",
        "ssm:ListCommandInvocations",
        "ssm:DescribeInstanceInformation",
        "ssm:GetCommandInvocation",
        "ec2messages:*"
      ],
      "Resource": "*"
    }
  ]
}
```

1. **Network Connectivity Issues**:

```bash
# Test connectivity from instance
curl -I https://ssm.us-east-1.amazonaws.com
curl -I https://ec2messages.us-east-1.amazonaws.com
```

### Issue: Patch Baseline Configuration

**Symptoms**:

- No patches being installed despite availability
- Wrong patches being installed

**Diagnosis**:

```bash
# Check patch baseline
aws ssm describe-patch-baselines \
  --filters Key=OWNER,Values=Self \
  --query 'BaselineIdentities[].{Id:BaselineId,Name:BaselineName}'

# Get baseline details
aws ssm get-patch-baseline \
  --baseline-id "pb-0123456789abcdef0"
```

**Resolution**:

```bash
# Create custom patch baseline
aws ssm create-patch-baseline \
  --name "EC2PatchingBaseline" \
  --operating-system "AMAZON_LINUX_2" \
  --approval-rules '{
    "PatchRules": [
      {
        "PatchFilterGroup": {
          "PatchFilters": [
            {
              "Key": "CLASSIFICATION",
              "Values": ["Security", "Bugfix", "Critical"]
            },
            {
              "Key": "SEVERITY",
              "Values": ["Critical", "Important"]
            }
          ]
        },
        "ApproveAfterDays": 0,
        "ComplianceLevel": "HIGH"
      }
    ]
  }'
```

## EventBridge Problems

### Issue: Scheduled Rules Not Triggering

**Symptoms**:

- Patching waves not starting as scheduled
- No Step Functions executions at expected times

**Diagnosis**:

```bash
# Check rule status
aws events describe-rule --name ec2patch-wave1-critical

# List recent rule executions
aws logs filter-log-events \
  --log-group-name /aws/events/rule/ec2patch-wave1-critical \
  --start-time $(date -d "24 hours ago" +%s)000
```

**Common Issues**:

1. **Rule Disabled**:

```bash
# Enable rule
aws events enable-rule --name ec2patch-wave1-critical
```

1. **Incorrect Cron Expression**:

```bash
# Test cron expression
# For "every Sunday at 2 AM UTC"
aws events put-rule \
  --name test-schedule \
  --schedule-expression "cron(0 2 ? * SUN *)"
```

1. **IAM Permissions for Target**:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowEventBridgeToStartStepFunctions",
      "Effect": "Allow",
      "Principal": {
        "Service": "events.amazonaws.com"
      },
      "Action": "states:StartExecution",
      "Resource": "arn:aws:states:*:*:stateMachine:ec2patch-orchestrator"
    }
  ]
}
```

<!-- Bedrock integration was removed; no AI-related troubleshooting is applicable in CFN-only scope. -->

## Performance Problems

### Issue: Slow Execution Times

**Symptoms**:

- Patch cycles taking longer than expected
- Lambda functions approaching timeout limits

**Diagnosis Tools**:

```bash
# Monitor Step Functions execution metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/States \
  --metric-name ExecutionTime \
  --dimensions Name=StateMachineArn,Value=$SF_ARN \
  --start-time $(date -d "24 hours ago" --iso-8601) \
  --end-time $(date --iso-8601) \
  --period 3600 \
  --statistics Average,Maximum
```

**Optimization Strategies**:

1. **Parallel Processing**:
   - Increase concurrency limits
   - Process accounts in parallel
   - Batch instance operations

2. **Caching**:

- Cache instance inventory
- Reuse cross-account credentials

1. **Timeouts**:
   - Optimize Lambda function timeouts
   - Adjust Step Functions timeouts
   - Set appropriate SSM command timeouts

```python
# Example optimization: Parallel processing
import concurrent.futures
import boto3

def process_account_parallel(accounts, regions):
    with concurrent.futures.ThreadPoolExecutor(max_workers=5) as executor:
        futures = []
        for account in accounts:
            for region in regions:
                future = executor.submit(process_single_account, account, region)
                futures.append(future)
        
        results = []
        for future in concurrent.futures.as_completed(futures):
            try:
                result = future.result(timeout=300)  # 5 minute timeout
                results.append(result)
            except Exception as e:
                print(f"Error processing account: {e}")
        
        return results
```

## Monitoring and Alerting

### CloudWatch Dashboard Setup

```bash
# Create comprehensive dashboard
aws cloudwatch put-dashboard \
  --dashboard-name "EC2-Patching-Operations" \
  --dashboard-body '{
    "widgets": [
      {
        "type": "metric",
        "properties": {
          "metrics": [
            ["AWS/States", "ExecutionsFailed", "StateMachineArn", "'$SF_ARN'"],
            ["AWS/States", "ExecutionsSucceeded", "StateMachineArn", "'$SF_ARN'"]
          ],
          "period": 300,
          "stat": "Sum",
          "region": "us-east-1",
          "title": "Step Functions Execution Status"
        }
      },
      {
        "type": "log",
        "properties": {
          "query": "SOURCE \"/aws/lambda/ec2patch-preec2inventory\" | filter @message like /ERROR/\n| stats count() by bin(5m)",
          "region": "us-east-1",
          "title": "Lambda Function Errors",
          "view": "table"
        }
      }
    ]
  }'
```

### Critical Alerts

```bash
# High failure rate alarm
aws cloudwatch put-metric-alarm \
  --alarm-name "EC2Patch-HighFailureRate" \
  --alarm-description "Patch failure rate exceeds 10%" \
  --metric-name "ExecutionsFailed" \
  --namespace "AWS/States" \
  --statistic "Sum" \
  --period 3600 \
  --threshold 5 \
  --comparison-operator "GreaterThanThreshold" \
  --dimensions Name=StateMachineArn,Value=$SF_ARN \
  --evaluation-periods 1 \
  --alarm-actions "arn:aws:sns:us-east-1:$ACCOUNT_ID:ec2patch-alerts"
```

### Log Analysis Queries

```bash
# CloudWatch Insights queries

# 1. Find most common errors
aws logs start-query \
  --log-group-name "/aws/lambda/ec2patch-orchestrator" \
  --start-time $(date -d "24 hours ago" +%s) \
  --end-time $(date +%s) \
  --query-string 'fields @timestamp, @message
| filter @message like /ERROR/
| stats count() by @message
| sort count desc
| limit 10'

# 2. Execution duration analysis
aws logs start-query \
  --log-group-name "/aws/stepfunctions/StateMachine" \
  --start-time $(date -d "24 hours ago" +%s) \
  --end-time $(date +%s) \
  --query-string 'fields @timestamp, @duration
| filter @type = "ExecutionSucceeded"
| stats avg(@duration), max(@duration), min(@duration) by bin(1h)'
```

## Emergency Procedures

### Emergency Stop All Executions

```bash
#!/bin/bash
# emergency-stop.sh

SF_ARN="arn:aws:states:us-east-1:111111111111:stateMachine:ec2patch-orchestrator"

echo "🚨 Emergency stop initiated for all running executions"

# Get all running executions
aws stepfunctions list-executions \
  --state-machine-arn "$SF_ARN" \
  --status-filter RUNNING \
  --query 'executions[].executionArn' \
  --output text | while read execution_arn; do
    
    echo "Stopping execution: $execution_arn"
    aws stepfunctions stop-execution \
      --execution-arn "$execution_arn" \
      --error "EmergencyStop" \
      --cause "Emergency stop initiated by operations team"
done

# Disable all EventBridge rules
aws events list-rules --name-prefix ec2patch \
  --query 'Rules[].Name' \
  --output text | while read rule_name; do
    
    echo "Disabling rule: $rule_name"
    aws events disable-rule --name "$rule_name"
done

echo "✅ Emergency stop complete"
```

### Rollback Procedures

```bash
# Disable all EventBridge rules for safety
aws events list-rules --name-prefix ec2patch \
  --query 'Rules[].Name' \
  --output text | while read rule_name; do
    echo "Disabling rule: $rule_name"
    aws events disable-rule --name "$rule_name"
done

# Optionally roll back CloudFormation stacks
aws cloudformation deploy \
  --template-file cloudformation/hub-cfn.yaml \
  --stack-name ec2-patch-hub \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides file://cloudformation/params/dev-hub.json
```

## Support Escalation

### Information to Gather

When escalating issues, collect:

1. **Execution Details**:
   - Execution ARN and name
   - Input parameters used
   - Error messages and codes

2. **Environment Information**:

- AWS account IDs involved
- Regions and availability zones
- CloudFormation change sets and stack events

1. **Timing Information**:
   - When issue started
   - Last successful execution
   - Pattern of failures

1. **Logs and Metrics**:
   - CloudWatch logs exports
   - Step Functions execution history
   - Lambda function metrics

### Contact Information

- **Tier 1 Support**: Create GitHub issue with label `bug`
- **Tier 2 Support**: Tag `@platform-team` in issue
- **Emergency**: Use incident response procedures

---

This troubleshooting guide covers the most common issues. For additional support, please refer to the [deployment guide](deployment-guide.md) or contact the platform team.
