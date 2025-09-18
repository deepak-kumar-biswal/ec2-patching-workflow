# Using Custom SSM Documents

## Overview

The EC2 Patching Orchestrator supports your existing custom SSM documents for Windows and Linux systems. This allows you to use specialized pre-patch, patch, and post-patch operations while maintaining the simplified orchestration workflow.

## Configuration

### 1. CloudFormation Parameters

Enable custom documents during deployment:

```yaml
# In hub-cfn.yaml parameters
CustomSsmDocuments: ENABLED
WindowsPrePatchDocument: 'WindowsPrePatch'
WindowsPatchDocument: 'WindowsPatch'
WindowsPostPatchDocument: 'WindowsPostPatch'
LinuxPrePatchDocument: 'LinuxPrePatch'
LinuxPatchDocument: 'LinuxPatch'
LinuxPostPatchDocument: 'LinuxPostPatch'
```

### 2. Execution Input

When triggering manually, include custom document configuration:

```json
{
  "useCustomDocuments": true,
  "customDocuments": {
    "windowsPrePatch": "WindowsPrePatch",
    "windowsPatch": "WindowsPatch", 
    "windowsPostPatch": "WindowsPostPatch",
    "linuxPrePatch": "LinuxPrePatch",
    "linuxPatch": "LinuxPatch",
    "linuxPostPatch": "LinuxPostPatch"
  }
}
```

## Execution Flow

### Standard Flow (Custom Documents Disabled)
```text
PreCollect → SendSSM (AWS-RunPatchBaseline) → MonitorSSM → PostVerify
```

### Custom Documents Flow (Enabled)
```text
PreCollect → CustomPrePatch → CustomPatch → CustomPostPatch → PostVerify
     ↓              ↓             ↓               ↓
Windows/Linux  Windows/Linux  Windows/Linux  Windows/Linux
   PrePatch      Patch         PostPatch
   Documents     Documents     Documents
```

## Platform Targeting

The orchestrator automatically targets the correct OS platforms:

- **Windows Documents**: Target instances with `Platform=Windows` tag
- **Linux Documents**: Target instances with `Platform=Linux` tag  
- **Combined**: Target instances with `PatchGroup=<value>` tag

## Document Execution Details

### Pre-Patch Phase
- Runs your `WindowsPrePatch` and `LinuxPrePatch` documents in parallel
- Output stored in S3: `runs/{executionId}/custom-pre/account-{}/region-{}/windows|linux/`
- Continues to patch phase even if pre-patch fails (with error logging)

### Patch Phase  
- Runs your `WindowsPatch` and `LinuxPatch` documents in parallel
- Replaces the standard `AWS-RunPatchBaseline` document
- Output stored in S3: `runs/{executionId}/custom-patch/account-{}/region-{}/windows|linux/`

### Post-Patch Phase
- Runs your `WindowsPostPatch` and `LinuxPostPatch` documents in parallel  
- Output stored in S3: `runs/{executionId}/custom-post/account-{}/region-{}/windows|linux/`
- Continues to verification even if post-patch fails (with error logging)

## Example Custom Documents

### WindowsPrePatch
```yaml
schemaVersion: '2.2'
description: 'Windows Pre-Patch Operations'
parameters:
  commands:
    type: StringList
    default:
      - 'Get-Service | Where-Object {$_.Status -eq "Running"} | Export-Csv C:\temp\services-before.csv'
      - 'Get-HotFix | Export-Csv C:\temp\patches-before.csv'
      - 'Stop-Service -Name "MyApp" -Force'
mainSteps:
  - action: aws:runPowerShellScript
    name: PrePatchSteps
    inputs:
      runCommand: '{{ commands }}'
```

### LinuxPrePatch
```yaml
schemaVersion: '2.2'
description: 'Linux Pre-Patch Operations'
parameters:
  commands:
    type: StringList
    default:
      - 'systemctl list-units --type=service --state=running > /tmp/services-before.txt'
      - 'dpkg -l > /tmp/packages-before.txt || rpm -qa > /tmp/packages-before.txt'
      - 'systemctl stop myapp.service'
mainSteps:
  - action: aws:runShellScript
    name: PrePatchSteps
    inputs:
      runCommand: '{{ commands }}'
```

## Command Line Usage

### Enable Custom Documents
```bash
aws cloudformation deploy \
  --template-file cloudformation/hub-cfn.yaml \
  --parameter-overrides \
    CustomSsmDocuments=ENABLED \
    WindowsPrePatchDocument=WindowsPrePatch \
    WindowsPatchDocument=WindowsPatch \
    WindowsPostPatchDocument=WindowsPostPatch \
    LinuxPrePatchDocument=LinuxPrePatch \
    LinuxPatchDocument=LinuxPatch \
    LinuxPostPatchDocument=LinuxPostPatch
```

### Trigger Execution with Custom Documents
```bash
aws stepfunctions start-execution \
  --state-machine-arn arn:aws:states:us-east-1:123456789012:stateMachine:ec2-patch-prod-orchestrator \
  --input file://examples/custom-inputs/custom-ssm-documents.json
```

### Disable Custom Documents (Fall back to AWS-RunPatchBaseline)
```bash
aws cloudformation deploy \
  --template-file cloudformation/hub-cfn.yaml \
  --parameter-overrides \
    CustomSsmDocuments=DISABLED
```

## Error Handling

- **Document Not Found**: Execution continues with error logged in CloudWatch
- **Permission Issues**: Ensure the cross-account role has access to your custom documents
- **Timeout**: Individual document execution respects SSM timeout settings
- **Partial Failures**: Pre-patch and post-patch failures don't abort the workflow

## Monitoring

### CloudWatch Logs
- Step Functions logs show custom document execution status
- Lambda function logs contain detailed command execution results

### S3 Output
- Pre-patch outputs: `runs/{id}/custom-pre/account-{}/region-{}/windows|linux/`
- Patch outputs: `runs/{id}/custom-patch/account-{}/region-{}/windows|linux/` 
- Post-patch outputs: `runs/{id}/custom-post/account-{}/region-{}/windows|linux/`

### Notifications
SNS notifications include custom document execution status and any failures.

## Migration Strategy

1. **Test Phase**: Deploy with `CustomSsmDocuments=DISABLED` to verify standard flow
2. **Gradual Rollout**: Enable custom documents for specific accounts/regions
3. **Full Deployment**: Update scheduled executions to use custom documents
4. **Monitoring**: Validate custom document outputs match expectations

## Troubleshooting

### Common Issues

**Custom document not found**
- Verify document exists in target account/region
- Check document name spelling in parameters

**Permission denied**
- Ensure cross-account role has `ssm:SendCommand` for your custom documents
- Verify document permissions allow cross-account execution

**Timeout issues**
- Review document timeout settings
- Consider breaking complex operations into smaller documents

**Platform targeting**
- Ensure instances have `Platform` tags set correctly: `Windows` or `Linux`
- Verify `PatchGroup` tags match your targeting criteria