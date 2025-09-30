# Using Custom SSM Documents

## Overview

The EC2 Patching Orchestrator now runs on custom SSM documents only. Your Windows and Linux pre/patch/post documents are created and centrally managed by the hub CloudFormation stack, and automatically shared to spoke accounts.

## Configuration

### 1. CloudFormation Parameters

Set or override the document names during deployment:

```json
{
  "WindowsPrePatchDocument": "WindowsPrePatch",
  "WindowsPatchDocument": "WindowsPatch",
  "WindowsPostPatchDocument": "WindowsPostPatch",
  "LinuxPrePatchDocument": "LinuxPrePatch",
  "LinuxPatchDocument": "LinuxPatch",
  "LinuxPostPatchDocument": "LinuxPostPatch"
}
```

### 2. Execution Input (optional overrides)

You can optionally override the document names per run. Omit this block to use the stack defaults:

```json
{
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

```text
PreCollect → CustomPrePatch → CustomPatch → CustomPostPatch → PostVerify
     ↓              ↓             ↓               ↓
Windows/Linux  Windows/Linux  Windows/Linux  Windows/Linux
   PrePatch      Patch         PostPatch
   Documents     Documents     Documents
```

## Platform Targeting

The orchestrator automatically targets the correct OS platforms:

- Windows documents target Windows instances
- Linux documents target Linux instances  
- Combined targeting can be controlled with tags like `PatchGroup=<value>`

## Document Execution Details

### Pre-Patch Phase

- Runs your Windows and Linux pre-patch documents in parallel
- Output stored in S3: `runs/{executionId}/custom-pre/account-{}/region-{}/windows|linux/`
- Continues to patch phase even if pre-patch fails (with error logging)

### Patch Phase

- Runs your Windows and Linux patch documents in parallel
- Replaces the legacy `AWS-RunPatchBaseline` path entirely
- Output stored in S3: `runs/{executionId}/custom-patch/account-{}/region-{}/windows|linux/`

### Post-Patch Phase

- Runs your Windows and Linux post-patch documents in parallel  
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
      - 'Get-Service | Where-Object {$_.Status -eq "Running"} | Export-Csv C:\\temp\\services-before.csv'
      - 'Get-HotFix | Export-Csv C:\\temp\\patches-before.csv'
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

### Deploy with custom document names

```bash
aws cloudformation deploy \
  --template-file cloudformation/hub-cfn.yaml \
  --parameter-overrides \
    WindowsPrePatchDocument=WindowsPrePatch \
    WindowsPatchDocument=WindowsPatch \
    WindowsPostPatchDocument=WindowsPostPatch \
    LinuxPrePatchDocument=LinuxPrePatch \
    LinuxPatchDocument=LinuxPatch \
    LinuxPostPatchDocument=LinuxPostPatch
```

### Trigger execution (optional overrides via input)

```bash
aws stepfunctions start-execution \
  --state-machine-arn arn:aws:states:us-east-1:123456789012:stateMachine:ec2-patch-prod-orchestrator \
  --input file://examples/custom-inputs/custom-ssm-documents.json
```

## Error Handling

- Document not found: Execution continues with error logged in CloudWatch
- Permission issues: Ensure the cross-account role has access to your custom documents
- Timeout: Individual document execution respects SSM timeout settings
- Partial failures: Pre-patch and post-patch failures don't abort the workflow

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

## Troubleshooting

### Common Issues

Custom document not found

- Verify document exists in hub account and is shared to spokes
- Check document name spelling in parameters or input overrides

Permission denied

- Ensure cross-account role has `ssm:SendCommand` for your custom documents
- Verify document permissions allow cross-account execution

Timeout issues

- Review document timeout settings
- Consider breaking complex operations into smaller documents

Platform targeting

- Ensure instances are correctly identified as Windows or Linux
- Verify `PatchGroup` tags match your targeting criteria
