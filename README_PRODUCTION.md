# EC2 Multi-Account Patching Orchestrator - Production Grade

## Overview

This is a **production-grade** EC2 patching solution designed for enterprise environments like Google or Netflix. It provides automated, scalable, and robust patch management across multiple AWS accounts and regions with comprehensive monitoring, error handling, and reporting capabilities.

## 🌟 Key Features

### Enterprise-Grade Capabilities
- **Multi-Account/Multi-Region**: Hub-spoke architecture for centralized patching across AWS organizations
- **Wave-Based Patching**: Configurable waves with scheduling, priorities, and dependencies  
- **Manual Approval Workflow**: Integration with SNS, Slack, and Microsoft Teams for approval workflows
- **AI-Powered Analysis**: Amazon Bedrock integration for intelligent issue analysis and recommendations
- **Production Monitoring**: Comprehensive CloudWatch dashboards, alarms, and X-Ray tracing
- **Security & Compliance**: End-to-end encryption, audit logging, and compliance framework support

### Reliability & Scalability
- **Fault Tolerance**: Comprehensive error handling with retry logic and circuit breakers
- **Auto-Recovery**: Self-healing capabilities with automatic retries and escalation
- **Load Balancing**: Intelligent concurrency control and rate limiting
- **Performance Monitoring**: Real-time metrics and performance optimization
- **Disaster Recovery**: Cross-region backup and recovery capabilities

### DevOps & Automation
- **Infrastructure as Code**: Complete Terraform configuration with best practices
- **CI/CD Pipeline**: GitHub Actions with automated testing, security scanning, and deployment
- **Testing Framework**: Unit, integration, and end-to-end tests with coverage reporting
- **Documentation**: Comprehensive documentation with architecture diagrams and runbooks

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Hub Account (Orchestrator)              │
├─────────────────────────────────────────────────────────────────┤
│  ┌──────────────┐  ┌─────────────────┐  ┌──────────────────┐   │
│  │  EventBridge │  │ Step Functions  │  │   API Gateway    │   │
│  │   Schedule   │──│   Orchestrator  │  │   (Approval)     │   │
│  └──────────────┘  └─────────────────┘  └──────────────────┘   │
│          │                  │                       │           │
│          └──────────────────┼───────────────────────┘           │
│                             │                                   │
│  ┌──────────────┐  ┌─────────────────┐  ┌──────────────────┐   │
│  │   Lambda     │  │   CloudWatch    │  │      SNS         │   │
│  │ Functions    │  │   Monitoring    │  │   Notifications  │   │
│  └──────────────┘  └─────────────────┘  └──────────────────┘   │
│          │                  │                       │           │
│  ┌──────────────┐  ┌─────────────────┐  ┌──────────────────┐   │
│  │      S3      │  │   DynamoDB      │  │   Bedrock AI     │   │
│  │  (Snapshots) │  │   (State)       │  │   (Analysis)     │   │
│  └──────────────┘  └─────────────────┘  └──────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                                │
                 ┌──────────────┼──────────────┐
                 │              │              │
    ┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
    │  Spoke Account  │ │  Spoke Account  │ │  Spoke Account  │
    │      (Dev)      │ │   (Staging)     │ │ (Production)    │
    ├─────────────────┤ ├─────────────────┤ ├─────────────────┤
    │ PatchExecRole   │ │ PatchExecRole   │ │ PatchExecRole   │
    │ EC2 Instances   │ │ EC2 Instances   │ │ EC2 Instances   │
    │ SSM Agent       │ │ SSM Agent       │ │ SSM Agent       │
    └─────────────────┘ └─────────────────┘ └─────────────────┘
```

## 🚀 Quick Start

### Prerequisites

1. **AWS Accounts**: Hub account + spoke accounts for patching
2. **Permissions**: Admin access to deploy IAM roles and resources
3. **Tools**: Terraform >= 1.5, AWS CLI, Git
4. **Bedrock**: Amazon Bedrock agent configured for AI analysis
5. **GitHub**: Repository with OIDC provider configured

### 1. Hub Account Deployment

```bash
# Clone repository
git clone https://github.com/deepak-kumar-biswal/aws-platform-audit.git
cd aws-platform-audit/ec2/ec2-patching-workflow/terraform/hub

# Configure variables
cp ../../examples/hub.auto.tfvars.example terraform.tfvars

