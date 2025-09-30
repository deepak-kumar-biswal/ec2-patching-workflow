# CloudFormation Integration - Custom SSM Documents

This guide explains how to deploy the EC2 patching workflow with built-in custom SSM documents that are automatically created and shared with spoke accounts.

## 🎯 Overview

The enhanced CloudFormation template now includes:
- **Custom SSM Documents**: Windows and Linux patching documents with pre/post operations
- **Automatic Sharing**: Documents are automatically shared with specified spoke accounts
- **Infrastructure as Code**: All resources managed through CloudFormation
 - **Always On**: Custom documents are always created and used (no toggle)

## 📋 Prerequisites

1. **Hub Account Setup**: Deploy the hub CloudFormation stack first
2. **Spoke Account IDs**: Have the list of spoke account IDs ready for sharing
3. **Lambda Artifacts**: Upload the Lambda deployment package to S3
4. **External ID**: Generate a secure external ID for cross-account access

## 🚀 Deployment Steps

### Step 1: Prepare Parameter File

Create or update your parameter file with spoke account IDs:

```json
{
  "ParameterKey": "SpokeAccountIds", 
  "ParameterValue": "222222222222,333333333333,444444444444"
}
```

### Step 2: Deploy Hub Stack

```bash
aws cloudformation deploy \
  --template-file cloudformation/hub-cfn.yaml \
  --stack-name ec2-patch-hub-prod \
  --parameter-overrides file://cloudformation/params/prod-hub-with-custom-documents.json \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-east-1
```

### Step 3: Verify Document Creation

```bash
# List created documents
aws ssm describe-document \
  --name "ec2-patch-prod-WindowsCustomPatch" \
  --region us-east-1

aws ssm describe-document \
  --name "ec2-patch-prod-LinuxCustomPatch" \
  --region us-east-1
```

### Step 4: Verify Document Sharing

```bash
# Check document permissions
aws ssm describe-document-permission \
  --name "ec2-patch-prod-WindowsCustomPatch" \
  --permission-type Share \
  --region us-east-1
```

### Step 5: Deploy Spoke Stacks

Deploy spoke stacks in target accounts using the existing spoke CloudFormation template:

```bash
aws cloudformation deploy \
  --template-file cloudformation/spoke-cfn.yaml \
  --stack-name ec2-patch-spoke-prod \
  --parameter-overrides file://cloudformation/params/prod-spoke.json \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-east-1
```

## 🔧 Configuration Details

### Custom Document Parameters

The custom documents are automatically configured with these parameters:

 
#### Windows Document Parameters

- `Operation`: Install or Scan mode
- `RebootOption`: NoReboot or RebootIfNeeded  
- `IncludeKbs`: Specific KBs to include
- `ExcludeKbs`: KBs to exclude from patching
- `ServiceNames`: Services to stop before patching
- `BackupLocation`: S3 path for configuration backups
- `MaintenanceMode`: Enable/disable maintenance notifications

 
#### Linux Document Parameters

- `Operation`: Install or Scan mode
- `RebootOption`: NoReboot or RebootIfNeeded
- `PackageNames`: Specific packages to update
- `ExcludePackages`: Packages to exclude
- `ServiceNames`: Services to stop before patching  
- `BackupLocation`: S3 path for configuration backups
- `MaintenanceMode`: Enable/disable maintenance notifications

### Document Sharing Mechanism

The CloudFormation template includes:

1. **ShareDocumentsFunction**: Lambda function that handles document sharing
2. **ShareDocumentsRole**: IAM role with permissions to modify document permissions
3. **Custom Resources**: Trigger document sharing when stack is deployed/updated

## 🎛️ CloudFormation Parameters

### New Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `SpokeAccountIds` | CommaDelimitedList | "" | Spoke account IDs for document sharing |

### Existing Parameters (for Custom Documents)

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `WindowsPrePatchDocument` | String | WindowsPrePatch | Windows pre-patch document name |
| `WindowsPatchDocument` | String | WindowsPatch | Windows patch document name |
| `WindowsPostPatchDocument` | String | WindowsPostPatch | Windows post-patch document name |
| `LinuxPrePatchDocument` | String | LinuxPrePatch | Linux pre-patch document name |
| `LinuxPatchDocument` | String | LinuxPatch | Linux patch document name |
| `LinuxPostPatchDocument` | String | LinuxPostPatch | Linux post-patch document name |

