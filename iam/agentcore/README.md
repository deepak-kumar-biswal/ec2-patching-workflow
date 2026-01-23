# AWS AgentCore IAM Role Architecture

## Overview

This directory contains modular IAM policies and roles for AWS AgentCore multi-agentic platform deployment. The design follows AWS security best practices:

- **Least Privilege**: Only required permissions are granted
- **Condition-based Access**: Resource and tag-based conditions
- **Modular Design**: Policies can be mixed and matched per application
- **Cross-Account Ready**: Supports hub-spoke architecture

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                    AgentCore IAM Architecture                        │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │                 Trust Policies (Assume Role)                  │   │
│  │  • Bedrock Service Principal                                  │   │
│  │  • Lambda Service Principal                                   │   │
│  │  • Cross-Account Principals (optional)                        │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                              │                                       │
│                              ▼                                       │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │                    Base Role (Required)                       │   │
│  │  • AgentCoreBaseRole                                          │   │
│  │  • Core Bedrock Agent permissions                             │   │
│  │  • CloudWatch Logging                                         │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                              │                                       │
│              ┌───────────────┼───────────────┐                      │
│              ▼               ▼               ▼                      │
│  ┌────────────────┐ ┌────────────────┐ ┌────────────────┐          │
│  │ Knowledge Base │ │ Action Groups  │ │ Model Access   │          │
│  │    Policy      │ │    Policy      │ │    Policy      │          │
│  └────────────────┘ └────────────────┘ └────────────────┘          │
│              │               │               │                      │
│              ▼               ▼               ▼                      │
│  ┌────────────────┐ ┌────────────────┐ ┌────────────────┐          │
│  │   S3 Access    │ │ Lambda Invoke  │ │ Secrets Mgr    │          │
│  │    Policy      │ │    Policy      │ │    Policy      │          │
│  └────────────────┘ └────────────────┘ └────────────────┘          │
│              │               │               │                      │
│              ▼               ▼               ▼                      │
│  ┌────────────────┐ ┌────────────────┐ ┌────────────────┐          │
│  │  OpenSearch/   │ │  Guardrails    │ │  Multi-Agent   │          │
│  │  Vector Store  │ │    Policy      │ │  Collaboration │          │
│  └────────────────┘ └────────────────┘ └────────────────┘          │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

## Policy Files

| File | Description | Required |
|------|-------------|----------|
| `trust-policy.json` | Service trust relationships | Yes |
| `base-policy.json` | Core agent permissions | Yes |
| `knowledge-base-policy.json` | RAG/Knowledge base access | Optional |
| `action-groups-policy.json` | Lambda action group invocation | Optional |
| `model-access-policy.json` | Foundation model invocation | Yes |
| `s3-data-policy.json` | S3 bucket access for data | Optional |
| `secrets-manager-policy.json` | API keys and credentials | Optional |
| `opensearch-policy.json` | Vector store access | Optional |
| `guardrails-policy.json` | Content filtering controls | Optional |
| `multi-agent-policy.json` | Agent collaboration permissions | Optional |
| `cloudwatch-policy.json` | Logging and monitoring | Yes |
| `cross-account-policy.json` | Multi-account access | Optional |

## Usage

### Single Application Deployment
```bash
# Attach base + required policies
aws iam attach-role-policy --role-name MyAgentRole --policy-arn arn:aws:iam::ACCOUNT:policy/AgentCoreBase
aws iam attach-role-policy --role-name MyAgentRole --policy-arn arn:aws:iam::ACCOUNT:policy/AgentCoreModelAccess
```

### Multi-Agent Platform Deployment
```bash
# Attach all policies for full platform
for policy in Base ModelAccess KnowledgeBase ActionGroups S3Data SecretsManager OpenSearch Guardrails MultiAgent CloudWatch; do
  aws iam attach-role-policy --role-name AgentPlatformRole --policy-arn arn:aws:iam::ACCOUNT:policy/AgentCore${policy}
done
```

## Tagging Strategy

All resources must be tagged for condition-based access:
- `AgentCore:Application` - Application identifier
- `AgentCore:Environment` - dev/staging/prod
- `AgentCore:AgentId` - Specific agent identifier
- `AgentCore:CostCenter` - For billing allocation

## Security Considerations

1. **Source ARN Conditions**: All policies use `aws:SourceArn` to prevent confused deputy
2. **Resource Boundaries**: Policies are scoped to specific resource patterns
3. **Encryption Requirements**: KMS key conditions for data encryption
4. **VPC Endpoints**: Use VPC endpoints for private connectivity
5. **Session Tags**: Support for ABAC-based access control
