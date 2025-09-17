# EC2 Patching Workflow - API Reference

## Overview

This document provides comprehensive API reference for the Enterprise EC2 Multi-Account Patching Platform, including Step Functions, Lambda functions, and integration APIs.

## Table of Contents

- [Step Functions API](#step-functions-api)
- [Lambda Functions](#lambda-functions)
- [EventBridge Integration](#eventbridge-integration)
- [Systems Manager Integration](#systems-manager-integration)
- [SNS Notifications](#sns-notifications)
- [Error Handling](#error-handling)

## Step Functions API

### State Machine Execution

#### Start Execution

**Endpoint**: `stepfunctions:StartExecution`

```bash
aws stepfunctions start-execution \
  --state-machine-arn "arn:aws:states:region:account:stateMachine:ec2patch-orchestrator" \
  --name "execution-name" \
  --input '{
    "waveId": "string",
    "dryRun": boolean,
    "accounts": ["string"],
    "regions": ["string"],
    "tagFilters": {
      "key": "value"
    },
    "instanceIds": ["string"],
    "approvalRequired": boolean,
    "notificationEmail": "string"
  }'
```

**Input Parameters**:

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `waveId` | string | No | Wave identifier for scheduled execution |
| `dryRun` | boolean | No | Execute without making changes (default: false) |
| `accounts` | array | Yes | List of AWS account IDs to patch |
| `regions` | array | Yes | List of AWS regions to patch |
| `tagFilters` | object | No | EC2 instance tag filters |
| `instanceIds` | array | No | Specific instance IDs to patch |
| `approvalRequired` | boolean | No | Require manual approval (default: true) |
| `notificationEmail` | string | No | Override default notification email |

**Response**:

```json
{
  "executionArn": "arn:aws:states:region:account:execution:ec2patch-orchestrator:execution-name",
  "startDate": "2025-08-27T10:00:00.000Z"
}
```

#### Get Execution Status

```bash
aws stepfunctions describe-execution \
  --execution-arn "arn:aws:states:region:account:execution:ec2patch-orchestrator:execution-name"
```

**Response**:

```json
{
  "executionArn": "string",
  "stateMachineArn": "string",
  "name": "string",
  "status": "RUNNING|SUCCEEDED|FAILED|TIMED_OUT|ABORTED",
  "startDate": "2025-08-27T10:00:00.000Z",
  "stopDate": "2025-08-27T11:00:00.000Z",
  "input": "{}",
  "output": "{}",
  "error": "string",
  "cause": "string"
}
```

#### Stop Execution

```bash
aws stepfunctions stop-execution \
  --execution-arn "arn:aws:states:region:account:execution:ec2patch-orchestrator:execution-name" \
  --error "UserInitiated" \
  --cause "Manual stop requested"
```

## Lambda Functions

### PreEC2Inventory

**Purpose**: Discover EC2 instances eligible for patching

**Input**:

```json
{
  "accounts": ["111111111111"],
  "regions": ["us-east-1"],
  "tagFilters": {
    "PatchGroup": "default",
    "Environment": "production"
  },
  "instanceIds": ["i-1234567890abcdef0"]
}
```

**Output**:

```json
{
  "instances": [
    {
      "instanceId": "i-1234567890abcdef0",
      "accountId": "111111111111",
      "region": "us-east-1",
      "imageId": "ami-0123456789abcdef0",
      "instanceType": "t3.medium",
      "state": "running",
      "tags": {
        "PatchGroup": "default",
        "Environment": "production"
      },
      "ssmStatus": "Online",
      "lastPatchDate": "2025-07-15T10:30:00.000Z",
      "patchLevel": "current"
    }
  ],
  "summary": {
    "totalInstances": 1,
    "eligibleInstances": 1,
    "excludedInstances": 0
  }
}
```

### SendApprovalRequest

**Purpose**: Initiate manual approval workflow

**Input**:

```json
{
  "executionName": "patch-execution-12345",
  "instances": [
    {
      "instanceId": "i-1234567890abcdef0",
      "accountId": "111111111111",
      "region": "us-east-1"
    }
  ],
  "approvers": ["ops-team@company.com"],
  "timeoutMinutes": 60
}
```

**Output**:

```json
{
  "approvalToken": "approval-token-12345",
  "snsMessageId": "12345678-1234-1234-1234-123456789012",
  "approvalUrl": "https://console.aws.amazon.com/stepfunctions/approval?token=approval-token-12345",
  "expiresAt": "2025-08-27T11:00:00.000Z"
}
```


### ApprovalCallback

**Purpose**: Process approval responses

**Input**:
```json
{
  "approvalToken": "approval-token-12345",
  "decision": "APPROVED|REJECTED",
  "comments": "Approved for emergency security patch",
  "approver": "ops-team@company.com"
}
```

**Output**:
```json
{
  "status": "success",
  "decision": "APPROVED",
  "processedAt": "2025-08-27T10:30:00.000Z"
}
```


### PollSsmCommand

**Purpose**: Monitor Systems Manager command execution

**Input**:
```json
{
  "commandId": "12345678-1234-1234-1234-123456789012",
  "instanceIds": ["i-1234567890abcdef0"],
  "maxWaitTimeMinutes": 30
}
```

**Output**:
```json
{
  "commandStatus": "Success|InProgress|Failed|Cancelled",
  "instanceResults": [
    {
      "instanceId": "i-1234567890abcdef0",
      "status": "Success",
      "exitCode": 0,
      "output": "Successfully installed 5 updates",
      "standardError": "",
      "executionStartDateTime": "2025-08-27T10:00:00.000Z",
      "executionEndDateTime": "2025-08-27T10:15:00.000Z"
    }
  ],
  "summary": {
    "totalInstances": 1,
    "successfulInstances": 1,
    "failedInstances": 0
  }
}
```


### PostEC2Verify

**Purpose**: Validate EC2 instances after patching

**Input**:
```json
{
  "instances": [
    {
      "instanceId": "i-1234567890abcdef0",
      "accountId": "111111111111",
      "region": "us-east-1"
    }
  ],
  "verificationTests": [
    "instanceState",
    "ssmConnectivity",
    "applicationHealth"
  ]
}
```

**Output**:
```json
{
  "verificationResults": [
    {
      "instanceId": "i-1234567890abcdef0",
      "overallStatus": "HEALTHY",
      "tests": {
        "instanceState": "PASSED",
        "ssmConnectivity": "PASSED", 
        "applicationHealth": "PASSED"
      },
      "issues": [],
      "recommendations": []
    }
  ],
  "summary": {
    "totalInstances": 1,
    "healthyInstances": 1,
    "unhealthyInstances": 0
  }
}
```



## EventBridge Integration

### Wave Execution Events

**Event Pattern**:

```json
{
  "source": ["aws.ec2patching"],
  "detail-type": ["EC2 Patch Wave Execution"],
  "detail": {
    "waveId": ["string"],
    "accounts": ["string"],
    "regions": ["string"],
    "scheduleExpression": ["string"]
  }
}
```


### Custom Rule Creation

```bash
aws events put-rule \
  --name "custom-patch-wave" \
  --schedule-expression "cron(0 3 ? * SUN *)" \
  --state ENABLED \
  --description "Custom patching wave for development accounts"

aws events put-targets \
  --rule "custom-patch-wave" \
  --targets 'Id=1,Arn=arn:aws:states:region:account:stateMachine:ec2patch-orchestrator,Input="{\"waveId\":\"custom-dev\",\"accounts\":[\"444444444444\"],\"regions\":[\"us-east-1\"]}"'
```

## Systems Manager Integration

### Patch Baseline Selection

```bash
# Get patch baseline
aws ssm get-patch-baseline \
  --baseline-id "pb-0123456789abcdef0"

# Create custom patch baseline
aws ssm create-patch-baseline \
  --name "CustomEC2PatchBaseline" \
  --operating-system "AMAZON_LINUX_2" \
  --approval-rules 'PatchRules=[{PatchFilterGroup={PatchFilters=[{Key=CLASSIFICATION,Values=[Security,Bugfix]}]},ApproveAfterDays=7}]'
```

### Command Execution

```bash
# Send patch command
aws ssm send-command \
  --document-name "AWS-RunPatchBaseline" \
  --parameters 'Operation=Install,RebootOption=RebootIfNeeded' \
  --targets 'Key=tag:PatchGroup,Values=default' \
  --max-concurrency 10 \
  --max-errors 2
```


## SNS Notifications

### Message Format

```json
{
  "eventType": "PATCH_EXECUTION_STARTED|APPROVAL_REQUIRED|PATCH_COMPLETED|PATCH_FAILED",
  "timestamp": "2025-08-27T10:00:00.000Z",
  "executionArn": "arn:aws:states:region:account:execution:name",
  "waveId": "wave1-critical",
  "accounts": ["111111111111"],
  "regions": ["us-east-1"],
  "instanceCount": 5,
  "details": {
    "message": "Patch execution completed successfully",
    "successCount": 5,
    "failureCount": 0
  }
}
```


### Subscription Management

```bash
# Subscribe to notifications
aws sns subscribe \
  --topic-arn "arn:aws:sns:region:account:ec2patch-notifications" \
  --protocol "email" \
  --notification-endpoint "ops-team@company.com"

# Set message filtering
aws sns set-subscription-attributes \
  --subscription-arn "arn:aws:sns:region:account:ec2patch-notifications:subscription-id" \
  --attribute-name FilterPolicy \
  --attribute-value '{"eventType":["PATCH_FAILED","APPROVAL_REQUIRED"]}'
```

## Error Handling

### Common Error Codes

| Error Code | Description | Resolution |
|------------|-------------|------------|
| `CrossAccountAccessDenied` | Cannot assume role in spoke account | Verify trust relationship and ExternalId |
| `InstanceNotFound` | Target instance does not exist | Check instance ID and account |
| `SSMNotResponding` | SSM agent not responding | Verify SSM agent status and connectivity |
| `PatchBaselineNotFound` | Patch baseline not configured | Create or assign patch baseline |
| `ApprovalTimeout` | Manual approval timed out | Increase timeout or resend approval |
| `ApprovalTimeout` | Manual approval timed out | Increase timeout or resend approval |

### Error Response Format

```json
{
  "errorCode": "CrossAccountAccessDenied",
  "errorMessage": "Unable to assume role in account 222222222222",
  "details": {
    "accountId": "222222222222",
    "roleArn": "arn:aws:iam::222222222222:role/PatchExecRole",
    "requestId": "request-12345"
  },
  "timestamp": "2025-08-27T10:00:00.000Z",
  "retryable": true
}
```

### Retry Logic

```python
import boto3
from botocore.exceptions import ClientError
import time

def execute_with_retry(func, max_retries=3, backoff_factor=2):
    for attempt in range(max_retries):
        try:
            return func()
        except ClientError as e:
            if attempt == max_retries - 1:
                raise
            
            if e.response['Error']['Code'] in ['Throttling', 'TooManyRequestsException']:
                wait_time = backoff_factor ** attempt
                time.sleep(wait_time)
            else:
                raise
```

## Rate Limits and Quotas

### AWS Service Limits

| Service | Limit | Workaround |
|---------|-------|------------|
| Step Functions executions | 2000 concurrent | Use execution queuing |
| Lambda concurrent executions | 1000 (default) | Request limit increase |
| SSM concurrent commands | 100 per account | Implement batching |
| SNS message rate | 30,000 per second | Use SQS for high volume |

### Best Practices

1. **Implement exponential backoff** for retries
2. **Use jitter** to avoid thundering herd
3. **Monitor CloudWatch metrics** for throttling
4. **Implement circuit breakers** for external dependencies
5. **Use queuing mechanisms** for high-volume operations

---

For additional technical details and examples, please refer to the individual Lambda function source code and the [deployment guide](deployment-guide.md).