# Edit terraform.tfvars with your values
vim terraform.tfvars

# Deploy infrastructure
terraform init
terraform plan
terraform apply
```

### 2. Spoke Account Deployment (Repeat for each target account)

```bash
cd ../spoke

# Configure variables
vim terraform.tfvars

# Deploy cross-account role
terraform init
terraform plan  
terraform apply
```

### 3. Configure GitHub Actions (Optional)

```bash
# Set up GitHub secrets and variables
gh secret set PRODUCTION_ROLE_ARN --body "arn:aws:iam::111111111111:role/GitHubActionsRole"
gh secret set BEDROCK_AGENT_ID --body "AGENT_ID_HERE"
gh variable set PRODUCTION_ACCOUNT_ID --body "111111111111"
```

## 📋 Configuration

### Hub Account Variables (`terraform.tfvars`)

```hcl
# Basic Configuration
region                  = "us-east-1"
orchestrator_account_id = "111111111111"
name_prefix            = "ec2patch"
environment            = "production"

# Wave Configuration
wave_rules = [
  {
    name                = "development-wave"
    schedule_expression = "cron(0 2 ? * SUN *)"  # Sunday 2 AM
    accounts           = ["222222222222"]
    regions            = ["us-east-1"]
    priority           = 1
    timeout_minutes    = 120
  },
  {
    name                = "staging-wave"  
    schedule_expression = "cron(0 3 ? * SUN *)"  # Sunday 3 AM
    accounts           = ["333333333333"]
    regions            = ["us-east-1", "us-west-2"]
    priority           = 2
    timeout_minutes    = 180
  },
  {
    name                = "production-wave"
    schedule_expression = "cron(0 4 ? * SUN *)"  # Sunday 4 AM
    accounts           = ["444444444444", "555555555555"]
    regions            = ["us-east-1", "us-west-2", "eu-west-1"]
    priority           = 3
    timeout_minutes    = 240
    parallel_execution = false
  }
]

# Notifications
sns_email_subscriptions = ["devops@company.com", "oncall@company.com"]
slack_webhook_url      = "https://hooks.slack.com/services/YOUR/WEBHOOK/URL"

# Bedrock AI Configuration
bedrock_agent_id       = "AGENT_ID_HERE"
bedrock_agent_alias_id = "ALIAS_ID_HERE"

# Security & Compliance
data_classification    = "Internal"
compliance_framework   = "SOC2"
enable_cloudtrail     = true

# Resource Tagging
owner          = "devops-team@company.com"
cost_center    = "IT-OPERATIONS"
business_unit  = "INFRASTRUCTURE"
```

### Environment-Specific Configuration

Create separate `.tfvars` files for each environment:

- `dev.tfvars` - Development environment
- `staging.tfvars` - Staging environment  
- `prod.tfvars` - Production environment

## 🔧 Advanced Configuration

### Custom Patch Policies

```hcl
# Custom patch configuration
patch_classification_filter = ["Critical", "Important"]
reboot_option              = "RebootIfNeeded"
max_concurrency_percentage = 15  # Conservative for production
max_error_percentage       = 2   # Low tolerance for failures
```

### High Availability Setup

```hcl
# Cross-region disaster recovery
enable_cross_region_backup = true
backup_region             = "us-west-2"
rpo_hours                = 4   # Recovery Point Objective
rto_hours                = 2   # Recovery Time Objective
```

### VPC Integration

```hcl
# Deploy Lambda functions in VPC
vpc_id                = "vpc-12345678"
subnet_ids           = ["subnet-12345", "subnet-67890"]
enable_vpc_endpoints = true
```

## 📊 Monitoring & Observability

### CloudWatch Dashboard

The solution automatically creates comprehensive dashboards:

- **Executive Summary**: High-level metrics and KPIs
- **Execution Monitoring**: Step Functions execution status and duration
- **Error Analysis**: Lambda errors, throttles, and failure rates
- **Resource Utilization**: DynamoDB, S3, and Lambda performance
- **Security Metrics**: Failed authentications and policy violations

Access via: AWS Console → CloudWatch → Dashboards → `{name_prefix}-production-dashboard`

### Alarms & Alerting

Automated alarms for:
- Step Functions execution failures
- High Lambda error rates  
- Long execution durations
- Security violations
- Resource capacity issues

### X-Ray Tracing

Distributed tracing enabled for:
- End-to-end request flow
- Performance bottleneck identification
- Error root cause analysis
- Cross-service dependency mapping

## 🔒 Security

### Encryption

- **At Rest**: KMS encryption for S3, DynamoDB, SNS
- **In Transit**: TLS 1.2+ for all communications
- **Key Management**: Customer-managed KMS keys with rotation

### Access Control

- **IAM Roles**: Least privilege principle
- **Cross-Account**: Secure assume role with conditions
- **API Security**: API Gateway with authentication
- **Network**: VPC endpoints for secure communication

### Audit & Compliance

- **CloudTrail**: Full API audit logging
- **Data Classification**: Automatic tagging
- **Retention Policies**: Configurable data lifecycle
- **Compliance**: SOC2, ISO27001, NIST, PCI-DSS support

## 🧪 Testing

### Running Tests Locally

```bash
# Install dependencies
pip install -r tests/requirements.txt

