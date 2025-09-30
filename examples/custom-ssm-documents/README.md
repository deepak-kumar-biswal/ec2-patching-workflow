# Custom SSM Patch Documents

This directory contains example custom SSM documents for the EC2 patching workflow. The orchestrator now uses custom documents exclusively; these examples show comprehensive and modular patterns you can adapt.

## 📁 Document Types

### Comprehensive Patch Documents

- `WindowsCustomPatch.json` - Complete Windows patching workflow with pre/post operations
- `LinuxCustomPatch.json` - Complete Linux patching workflow with pre/post operations

### Modular Documents

- `WindowsPrePatch.json` - Windows pre-patch operations (service stop, backup)
- `WindowsPostPatch.json` - Windows post-patch operations (service restart, validation)
- `LinuxPrePatch.json` - Linux pre-patch operations (service stop, backup)
- `LinuxPostPatch.json` - Linux post-patch operations (service restart, validation)

## 🚀 Deployment Steps

### 1. Create SSM Documents (optional if using hub-managed docs)

If you prefer to manage documents manually, create them like this:

```bash
# Windows comprehensive document
aws ssm create-document \
    --name "WindowsCustomPatch" \
    --document-type "Command" \
    --document-format JSON \
    --content file://WindowsCustomPatch.json

# Linux comprehensive document
aws ssm create-document \
    --name "LinuxCustomPatch" \
    --document-type "Command" \
    --document-format JSON \
    --content file://LinuxCustomPatch.json

# Or create modular documents
aws ssm create-document --name "WindowsPrePatch" --document-type "Command" --document-format JSON --content file://WindowsPrePatch.json
aws ssm create-document --name "WindowsPostPatch" --document-type "Command" --document-format JSON --content file://WindowsPostPatch.json
aws ssm create-document --name "LinuxPrePatch" --document-type "Command" --document-format JSON --content file://LinuxPrePatch.json
aws ssm create-document --name "LinuxPostPatch" --document-type "Command" --document-format JSON --content file://LinuxPostPatch.json
```

### 2. Configure Hub CloudFormation Stack

Update your hub CloudFormation parameters to set document names (custom docs are always on):

```bash
aws cloudformation update-stack \
    --stack-name ec2-patch-hub \
    --use-previous-template \
    --parameters \
        ParameterKey=WindowsPatchDocument,ParameterValue=WindowsCustomPatch \
        ParameterKey=LinuxPatchDocument,ParameterValue=LinuxCustomPatch \
        ParameterKey=WindowsPrePatchDocument,ParameterValue=WindowsPrePatch \
        ParameterKey=WindowsPostPatchDocument,ParameterValue=WindowsPostPatch \
        ParameterKey=LinuxPrePatchDocument,ParameterValue=LinuxPrePatch \
        ParameterKey=LinuxPostPatchDocument,ParameterValue=LinuxPostPatch
```

### 3. Execute with Custom Documents

```bash
aws stepfunctions start-execution \
    --state-machine-arn "arn:aws:states:us-east-1:111111111111:stateMachine:ec2patch-orchestrator" \
    --name "custom-patch-$(date +%s)" \
    --input '{
        "accountWaves": [
            {
                "name": "wave-1",
                "accounts": ["222222222222"],
                "regions": ["us-east-1"]
            }
        ],
        "ec2": {
            "tagKey": "PatchGroup",
            "tagValue": "default"
        },
        "customDocuments": {
            "windowsPrePatch": "WindowsPrePatch",
            "windowsPatch": "WindowsCustomPatch",
            "windowsPostPatch": "WindowsPostPatch",
            "linuxPrePatch": "LinuxPrePatch",
            "linuxPatch": "LinuxCustomPatch",
            "linuxPostPatch": "LinuxPostPatch"
        },
        "preCollect": {"enabled": true},
        "abortOnIssues": false
    }'
```

## ⚙️ Document Features

### Windows Features

- Pre-patch validation - Disk space, domain connectivity, service status
- Configuration backup - Registry, IIS config, system info
- Service management - Stop/start specified services
- Maintenance mode - Create maintenance pages for web servers
- Smart patching - PSWindowsUpdate module with filtering
- Post-validation - Error checking, reboot detection
- Comprehensive reporting - JSON-formatted execution reports

### Linux Features

- Pre-patch validation - Disk space, load average, package manager locks
- Configuration backup - System configs, web server configs, database configs
- Service management - Systemd service stop/start with validation
- Maintenance mode - Create maintenance files and pages
- Multi-distro support - Works with RHEL, Ubuntu, SUSE (yum, apt, zypper)
- Security filtering - Security-only updates option
- Post-validation - Service health checks, reboot detection
- Health monitoring - System load, memory, disk usage

## 📋 Customization Options

### Common Parameters

- `Operation` - "Install" or "Scan"
- `RebootOption` - "RebootIfNeeded" or "NoReboot"
- `ServiceNames` - List of services to stop/restart
- `MaintenanceMode` - Enable maintenance mode features

### Windows-Specific Parameters

- `IncludeKbs` - Specific KB articles to include
- `ExcludeKbs` - KB articles to exclude (e.g., "KB1234567,KB7654321")
- `BackupLocation` - S3 location for backups

### Linux-Specific Parameters

- `PackageIncludeFilter` - Package patterns to include
- `PackageExcludeFilter` - Package patterns to exclude (e.g., "kernel\* \*-devel")
- `SecurityUpdatesOnly` - Install only security updates
- `BackupLocation` - Local backup directory

## 🔧 Customization Guide

### Adding Custom Services

Edit the default service lists in the parameters section:

```json
"ServiceNames": {
    "default": ["httpd", "nginx", "myapp", "custom-service"]
}
```

### Adding Custom Validation

Add validation steps in the post-patch sections:

```bash
# Example: Custom application health check
if systemctl is-active --quiet myapp 2>/dev/null; then
    if curl -s http://localhost:8080/health | grep -q "OK"; then
        log 'MyApp validation: Health check passed'
    else
        log 'WARNING: MyApp health check failed'
    fi
fi
```

### Adding Custom Backup Locations

Modify backup logic to support your backup strategy:

```bash
# Example: Upload to S3
if command -v aws >/dev/null 2>&1; then
    aws s3 sync "$backup_dir" "s3://my-backup-bucket/$(hostname)/"
    log "Backup uploaded to S3"
fi
```

## 🚨 Important Notes

1. Test First - Always test custom documents in development environments
2. Service Dependencies - Ensure service stop/start order respects dependencies  
3. Timeouts - Adjust timeout values based on your environment
4. Permissions - Ensure EC2 instances have required permissions for custom operations
5. Error Handling - Documents include comprehensive error handling and logging
6. Platform Targeting - Documents automatically target correct OS platforms

## 📊 Monitoring Integration

All documents generate structured output that integrates with the orchestrator's monitoring:

- JSON reports - Structured patching reports in CloudWatch logs
- Status indicators - Clear success/failure indicators  
- Reboot detection - Automatic detection of reboot requirements
- Service validation - Health checks for critical services
- Error reporting - Detailed error messages and troubleshooting info

## 🔄 Integration with Orchestrator

These documents integrate seamlessly with the existing orchestrator:

- Cross-account execution - No IAM changes needed in documents
- Parameter passing - Orchestrator passes configuration parameters
- Output collection - All outputs stored in S3 for analysis
- Monitoring - Same polling and status tracking for custom documents
- Notifications - Failure notifications through existing SNS topics

---

For more information, see the main [deployment guide](../../docs/deployment-guide.md) and [troubleshooting guide](../../docs/troubleshooting-guide.md).
