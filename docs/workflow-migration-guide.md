# Workflow Migration Guide

## Overview

This guide helps you update your workflows and parameter files to work with the simplified EC2 patching orchestrator that now uses custom SSM documents exclusively.

## What Changed

### ❌ Removed (Old Complex System)

- Approval workflow parameters (`ApprovalTimeoutSeconds`, `ApprovalEmail`, `ApprovalSigningSecretString`)
- Complex `waves` input format with nested filters
- Multiple IAM roles and approval Lambda functions
- Standard AWS-RunPatchBaseline execution path

### ✅ Added (New Simplified System)

- SNS notification parameters (`NotificationEmail`)
- Custom SSM document parameters (6 new parameters)
- EventBridge scheduling parameters
- Simplified `accountWaves` input format
- Always-on custom SSM documents

## Migration Steps

### 1. Update Parameter Files

Before (`cloudformation/params/prod-hub.json`):

```json
{
  "NamePrefix": "ec2-patch",
  "Environment": "prod",
  "ApprovalTimeoutSeconds": 3600,
  "ApprovalEmail": "",
  "ApprovalSigningSecretString": "",
  "CrossAccountExternalId": "CHANGE-ME"
}
```

After (now simplified and custom-docs-only):

```json
{
  "NamePrefix": "ec2-patch",
  "Environment": "prod",
  "EnableScheduledExecution": "ENABLED",
  "PatchingSchedule": "cron(0 2 ? * SUN *)",
  "DefaultPatchGroup": "prod-servers",
  "NotificationEmail": "ops-team@company.com",
  "WindowsPrePatchDocument": "WindowsPrePatch",
  "WindowsPatchDocument": "WindowsPatch",
  "WindowsPostPatchDocument": "WindowsPostPatch",
  "LinuxPrePatchDocument": "LinuxPrePatch",
  "LinuxPatchDocument": "LinuxPatch",
  "LinuxPostPatchDocument": "LinuxPostPatch",
  "CrossAccountExternalId": "CHANGE-ME"
}
```

### 2. Update Input JSON Files

Before (`examples/run-inputs/canary-small.json`):

```json
{
  "waves": [
    {
      "name": "canary",
      "accounts": ["111111111111"],
      "regions": ["us-east-1"],
      "filters": {
        "tags": { "PatchGroup": ["default"] },
        "platforms": ["Linux", "Windows"]
      },
      "ssm": {
        "maxConcurrency": "10%",
        "maxErrors": "1",
        "operation": "Install",
        "rebootOption": "RebootIfNeeded"
      }
    }
  ]
}
```

After (simplified):

```json
{
  "comment": "Canary test with small instance set",
  "executionName": "canary-small",
  "accountWaves": [
    {
      "name": "canary-wave",
      "accounts": ["111111111111"],
      "regions": ["us-east-1"]
    }
  ],
  "ec2": {
    "tagKey": "PatchGroup",
    "tagValue": "default"
  },
  "preCollect": {
    "enabled": true
  },
  "abortOnIssues": true
}
```

### 3. CI Updates (if you use GitHub Actions)

- Route standard scenarios to `examples/run-inputs/`
- Route custom-doc scenarios to `examples/custom-inputs/`

### 4. New Capabilities

EventBridge Scheduling:

```yaml
EnableScheduledExecution: "ENABLED"  # or "DISABLED"
PatchingSchedule: "cron(0 2 ? * SUN *)"  # Every Sunday 2 AM UTC
DefaultPatchGroup: "prod-servers"
```

SNS Notifications:

```yaml
NotificationEmail: "ops-team@company.com"  # or "" to disable
```

Custom SSM Documents (always on):

```yaml
WindowsPrePatchDocument: "WindowsPrePatch"
WindowsPatchDocument: "WindowsPatch"
WindowsPostPatchDocument: "WindowsPostPatch"
LinuxPrePatchDocument: "LinuxPrePatch" 
LinuxPatchDocument: "LinuxPatch"
LinuxPostPatchDocument: "LinuxPostPatch"
```

## Updated Files Summary

### ✅ Parameter Files (removed approval, added notifications & custom docs)

- `cloudformation/params/dev-hub.json`
- `cloudformation/params/stage-hub.json`
- `cloudformation/params/prod-hub.json`

### ✅ Example Input Files (converted from waves to accountWaves format)

- `examples/run-inputs/canary-small.json`
- `examples/run-inputs/windows-only-multi-region.json`
- `examples/run-inputs/linux-by-tags.json`
- `examples/run-inputs/multi-wave-staggered.json`
- `examples/run-inputs/scan-no-reboot.json`

### ✅ New Example Created

- `examples/custom-inputs/custom-ssm-documents.json` - Custom document example

## Testing Migration

### 1. Deploy Development Environment

```bash
git checkout feature/ec2-patching-simple-version
.github/workflows/cfn-deploy.yml  # Uses updated dev-hub.json
```

### 2. Test a Standard Scenario

```bash
gh workflow run patch-canary.yml \
  --field scenario=canary-small \
  --field state_machine_arn=<YOUR_ARN> \
  --field aws_region=us-east-1
```

### 3. Test Custom Documents

```bash
gh workflow run patch-canary.yml \
  --field scenario=custom-ssm-documents \
  --field state_machine_arn=<YOUR_ARN> \
  --field aws_region=us-east-1
```

### 4. Validate Notifications

- Deploy with `NotificationEmail` set
- Trigger execution and verify SNS notifications

## Rollback Plan

If issues occur, you can:

1. Revert notifications: set `NotificationEmail=""`
2. Use older input files temporarily while migrating
3. Disable scheduling: set `EnableScheduledExecution=DISABLED`

## Environment-Specific Configurations

### Development

- Scheduling: Disabled (manual execution only)
- Notifications: Disabled or dev team email  
- Custom Documents: Enabled (target small subsets)

### Staging

- Scheduling: Disabled (controlled testing)
- Notifications: Enabled (devops team)
- Custom Documents: Enabled (test your custom docs)

### Production

- Scheduling: Enabled (Sunday 2 AM UTC)
- Notifications: Enabled (ops team)
- Custom Documents: Enabled (use your specialized documents)

All parameter files have appropriate defaults for each environment.
