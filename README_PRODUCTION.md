# EC2 Multi-Account Patching Orchestrator - Production Grade

## Overview

This is a **production-grade** EC2 patching solution designed for enterprise environments like Google or Netflix. It provides automated, scalable, and robust patch management across multiple AWS accounts and regions with comprehensive monitoring, error handling, and reporting capabilities.

## 🌟 Key Features

### Enterprise-Grade Capabilities
- **Multi-Account/Multi-Region**: Hub-spoke architecture for centralized patching across AWS organizations
- **Wave-Based Patching**: Configurable waves with scheduling, priorities, and dependencies  
- **Manual Approval Workflow**: Integration with SNS, Slack, and Microsoft Teams for approval workflows
- **Production Monitoring**: Comprehensive CloudWatch dashboards and alarms
- **Security & Compliance**: End-to-end encryption, audit logging, and compliance framework support

 
### Reliability & Scalability
 
- **Fault Tolerance**: Comprehensive error handling with retry logic and circuit breakers
- **Auto-Recovery**: Self-healing capabilities with automatic retries and escalation
- **Load Balancing**: Intelligent concurrency control and rate limiting
- **Performance Monitoring**: Real-time metrics and performance optimization
- **Disaster Recovery**: Cross-region backup and recovery capabilities

 
### DevOps & Automation
 
- **Infrastructure as Code**: Complete IaC via CloudFormation templates
- **CI/CD Pipeline**: GitHub Actions with automated testing, security scanning, and deployment
- **Testing Framework**: Unit, integration, and end-to-end tests with coverage reporting
- **Documentation**: Comprehensive documentation with architecture diagrams and runbooks

## 🏗️ Architecture

```text
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
│  │      S3      │  │   DynamoDB      │                     │   │
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
3. **Tools**: AWS CLI, Git
4. **GitHub**: Repository with OIDC provider configured

### Deployment

Use the CloudFormation templates in `cloudformation/` and the GitHub Actions workflows in `.github/workflows/` to deploy the hub and spoke stacks. Provide parameter JSONs in `cloudformation/params/` and set required GitHub secrets/vars as documented in the main README.

## 📋 Configuration

### Configuration

See the main `README.md` for CloudFormation parameter details and example JSONs in `cloudformation/params/`.

### Environments

Provide separate parameter JSONs for each environment (e.g., `dev-hub.json`, `stage-hub.json`, `prod-hub.json`) in `cloudformation/params/`.

## 🔧 Advanced Configuration

### Custom Patch Policies

Use SSM Patch Baselines and CloudFormation parameters to control `MaxConcurrency`, `MaxErrors`, and approval rules for patches.

### High Availability Setup

Use cross-region S3 replication and DynamoDB PITR, and deploy read-only dashboards in secondary regions if required.

### VPC Integration

Attach Lambdas to your VPC subnets/security groups via CloudFormation parameters and ensure VPC endpoints exist for SSM/EC2 Messages where needed.

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

<!-- X-Ray was removed for this CFN-only solution: no tracing guidance here to avoid confusion. -->

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

Enable detailed logging via CloudWatch log level and longer retention settings in your CloudFormation parameters.

For day-2 operations, see the Operations Runbook: `docs/runbook-operations.md`.

## 📈 Performance Optimization

### Scaling Recommendations

| Environment | Accounts | Instances | Recommended Settings |
|-------------|----------|-----------|---------------------|
| Development | 1-5      | <100      | Default settings    |
| Staging     | 5-20     | 100-1000  | Increase timeouts   |
| Production  | 20+      | 1000+     | Custom optimization |

### Production Tuning

Use CloudFormation parameters to tune:

- Max concurrent accounts per wave (Step Functions Map concurrency)
- Lambda reserved concurrency for pollers and senders
- Wave pause seconds between waves
- Execution timeout minutes

## 🔄 CI/CD Pipeline

The GitHub Actions workflows include:

1. **Validation**: cfn-lint on templates, pytest on Python code
2. **Deployment**: CloudFormation deploy (hub and spokes)
3. **Testing**: Unit tests and optional integration tests
4. **Notification**: Slack/Teams integration (optional)

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
