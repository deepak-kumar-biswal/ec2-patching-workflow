<div align="center">
  <img src="https://img.shields.io/badge/🔧-EC2%20Patching%20Platform-blue?style=for-the-badge&logoColor=white" alt="EC2 Patching"/>
  <img src="https://img.shields.io/badge/🏢-Enterprise%20Scale-orange?style=for-the-badge" alt="Enterprise"/>
  <img src="https://img.shields.io/badge/⚡-Production%20Ready-green?style=for-the-badge" alt="Production Ready"/>
</div>

<div align="center">
  <h1>🔧 Enterprise EC2 Multi-Account Patching Platform</h1>
  <p><strong>Production-grade EC2 patching orchestration for 1000+ AWS accounts</strong></p>
</div>

<div align="center">

[![Hub Deploy](https://github.com/your-org/ec2-patching-workflow/workflows/Hub%20Deploy/badge.svg)](https://github.com/your-org/ec2-patching-workflow/actions)
[![Spoke Deploy](https://github.com/your-org/ec2-patching-workflow/workflows/Spoke%20Deploy/badge.svg)](https://github.com/your-org/ec2-patching-workflow/actions)
[![Security Scan](https://github.com/your-org/ec2-patching-workflow/workflows/Security%20Scan/badge.svg)](https://github.com/your-org/ec2-patching-workflow/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

</div>

## 🏆 Enterprise-Grade EC2 Patching Orchestration

This platform deploys a **production-grade** EC2 patching orchestrator using hub-and-spoke architecture for **1000+ AWS accounts** with automated patching workflows, manual approval gates, intelligent Bedrock analysis, and comprehensive monitoring.

## 📋 Table of Contents

- [Architecture Overview](#architecture-overview)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Security Services](#security-services)
- [API Reference](#api-reference)
- [Monitoring](#monitoring)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [Support](#support)

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        HUB ACCOUNT                              │
│                  (Orchestration Control Plane)                 │
│  ┌─────────────────┐  ┌───────────────────┐  ┌───────────────┐ │
│  │   EventBridge   │  │ Step Functions    │  │   Lambda      │ │
│  │   (Scheduler)   │◄─┤   Orchestrator    │◄─┤   Processors  │ │
│  │                 │  │                   │  │               │ │
│  └─────────────────┘  └───────────────────┘  └───────────────┘ │
│           │                      │                      │       │
│           │             ┌────────▼────────┐            │       │
│           │             │   Bedrock AI    │            │       │
│           │             │   Analysis      │            │       │
│           │             └─────────────────┘            │       │
│           │                                            │       │
│  ┌────────▼────────┐  ┌─────────────────┐  ┌──────────▼──────┐ │
│  │   CloudWatch    │  │     SNS/SQS     │  │   DynamoDB      │ │
│  │   Dashboard     │  │   Notifications │  │   State Store   │ │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘ │
└─────────────────────────────────┬───────────────────────────────┘
                                  │ Cross-Account AssumeRole
                                  │
          ┌───────────────────────┼───────────────────────┐
          │                       │                       │
┌─────────▼─────────┐    ┌────────▼────────┐    ┌────────▼────────┐
│  SPOKE ACCOUNT 1  │    │  SPOKE ACCOUNT 2 │    │ SPOKE ACCOUNT N │
│                   │    │                  │    │                 │
│ ┌───────────────┐ │    │ ┌──────────────┐ │    │ ┌─────────────┐ │
│ │  Cross-Account│ │    │ │Cross-Account │ │    │ │Cross-Account│ │
│ │  Exec Role    │ │    │ │ Exec Role    │ │    │ │ Exec Role   │ │
│ └───────────────┘ │    │ └──────────────┘ │    │ └─────────────┘ │
│ ┌───────────────┐ │    │ ┌──────────────┐ │    │ ┌─────────────┐ │
│ │   EC2         │ │    │ │    EC2       │ │    │ │    EC2      │ │
│ │   Instances   │ │    │ │  Instances   │ │    │ │  Instances  │ │
│ │   (Tagged)    │ │    │ │  (Tagged)    │ │    │ │  (Tagged)   │ │
│ └───────────────┘ │    │ └──────────────┘ │    │ └─────────────┘ │
└───────────────────┘    └──────────────────┘    └─────────────────┘
```

### Key Components

- **🎯 Hub Account**: Centralized orchestration with Step Functions workflow
- **🔄 Spoke Accounts**: Target accounts with cross-account execution roles
- **📅 Wave Management**: Account grouping with scheduled maintenance windows
- **🤖 AI Analysis**: Bedrock-powered patch impact assessment
- **✅ Approval Gates**: Manual approval workflow with SNS notifications
- **📊 Monitoring**: Real-time dashboards and alerting

## 🚀 Quick Start

### Prerequisites

- Terraform >= 1.5
- AWS CLI configured
- OIDC-enabled GitHub roles (for CI/CD)
- SSM Agent on target EC2 instances
- Instances tagged with `PatchGroup=default`

### 1. Deploy Hub Account

```bash
cd terraform/hub
terraform init

terraform apply \
  -var='region=us-east-1' \
  -var='orchestrator_account_id=111111111111' \
  -var='name_prefix=ec2patch' \
  -var='bedrock_agent_id=YOUR_AGENT_ID' \
  -var='bedrock_agent_alias_id=YOUR_ALIAS_ID' \
  -var='wave_rules=[
    {
      name="wave1-critical",
      schedule_expression="cron(0 3 ? * SAT *)",
      accounts=["222222222222","333333333333"],
      regions=["us-east-1"]
    },
    {
      name="wave2-standard", 
      schedule_expression="cron(30 3 ? * SAT *)",
      accounts=["444444444444","555555555555"],
      regions=["us-east-1"]
    }
  ]'
```

### 2. Deploy Spoke Accounts

```bash
cd terraform/spoke
terraform init

# Repeat for each target account
terraform apply \
  -var='region=us-east-1' \
  -var='orchestrator_account_id=111111111111'
```

### 3. Verify Deployment

```bash
# Check Step Functions
aws stepfunctions list-state-machines --query 'stateMachines[?contains(name,`ec2patch`)]'

# Check EventBridge rules
aws events list-rules --name-prefix ec2patch

# Test cross-account access
aws sts assume-role \
  --role-arn arn:aws:iam::SPOKE_ACCOUNT:role/PatchExecRole \
  --role-session-name test-session
```

## ⚙️ Configuration

### Hub Account Variables

| Variable | Type | Description | Example |
|----------|------|-------------|---------|
| `region` | string | AWS region for deployment | `us-east-1` |
| `orchestrator_account_id` | string | Hub account ID | `111111111111` |
| `name_prefix` | string | Resource naming prefix | `ec2patch` |
| `bedrock_agent_id` | string | Bedrock agent identifier | `AGENT123` |
| `bedrock_agent_alias_id` | string | Bedrock agent alias | `ALIAS123` |
| `sns_email_subscriptions` | list(string) | Email addresses for notifications | `["ops@company.com"]` |
| `wave_pause_seconds` | number | Delay between waves | `300` |
| `abort_on_issues` | bool | Stop on detected issues | `true` |

### Wave Configuration

```hcl
variable "wave_rules" {
  description = "Patching wave configuration"
  type = list(object({
    name                = string
    schedule_expression = string  # EventBridge cron
    accounts           = list(string)
    regions            = list(string)
  }))
  
  default = [
    {
      name                = "critical-systems"
      schedule_expression = "cron(0 2 ? * SUN *)"  # Sunday 2 AM
      accounts           = ["111111111111", "222222222222"]
      regions            = ["us-east-1", "us-west-2"]
    },
    {
      name                = "development"
      schedule_expression = "cron(0 3 ? * SUN *)"  # Sunday 3 AM
      accounts           = ["333333333333", "444444444444"]
      regions            = ["us-east-1"]
    }
  ]
}
```

### Spoke Account Variables

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| `region` | string | Region for spoke resources | `us-east-1` |
| `orchestrator_account_id` | string | Hub account ID | - |
| `role_name` | string | Cross-account role name | `PatchExecRole` |

### Instance Tagging Requirements

```bash
# Required tags for EC2 instances
PatchGroup=default           # Patch group identifier
Environment=production       # Environment classification
MaintenanceWindow=standard   # Maintenance window type
CriticalityLevel=high       # Business criticality
```

## 🛡️ Security Services

### Supported AWS Services
- ✅ **Systems Manager** - Patch orchestration and compliance
- ✅ **EventBridge** - Scheduled maintenance windows
- ✅ **Step Functions** - Workflow orchestration
- ✅ **Lambda** - Custom processing logic
- ✅ **Bedrock AI** - Intelligent patch analysis
- ✅ **SNS/SQS** - Notification and queueing
- ✅ **CloudWatch** - Monitoring and alerting
- ✅ **DynamoDB** - State management
- ✅ **S3** - Artifact storage
- ✅ **IAM** - Cross-account security

### Cross-Account Security Model

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::HUB_ACCOUNT:role/PatchOrchestratorRole"
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": {
          "sts:ExternalId": "unique-external-id"
        }
      }
    }
  ]
}
```

## API Reference

### Step Functions API

**Start Execution**
```bash
aws stepfunctions start-execution \
  --state-machine-arn arn:aws:states:region:account:stateMachine:ec2patch-orchestrator \
  --name "manual-patch-$(date +%s)" \
  --input '{
    "waveId": "wave1-critical",
    "dryRun": false,
    "accounts": ["111111111111"],
    "regions": ["us-east-1"],
    "tagFilters": {
      "PatchGroup": "default"
    }
  }'
```

**Get Execution Status**
```bash
aws stepfunctions describe-execution \
  --execution-arn arn:aws:states:region:account:execution:ec2patch-orchestrator:execution-name
```

### Lambda Functions

| Function | Purpose | Timeout |
|----------|---------|---------|
| `PreEC2Inventory` | Discover patchable instances | 5 min |
| `SendApprovalRequest` | Initiate approval workflow | 1 min |
| `ApprovalCallback` | Process approval responses | 1 min |
| `PollSsmCommand` | Monitor patch execution | 10 min |
| `PostEC2Verify` | Validate patch success | 5 min |
| `AnalyzeWithBedrock` | AI-powered analysis | 3 min |

## 📈 Monitoring

### CloudWatch Dashboard

Key metrics monitored:

- **Patch Success Rate**: % of successful patches per wave
- **Instance Availability**: Pre/post-patch instance health
- **Execution Duration**: Time taken per patching wave
- **Error Rates**: Failed patches and root causes
- **Compliance Drift**: Instances falling behind patch levels

### Alerting Configuration

```yaml
# CloudWatch Alarms
PatchFailureRate:
  MetricName: PatchFailures
  Threshold: 5
  ComparisonOperator: GreaterThanThreshold
  
InstanceDowntime:
  MetricName: InstancesUnhealthy
  Threshold: 2
  ComparisonOperator: GreaterThanThreshold
  
ApprovalTimeout:
  MetricName: PendingApprovals
  Threshold: 60  # minutes
  ComparisonOperator: GreaterThanThreshold
```

### Log Analysis

```bash
# Query CloudWatch Logs
aws logs filter-log-events \
  --log-group-name /aws/lambda/ec2patch-orchestrator \
  --filter-pattern "ERROR" \
  --start-time $(date -d "1 hour ago" +%s)000

# Check Step Functions execution logs
aws stepfunctions get-execution-history \
  --execution-arn arn:aws:states:region:account:execution:name \
  --max-items 100
```

## 🔧 Troubleshooting

### Common Issues

#### 1. Cross-Account Role Assumption Failed
```bash
# Verify role exists and trust policy
aws iam get-role --role-name PatchExecRole

# Test assume role
aws sts assume-role \
  --role-arn arn:aws:iam::SPOKE_ACCOUNT:role/PatchExecRole \
  --role-session-name test
```

**Solution**: Ensure External ID matches and trust policy is correct.

#### 2. SSM Command Failed
```bash
# Check SSM agent status
aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=i-1234567890abcdef0"

# View command execution details
aws ssm get-command-invocation \
  --command-id command-id \
  --instance-id i-1234567890abcdef0
```

**Solution**: Verify SSM agent is running and instance has proper IAM role.

#### 3. Bedrock Analysis Timeout
```bash
# Check Bedrock agent status
aws bedrock-agent get-agent \
  --agent-id YOUR_AGENT_ID

# View Lambda logs
aws logs tail /aws/lambda/ec2patch-bedrock-analyzer --follow
```

**Solution**: Increase Lambda timeout or optimize Bedrock query.

#### 4. EventBridge Rule Not Triggering
```bash
# List EventBridge rules
aws events list-rules --name-prefix ec2patch

# Check rule targets
aws events list-targets-by-rule --rule ec2patch-wave1-critical
```

**Solution**: Verify cron expression and rule state.

### Performance Optimization

- **Parallel Processing**: Configure concurrent executions
- **Batch Size**: Optimize instance grouping per wave  
- **Timeout Values**: Adjust based on patch complexity
- **Region Strategy**: Minimize cross-region calls

## 🤝 Contributing

### Development Setup

1. **Clone Repository**
```bash
git clone <repository-url>
cd ec2-patching-workflow
```

2. **Install Dependencies**
```bash
pip install -r requirements-dev.txt
terraform --version  # Verify >= 1.5
```

3. **Run Tests**
```bash
python -m pytest tests/
terraform -chdir=terraform/hub validate
terraform -chdir=terraform/spoke validate
```

4. **Local Development**
```bash
# Plan changes
terraform -chdir=terraform/hub plan -var-file=../../examples/hub.auto.tfvars.example

# Apply to development environment
terraform -chdir=terraform/hub apply -var="name_prefix=dev-ec2patch"
```

### Code Standards

- Follow Terraform best practices and naming conventions
- Use consistent Python coding standards (PEP 8)
- Include comprehensive error handling and logging
- Write unit tests for all Lambda functions
- Document all configuration parameters

### Pull Request Guidelines

- Create feature branches from `main`
- Include tests for new functionality
- Update documentation as needed
- Ensure CI/CD pipeline passes
- Request review from code owners

## 📞 Support

### Documentation
- [Deployment Guide](docs/deployment-guide.md)
- [API Reference](docs/api.md)
- [Troubleshooting Guide](docs/troubleshooting-guide.md)

### Getting Help
- **Issues**: Create GitHub issue with detailed reproduction steps
- **Questions**: Check existing documentation and issues first
- **Security**: Report vulnerabilities through private channels

### Maintenance Schedule
- **Patch Testing**: First Sunday of each month
- **Documentation Updates**: Quarterly
- **Dependency Updates**: Monthly automated PRs
- **Security Reviews**: Bi-annual comprehensive audits

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

**Built with ❤️ for Enterprise-Scale EC2 Patch Management**

For comprehensive technical details, please refer to the documentation in the [docs/](docs/) directory.
- An **SNS email** includes two links (`Approve`/`Reject`) pointing to the API Gateway `/callback` route.
- Approval triggers the **Step Functions** state machine to proceed.

## Start a Run Manually
You can start execution with a JSON `input` similar to what EventBridge sends:
```json
{
  "accountWaves": [
    { "accounts": ["222222222222","333333333333"], "regions": ["us-east-1"] }
  ],
  "ec2": { "tagKey": "PatchGroup", "tagValue": "default" },
  "snsTopicArn": "arn:aws:sns:us-east-1:111111111111:ec2patch-PatchAlerts",
  "bedrock": { "agentId": "AGENT_ID", "agentAliasId": "ALIAS_ID" },
  "wavePauseSeconds": 0,
  "abortOnIssues": true
}
```

## CloudWatch Dashboard
A dashboard named `${name_prefix}-dashboard` is created with **Step Functions** and **Lambda** error metrics.

## Security Notes
- `PatchExecRole` is limited to SSM/EC2 read + required operations.
- Step Functions assumes `PatchExecRole` in each target account.