## 📊 CloudFormation Outputs

The template provides these outputs:

 
```yaml
Outputs:
  WindowsCustomPatchDocumentName:
    Description: Name of the Windows custom patch document
    Value: ec2-patch-prod-WindowsCustomPatch
    
  LinuxCustomPatchDocumentName:
    Description: Name of the Linux custom patch document  
    Value: ec2-patch-prod-LinuxCustomPatch
    
  SharedDocuments:
    Description: List of custom SSM documents available for patching
    Value: "ec2-patch-prod-WindowsCustomPatch, ec2-patch-prod-LinuxCustomPatch"
```

## 🔄 Document Updates

When you update the CloudFormation stack:

1. **Document Content**: Changes to document content are automatically applied
2. **New Spoke Accounts**: Adding accounts to `SpokeAccountIds` shares documents with new accounts
3. **Automatic Versioning**: SSM automatically versions document updates

### Update Example

 
```bash
# Update stack with new spoke account
aws cloudformation deploy \
  --template-file cloudformation/hub-cfn.yaml \
  --stack-name ec2-patch-hub-prod \
  --parameter-overrides \
    SpokeAccountIds="222222222222,333333333333,444444444444,555555555555" \
  --capabilities CAPABILITY_NAMED_IAM
```

## 🔒 Security Considerations

### IAM Permissions

The sharing Lambda function has minimal permissions:
```json
{
  "Effect": "Allow",
  "Action": [
    "ssm:ModifyDocumentPermission",
    "ssm:DescribeDocumentPermission", 
    "ssm:DescribeDocument"
  ],
  "Resource": "arn:aws:ssm:*:*:document/ec2-patch-*"
}
```

### Document Access

- Documents are shared with specific spoke accounts only
- Cross-account access requires the existing IAM role structure
- Documents inherit execution context from the orchestrator

## 🚨 Troubleshooting

### Common Issues

 
#### Document Sharing Fails
 
```bash
# Check CloudFormation events
aws cloudformation describe-stack-events \
  --stack-name ec2-patch-hub-prod \
  --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`]'

# Check Lambda logs
aws logs filter-log-events \
  --log-group-name "/aws/lambda/ec2-patch-prod-ShareSSMDocuments" \
  --start-time $(date -d '1 hour ago' +%s)000
```

 
#### Document Not Available in Spoke Account

1. Verify the document was shared: `aws ssm describe-document-permission`
2. Check spoke account has the correct cross-account role
3. Ensure the spoke account is in the same region

 
#### Document Execution Fails

1. Verify the orchestrator is using the correct document names
2. Check document parameters match the expected format
3. Review SSM execution logs in CloudWatch

### Manual Verification

 
```bash
# Test document execution in spoke account
aws ssm send-command \
  --document-name "ec2-patch-prod-WindowsCustomPatch" \
  --targets "Key=tag:PatchGroup,Values=test-servers" \
  --parameters "Operation=Scan,RebootOption=NoReboot" \
  --region us-east-1
```

## 📈 Monitoring

The enhanced template includes monitoring for:

- **Document Creation**: CloudFormation stack events
- **Document Sharing**: Lambda function logs
- **Document Usage**: SSM command executions in CloudWatch

## 🔄 Integration with Existing Workflow

Custom SSM documents are now the only execution mode and integrate seamlessly:

1. Existing Lambda functions work unchanged (they are document-agnostic)
2. Document names are passed via Step Functions inputs
3. No fallback to default patching exists; all executions use custom documents

## 📚 Next Steps

1. **Test in Dev**: Deploy to development environment first
2. **Validate Documents**: Test custom documents with sample instances
3. **Monitor Executions**: Set up CloudWatch dashboards for document metrics
4. **Customize Documents**: Modify document content for your specific requirements

## 🏷️ Tags

All created resources are tagged with:

- `Name`: Resource identifier
- `Environment`: Deployment environment
- Standard AWS tags for cost allocation
