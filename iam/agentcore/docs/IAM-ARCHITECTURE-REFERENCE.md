# AWS AgentCore IAM Architecture Reference

## Executive Summary

This document provides a comprehensive reference for the AWS AgentCore IAM role architecture designed for multi-agentic platforms. The architecture follows AWS security best practices including least privilege, defense in depth, and attribute-based access control (ABAC).

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Security Principles](#security-principles)
3. [Role Design](#role-design)
4. [Policy Breakdown](#policy-breakdown)
5. [Condition Keys Reference](#condition-keys-reference)
6. [Multi-Account Strategy](#multi-account-strategy)
7. [Tagging Strategy](#tagging-strategy)
8. [Usage Examples](#usage-examples)
9. [Troubleshooting](#troubleshooting)

---

## Architecture Overview

### Component Diagram

```
┌────────────────────────────────────────────────────────────────────────────┐
│                        AWS AgentCore Platform                               │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                     Trust Layer (Who Can Assume)                     │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                  │   │
│  │  │   Bedrock   │  │   Lambda    │  │ Cross-Acct  │                  │   │
│  │  │   Service   │  │   Service   │  │  Principals │                  │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘                  │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                        │
│                                    ▼                                        │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                     Permissions Boundary (Guard Rails)               │   │
│  │  Maximum permissions any AgentCore role can have                     │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                        │
│                                    ▼                                        │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                     Modular Policy Layer                             │   │
│  │                                                                       │   │
│  │   Required Policies              Optional Policies                   │   │
│  │   ─────────────────              ─────────────────                   │   │
│  │   ┌──────────────┐              ┌──────────────────┐                 │   │
│  │   │ Base Policy  │              │ Knowledge Base   │                 │   │
│  │   └──────────────┘              └──────────────────┘                 │   │
│  │   ┌──────────────┐              ┌──────────────────┐                 │   │
│  │   │ Model Access │              │ Action Groups    │                 │   │
│  │   └──────────────┘              └──────────────────┘                 │   │
│  │   ┌──────────────┐              ┌──────────────────┐                 │   │
│  │   │ CloudWatch   │              │ Guardrails       │                 │   │
│  │   └──────────────┘              └──────────────────┘                 │   │
│  │                                 ┌──────────────────┐                 │   │
│  │                                 │ Multi-Agent      │                 │   │
│  │                                 └──────────────────┘                 │   │
│  │                                 ┌──────────────────┐                 │   │
│  │                                 │ Cross-Account    │                 │   │
│  │                                 └──────────────────┘                 │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                        │
│                                    ▼                                        │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                     Resource Layer (What Can Be Accessed)           │   │
│  │                                                                       │   │
│  │   ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐   │   │
│  │   │ Agents  │  │   KBs   │  │ Models  │  │   S3    │  │ Secrets │   │   │
│  │   └─────────┘  └─────────┘  └─────────┘  └─────────┘  └─────────┘   │   │
│  │   ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐   │   │
│  │   │ Lambda  │  │OpenSearch│ │DynamoDB │  │  SNS   │  │  SQS    │   │   │
│  │   └─────────┘  └─────────┘  └─────────┘  └─────────┘  └─────────┘   │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└────────────────────────────────────────────────────────────────────────────┘
```

### Policy Modularity Matrix

| Application Type | Base | Model | KB | Actions | Guards | Multi-Agent | X-Acct |
|-----------------|------|-------|-----|---------|--------|-------------|--------|
| Simple Agent    | ✅   | ✅    | ❌  | ❌      | ❌     | ❌          | ❌     |
| RAG Agent       | ✅   | ✅    | ✅  | ❌      | ✅     | ❌          | ❌     |
| Tool Agent      | ✅   | ✅    | ❌  | ✅      | ✅     | ❌          | ❌     |
| Full Platform   | ✅   | ✅    | ✅  | ✅      | ✅     | ✅          | ❌     |
| Enterprise      | ✅   | ✅    | ✅  | ✅      | ✅     | ✅          | ✅     |

---

## Security Principles

### 1. Least Privilege

Every policy grants only the minimum permissions required:

```json
{
  "Effect": "Allow",
  "Action": [
    "bedrock:InvokeAgent"  // Only what's needed
  ],
  "Resource": [
    "arn:aws:bedrock:*:${AWS::AccountId}:agent/*"  // Scoped to account
  ]
}
```

### 2. Confused Deputy Protection

All trust policies include source ARN/account conditions:

```json
{
  "Effect": "Allow",
  "Principal": {
    "Service": "bedrock.amazonaws.com"
  },
  "Action": "sts:AssumeRole",
  "Condition": {
    "StringEquals": {
      "aws:SourceAccount": "${AWS::AccountId}"
    },
    "ArnLike": {
      "aws:SourceArn": "arn:aws:bedrock:*:${AWS::AccountId}:agent/*"
    }
  }
}
```

### 3. Attribute-Based Access Control (ABAC)

Tags control access at runtime:

```json
{
  "Condition": {
    "StringEquals": {
      "aws:ResourceTag/AgentCore:Application": "${aws:PrincipalTag/Application}"
    }
  }
}
```

### 4. Deny Statements for Critical Protections

Explicit denies prevent security bypasses:

```json
{
  "Sid": "DenyUntaggedResourceCreation",
  "Effect": "Deny",
  "Action": [
    "bedrock:CreateAgent",
    "bedrock:CreateKnowledgeBase"
  ],
  "Resource": "*",
  "Condition": {
    "Null": {
      "aws:RequestTag/AgentCore:Application": "true"
    }
  }
}
```

---

## Role Design

### Execution Role (Primary)

The main role assumed by Bedrock Agents:

| Attribute | Value |
|-----------|-------|
| Name Pattern | `AgentCore-{AppName}-{Env}-ExecutionRole` |
| Trust Principal | `bedrock.amazonaws.com` |
| Permissions Boundary | Yes (recommended) |
| Session Duration | 1 hour (default) |

### Lambda Service Role

For action group functions:

| Attribute | Value |
|-----------|-------|
| Name Pattern | `AgentCore-{AppName}-{Env}-LambdaRole` |
| Trust Principal | `lambda.amazonaws.com` |
| Managed Policies | `AWSLambdaBasicExecutionRole` |

---

## Policy Breakdown

### base-policy.json

**Purpose**: Core agent operations required by all agents

**Permissions**:
- Agent invocation and lifecycle management
- Prompt management
- Flow operations
- IAM PassRole for Bedrock

**Key Conditions**:
- Resource tagging requirements
- Tag-based access control
- Deny untagged resource creation

### model-access-policy.json

**Purpose**: Foundation model invocation

**Permissions**:
- InvokeModel / InvokeModelWithResponseStream
- Converse / ConverseStream APIs
- Cross-region inference profiles
- Custom and provisioned model access

**Supported Models**:
- Anthropic Claude (3, 3.5)
- Amazon Titan (text, embeddings)
- Cohere (embeddings)
- Meta Llama

### knowledge-base-policy.json

**Purpose**: RAG and knowledge base operations

**Permissions**:
- Knowledge base CRUD operations
- Data source management
- Ingestion job control
- Retrieve and RetrieveAndGenerate APIs

**Dependencies**:
- Requires `s3-data-policy.json` for data access
- Requires `opensearch-policy.json` for vector stores

### action-groups-policy.json

**Purpose**: Lambda and API action group invocation

**Permissions**:
- Lambda function invocation
- API Gateway execution
- Step Functions execution
- Lambda resource policy management

**Naming Convention**:
Functions must be prefixed with `AgentCore-` or `agentcore-`

### secrets-manager-policy.json

**Purpose**: API key and credential access

**Permissions**:
- Secret value retrieval
- Secret rotation
- Parameter Store access
- KMS decryption for secrets

**Security**:
- Secrets must be KMS encrypted
- Secret type tagging required
- Version stage restrictions

### opensearch-policy.json

**Purpose**: Vector store operations

**Permissions**:
- OpenSearch Serverless collection access
- Security and access policy management
- VPC endpoint management
- RDS Aurora vector store access

### guardrails-policy.json

**Purpose**: Content filtering and safety

**Permissions**:
- Guardrail CRUD operations
- Guardrail application
- Evaluation job management
- Content filtering logging

### multi-agent-policy.json

**Purpose**: Agent collaboration and orchestration

**Permissions**:
- Cross-agent invocation
- Shared knowledge base access
- Agent memory management
- EventBridge/SNS/SQS coordination
- DynamoDB state management
- Flow orchestration

**Key Tag**: `AgentCore:Platform` for platform-wide access

### cloudwatch-policy.json

**Purpose**: Logging and monitoring

**Permissions**:
- Log group/stream management
- Metric publication
- Alarm management
- Dashboard management
- X-Ray tracing
- CloudWatch Insights queries

**Namespaces**:
- `AgentCore/Agents`
- `AgentCore/KnowledgeBases`
- `AgentCore/Platform`
- `AWS/Bedrock`

### cross-account-policy.json

**Purpose**: Multi-account agent access

**Permissions**:
- Cross-account agent invocation
- Shared knowledge base retrieval
- Cross-account role assumption
- Shared S3 and Secrets access
- Cross-account EventBridge

**Security**:
- Organization path validation
- External ID requirements
- Cross-account access tags

---

## Condition Keys Reference

### Bedrock-Specific Condition Keys

| Key | Description | Example |
|-----|-------------|---------|
| `bedrock:AgentAliasTag/*` | Agent alias tags | Content filtering |
| `bedrock:GuardrailArn` | Associated guardrail | Guardrail enforcement |
| `bedrock:InferenceProfileArn` | Inference profile | Cross-region routing |
| `bedrock:InvokeModelUseCases` | Invocation context | KNOWLEDGE_BASE |

### AWS Global Condition Keys

| Key | Description | Example |
|-----|-------------|---------|
| `aws:SourceArn` | Source resource ARN | Confused deputy |
| `aws:SourceAccount` | Source account ID | Account isolation |
| `aws:PrincipalTag/*` | Session tags | ABAC |
| `aws:ResourceTag/*` | Resource tags | Resource access |
| `aws:RequestTag/*` | Request tags | Tag enforcement |
| `aws:TagKeys` | Tag key list | Required tags |
| `aws:ResourceOrgPaths` | Org unit paths | Cross-account |

---

## Multi-Account Strategy

### Hub-Spoke Model

```
                    ┌─────────────────────┐
                    │    Hub Account      │
                    │  (Shared Services)  │
                    │                     │
                    │  • Shared KBs       │
                    │  • Central Secrets  │
                    │  • Audit Logging    │
                    └──────────┬──────────┘
                               │
          ┌────────────────────┼────────────────────┐
          │                    │                    │
          ▼                    ▼                    ▼
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│  Spoke Account  │  │  Spoke Account  │  │  Spoke Account  │
│   (Dev Agents)  │  │ (Staging Agents)│  │  (Prod Agents)  │
└─────────────────┘  └─────────────────┘  └─────────────────┘
```

### Cross-Account Role Chain

1. **Agent in Spoke** assumes cross-account role
2. **Cross-account role** has trust for spoke account
3. **Resource policies** allow cross-account access
4. **Tags** validate platform membership

---

## Tagging Strategy

### Required Tags

| Tag Key | Description | Example |
|---------|-------------|---------|
| `AgentCore:Application` | Application identifier | `inventory-agent` |
| `AgentCore:Environment` | Environment name | `prod` |
| `AgentCore:Platform` | Platform identifier | `enterprise-platform` |

### Optional Tags

| Tag Key | Description | Example |
|---------|-------------|---------|
| `AgentCore:AgentId` | Specific agent ID | `abc123` |
| `AgentCore:CostCenter` | Billing allocation | `engineering` |
| `AgentCore:SharedAccess` | Cross-agent sharing | `true` |
| `AgentCore:CrossAccountAccess` | Cross-account flag | `true` |
| `AgentCore:SecretType` | Secret classification | `api-key` |

### Tag Propagation

```
Agent Creation
      │
      ▼
┌─────────────────────┐
│ Request Tags        │
│ (must include       │
│  Application tag)   │
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│ Resource Tags       │
│ (inherited to       │
│  all sub-resources) │
└─────────────────────┘
```

---

## Usage Examples

### Creating an Agent with the Role

```python
import boto3

bedrock_agent = boto3.client('bedrock-agent')

response = bedrock_agent.create_agent(
    agentName='my-inventory-agent',
    agentResourceRoleArn='arn:aws:iam::123456789012:role/AgentCore-myapp-prod-ExecutionRole',
    foundationModel='anthropic.claude-3-sonnet-20240229-v1:0',
    instruction='You are an inventory management assistant...',
    tags={
        'AgentCore:Application': 'inventory-agent',
        'AgentCore:Environment': 'prod',
        'AgentCore:Platform': 'enterprise-platform'
    }
)
```

### Attaching Knowledge Base

```python
response = bedrock_agent.associate_agent_knowledge_base(
    agentId='AGENT123',
    agentVersion='DRAFT',
    knowledgeBaseId='KB456',
    description='Product catalog knowledge base',
    knowledgeBaseState='ENABLED'
)
```

### Multi-Agent Invocation

```python
bedrock_runtime = boto3.client('bedrock-agent-runtime')

# Orchestrator agent invoking specialist agent
response = bedrock_runtime.invoke_agent(
    agentId='SPECIALIST_AGENT_ID',
    agentAliasId='ALIAS_ID',
    sessionId='shared-session-123',
    inputText='Process this inventory request'
)
```

---

## Troubleshooting

### Common Issues

#### 1. AccessDenied on InvokeModel

**Cause**: Model not in allowed list or region mismatch

**Solution**: 
- Verify model ARN in `model-access-policy.json`
- Check if cross-region inference is configured

#### 2. AccessDenied on Knowledge Base

**Cause**: Missing S3 or OpenSearch permissions

**Solution**:
- Attach `s3-data-policy.json`
- Attach `opensearch-policy.json`
- Verify bucket naming convention

#### 3. Tag Condition Failures

**Cause**: Resources missing required tags

**Solution**:
```bash
# Check resource tags
aws bedrock get-agent --agent-id AGENT_ID --query 'agent.tags'

# Add missing tags
aws bedrock tag-resource --resource-arn ARN --tags AgentCore:Application=myapp
```

#### 4. Cross-Account Access Denied

**Cause**: Organization path or external ID mismatch

**Solution**:
- Verify `aws:ResourceOrgPaths` matches
- Confirm external ID in trust policy
- Check `AgentCore:CrossAccountAccess` tag

### Debug Commands

```bash
# Simulate policy evaluation
aws iam simulate-principal-policy \
    --policy-source-arn arn:aws:iam::123456789012:role/AgentCore-myapp-prod-ExecutionRole \
    --action-names bedrock:InvokeAgent \
    --resource-arns arn:aws:bedrock:us-east-1:123456789012:agent/ABC123

# Check role policies
aws iam list-attached-role-policies --role-name AgentCore-myapp-prod-ExecutionRole

# Verify trust policy
aws iam get-role --role-name AgentCore-myapp-prod-ExecutionRole --query 'Role.AssumeRolePolicyDocument'
```

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2024-01 | Initial release |
| 1.1.0 | 2024-02 | Added multi-agent collaboration |
| 1.2.0 | 2024-03 | Added cross-account support |

---

## Contact

For questions or issues with this IAM architecture, contact your AWS Solutions Architect or raise an issue in the repository.