# Run unit tests
pytest tests/unit/ -v

# Run integration tests
pytest tests/integration/ -v --aws-profile=your-profile

# Run load tests
pytest tests/load/ -v --duration=300
```

### Test Coverage

- **Unit Tests**: 95%+ code coverage for Lambda functions
- **Integration Tests**: End-to-end workflow validation
- **Load Tests**: 1000+ concurrent account processing
- **Security Tests**: IAM policy validation and penetration testing

## 🚨 Troubleshooting

### Common Issues

1. **Role Assumption Failures**
   ```bash
   # Check spoke account role configuration
   aws sts assume-role --role-arn arn:aws:iam::ACCOUNT:role/PatchExecRole --role-session-name test
   ```

2. **Step Functions Timeout**
   ```bash
   # Check execution logs in CloudWatch
   aws logs filter-log-events --log-group-name /aws/stepfunctions/{sfn_name}
   ```

3. **Lambda Function Errors**
   ```bash
   # Check function logs
   aws logs tail /aws/lambda/{function_name} --follow
   ```

### Debug Mode

Enable detailed logging:
```hcl
enable_detailed_monitoring = true
log_retention_days         = 14
xray_sampling_rate        = 1.0  # 100% sampling for debugging
```

## 📈 Performance Optimization

### Scaling Recommendations

| Environment | Accounts | Instances | Recommended Settings |
|-------------|----------|-----------|---------------------|
| Development | 1-5      | <100      | Default settings    |
| Staging     | 5-20     | 100-1000  | Increase timeouts   |
| Production  | 20+      | 1000+     | Custom optimization |

### Production Tuning

```hcl
# Production optimizations
max_concurrent_executions    = 10
lambda_reserved_concurrency  = 50
wave_pause_seconds          = 600  # 10 minutes between waves
execution_timeout_minutes   = 480  # 8 hours total
```

## 🔄 CI/CD Pipeline

The GitHub Actions workflow includes:

1. **Validation**: Terraform format, validate, and plan
2. **Security Scanning**: Checkov, TFLint, TFSec analysis
3. **Cost Analysis**: Infracost estimation
4. **Deployment**: Automated infrastructure deployment
5. **Testing**: Integration and smoke tests
6. **Notification**: Slack/Teams integration for status updates

### Pipeline Environments

- **Development**: Auto-deploy on feature branch merge
- **Staging**: Auto-deploy on main branch  
- **Production**: Manual approval required

## 🆘 Support & Maintenance

### Monitoring Checklist

- [ ] CloudWatch alarms active
- [ ] Dashboard metrics updating
- [ ] SNS notifications working
- [ ] Audit logs flowing to CloudTrail
- [ ] Backup/restore procedures tested

### Regular Maintenance

- **Weekly**: Review execution reports and metrics
- **Monthly**: Update patch baselines and test execution
- **Quarterly**: Disaster recovery testing
- **Annually**: Security audit and compliance review

## 📚 Additional Resources

- [AWS Systems Manager Patch Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-patch.html)
- [Step Functions Best Practices](https://docs.aws.amazon.com/step-functions/latest/dg/best-practices.html)
- [Multi-Account Strategy](https://docs.aws.amazon.com/whitepapers/latest/organizing-your-aws-environment/organizing-your-aws-environment.html)
- [Security Best Practices](https://docs.aws.amazon.com/security/latest/userguide/best-practices.html)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

**Note**: This solution is designed for enterprise production environments. Ensure you understand the cost implications and have proper AWS support contracts in place before deployment.
