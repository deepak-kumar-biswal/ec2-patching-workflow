# Notification Examples

## Overview
The simplified EC2 patching orchestrator supports optional SNS notifications for critical events and status updates.

## Configuration
Set the `NotificationEmail` parameter when deploying the CloudFormation template:

```bash
aws cloudformation create-stack \
  --stack-name ec2-patch-hub-prod \
  --template-body file://hub-cfn.yaml \
  --parameters ParameterKey=NotificationEmail,ParameterValue=ops-team@company.com \
  --capabilities CAPABILITY_IAM
```

## Notification Events

### Automatic CloudWatch Alarms
The following alarms will trigger SNS notifications:

1. **Step Function Execution Failures** - Immediate notification when orchestration fails
2. **Lambda Function Errors** - When 5+ Lambda errors occur within 5 minutes  
3. **Low Patch Success Rate** - When success rate drops below 80%

### Programmatic Notifications from Lambda
Lambda functions can send custom notifications using the SNS topic:

```python
import boto3
import os
import json

def send_notification(subject, message, details=None):
    """Send SNS notification if topic is configured"""
    sns_topic_arn = os.environ.get('SNS_TOPIC_ARN')
    if not sns_topic_arn:
        return
    
    sns = boto3.client('sns')
    
    # Structure the message
    notification_body = {
        'timestamp': datetime.utcnow().isoformat(),
        'subject': subject,
        'message': message,
        'details': details or {}
    }
    
    try:
        sns.publish(
            TopicArn=sns_topic_arn,
            Subject=f"[EC2 Patching] {subject}",
            Message=json.dumps(notification_body, indent=2)
        )
    except Exception as e:
        print(f"Failed to send notification: {e}")

# Example usage in PreEC2Inventory
def handler(event, context):
    try:
        # Inventory logic here...
        instance_count = len(discovered_instances)
        
        # Send start notification
        send_notification(
            "Patching Started",
            f"EC2 patching initiated for {instance_count} instances",
            {
                "accounts": event.get('accounts', []),
                "regions": event.get('regions', []),
                "patch_group": event.get('ec2', {}).get('tagValue'),
                "execution_id": context.aws_request_id
            }
        )
        
    except Exception as e:
        # Send error notification
        send_notification(
            "Patching Error",
            f"Failed during inventory phase: {str(e)}",
            {"error_type": type(e).__name__}
        )
        raise
```

## Notification Content Examples

### Execution Start
```json
{
  "timestamp": "2025-09-17T02:00:15Z",
  "subject": "Patching Started", 
  "message": "EC2 patching initiated for 45 instances",
  "details": {
    "accounts": ["123456789012"],
    "regions": ["us-east-1", "us-west-2"],
    "patch_group": "prod-servers",
    "execution_id": "arn:aws:states:us-east-1:123456789012:execution:ec2-patch-prod-orchestrator:scheduled-prod-20250917"
  }
}
```

### Completion Summary
```json
{
  "timestamp": "2025-09-17T03:45:22Z",
  "subject": "Patching Completed",
  "message": "EC2 patching completed with 98% success rate",
  "details": {
    "total_instances": 45,
    "successful": 44,
    "failed": 1,
    "success_rate": 97.8,
    "duration_minutes": 105,
    "failed_instances": ["i-1234567890abcdef0"]
  }
}
```

### Error Alert
```json
{
  "timestamp": "2025-09-17T02:30:45Z",
  "subject": "Patching Error",
  "message": "High failure rate detected in us-west-2",
  "details": {
    "region": "us-west-2",
    "failure_rate": 0.25,
    "failed_count": 8,
    "error_summary": "SSM agent unreachable on 8 instances"
  }
}
```

## Disabling Notifications
Leave the `NotificationEmail` parameter empty to disable all notifications:

```bash
--parameters ParameterKey=NotificationEmail,ParameterValue=""
```

This will skip SNS topic creation and alarm actions while keeping all other functionality intact.