# Agent 6: Auto-Remediation Agent - Technical Design

## Document Information
| Attribute | Value |
|-----------|-------|
| Version | 1.0 |
| Last Updated | January 14, 2026 |
| Status | Draft |
| Owner | Platform Engineering |
| Agent ID | `auto-remediation-agent` |

---

## 1. Executive Summary

The **Auto-Remediation Agent** is the most carefully controlled agent in the multi-agent system. It has the ability to perform **write operations** to recover from common patching failures. Due to the sensitive nature of these operations, this agent is implemented with **extensive guardrails, approval workflows, and blast radius controls**.

### 1.1 Key Capabilities

| Capability | Description | Priority | Approval Required |
|------------|-------------|----------|-------------------|
| SSM Agent Recovery | Restart unresponsive SSM agents | P0 | Auto (with limits) |
| Controlled Retry | Retry failed patch operations | P0 | Threshold-based |
| Force Stop/Start | Recover hung instances | P1 | Always |
| Cleanup Operations | Clear disk space, temp files | P1 | Auto |
| Rollback | Revert failed patches | P2 | Always |
| Escalation | Create tickets, page on-call | P0 | Never |

### 1.2 Safety-First Design Principles

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           SAFETY-FIRST DESIGN                                │
│                                                                              │
│  1. LEAST PRIVILEGE    - Only permissions absolutely necessary              │
│  2. BLAST RADIUS       - Maximum 5 instances per autonomous action          │
│  3. APPROVAL WORKFLOW  - High-risk actions require human approval           │
│  4. AUDIT TRAIL        - Every action logged with full context              │
│  5. RATE LIMITING      - Prevent runaway automation                         │
│  6. ROLLBACK READY     - Every action must be reversible                    │
│  7. HUMAN IN THE LOOP  - Escalate when uncertain                            │
│  8. FAIL SAFE          - Default to no action when in doubt                 │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Architecture

```
┌──────────────────────────────────────────────────────────────────────────────────────┐
│                          AUTO-REMEDIATION AGENT                                       │
│                                                                                       │
│  ┌─────────────────────────────────────────────────────────────────────────────────┐ │
│  │                              AGENT CORE                                          │ │
│  │  Model: anthropic.claude-3-sonnet-20240229-v1:0                                 │ │
│  │  Temperature: 0.0 (deterministic, predictable)                                  │ │
│  │  Max Tokens: 2048 (concise action descriptions)                                 │ │
│  └─────────────────────────────────────────────────────────────────────────────────┘ │
│                                        │                                              │
│                              ┌─────────┴─────────┐                                   │
│                              │   GUARDRAILS      │                                   │
│                              │   GATEWAY         │                                   │
│                              │   (MANDATORY)     │                                   │
│                              └─────────┬─────────┘                                   │
│                                        │                                              │
│         ┌──────────────────────────────┼──────────────────────────────┐               │
│         │                              │                              │               │
│         ▼                              ▼                              ▼               │
│  ┌─────────────────┐     ┌────────────────────────┐    ┌─────────────────────────┐  │
│  │ KNOWLEDGE BASES │     │     ACTION GROUPS       │    │  APPROVAL ENGINE        │  │
│  │                 │     │                         │    │                         │  │
│  │ • runbooks      │     │ • Recovery Actions      │    │ • Threshold Checker     │  │
│  │ • troubleshoot  │     │ • Retry Controller      │    │ • Approval Workflow     │  │
│  │ • error-patterns│     │ • Cleanup Operations    │    │ • Human Escalation      │  │
│  └─────────────────┘     │ • Escalation Manager    │    │ • Audit Logger          │  │
│                          └────────────────────────┘    └─────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────────────────────┘
                                        │
                                        ▼
┌──────────────────────────────────────────────────────────────────────────────────────┐
│                          ACTION EXECUTION LAYER                                       │
│                                                                                       │
│  ┌─────────────────────────────────────────────────────────────────────────────────┐ │
│  │                         EXECUTION CONTROLS                                       │ │
│  │                                                                                  │ │
│  │  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────────────────┐  │ │
│  │  │ Rate Limiter     │  │ Blast Radius     │  │ Rollback Controller         │  │ │
│  │  │                  │  │ Controller       │  │                              │  │ │
│  │  │ • 10 actions/hr  │  │ • Max 5 instances│  │ • Pre-action snapshots      │  │ │
│  │  │ • Per-account    │  │ • Per-account    │  │ • Rollback triggers         │  │ │
│  │  │ • Per-action type│  │ • Per-action     │  │ • State preservation        │  │ │
│  │  └──────────────────┘  └──────────────────┘  └──────────────────────────────┘  │ │
│  │                                                                                  │ │
│  └─────────────────────────────────────────────────────────────────────────────────┘ │
│                                                                                       │
│  ┌─────────────────────────────────────────────────────────────────────────────────┐ │
│  │                         AUDIT & COMPLIANCE LOG                                   │ │
│  │                                                                                  │ │
│  │  Every action recorded with:                                                    │ │
│  │  • Timestamp, Actor (agent + trigger)                                          │ │
│  │  • Target resources                                                            │ │
│  │  • Action type, Parameters                                                     │ │
│  │  • Pre-state, Post-state                                                       │ │
│  │  • Approval chain (if applicable)                                              │ │
│  │  • Outcome (success/failure/rollback)                                          │ │
│  └─────────────────────────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Action Classification

### 3.1 Action Risk Tiers

```yaml
ActionTiers:
  TIER_1_AUTO:
    description: "Low-risk, high-confidence, fully automated"
    approval: "None - autonomous execution"
    examples:
      - "Restart SSM agent on single instance"
      - "Clear temp files on single instance"
      - "Retry scan operation"
    limits:
      max_instances_per_action: 1
      max_actions_per_hour: 20
      require_prior_failure: true
  
  TIER_2_THRESHOLD:
    description: "Medium-risk, automated up to threshold"
    approval: "Required after threshold exceeded"
    examples:
      - "Retry failed patch installation"
      - "Restart SSM agent on multiple instances"
      - "Clear package manager cache"
    limits:
      max_instances_per_action: 5
      max_actions_per_hour: 10
      auto_threshold: 3  # After 3, require approval
      cooldown_minutes: 15
  
  TIER_3_APPROVAL:
    description: "High-risk, always requires approval"
    approval: "Always - human approval mandatory"
    examples:
      - "Force stop/start instance"
      - "Rollback patches"
      - "Modify security group (emergency)"
    limits:
      max_instances_per_action: 1
      approval_timeout_minutes: 30
      require_justification: true
  
  TIER_4_PROHIBITED:
    description: "Destructive actions - never automated"
    approval: "Denied - must be manual"
    examples:
      - "Terminate instance"
      - "Delete volumes"
      - "Modify IAM roles"
    limits:
      automated: false
      escalate_to_human: true
```

### 3.2 Action Approval Matrix

| Action | Tier | Auto Limit | Approval After | Cooldown |
|--------|------|------------|----------------|----------|
| Restart SSM Agent | T1 | 1 instance | Never | 5 min |
| Clear Temp Files | T1 | 1 instance | Never | 5 min |
| Retry Scan | T1 | 5 instances | Never | 10 min |
| Retry Patch Install | T2 | 3 instances | 3rd retry | 15 min |
| Clear Package Cache | T2 | 3 instances | 3rd action | 10 min |
| Batch SSM Restart | T2 | 5 instances | Always | 30 min |
| Force Stop/Start | T3 | 1 instance | Always | 60 min |
| Rollback Patches | T3 | 1 instance | Always | N/A |
| Emergency Reboot | T3 | 1 instance | Always | 60 min |
| Terminate Instance | T4 | 0 | Never | N/A |

---

## 4. Guardrails Configuration

### 4.1 Bedrock Guardrails

```yaml
AutoRemediationGuardrails:
  Type: AWS::Bedrock::Guardrail
  Properties:
    Name: !Sub '${NamePrefix}-auto-remediation-guardrails'
    Description: 'Strict guardrails for auto-remediation agent'
    BlockedInputMessaging: |
      This request has been blocked for safety. The auto-remediation
      agent cannot perform the requested action. Please escalate
      to a human operator.
    BlockedOutputMessaging: |
      The generated response was blocked because it suggested
      an action that violates safety policies.
    
    ContentPolicyConfig:
      FiltersConfig:
        - Type: VIOLENCE
          InputStrength: HIGH
          OutputStrength: HIGH
        - Type: MISCONDUCT
          InputStrength: HIGH
          OutputStrength: HIGH
        - Type: PROMPT_ATTACK
          InputStrength: HIGH
          OutputStrength: HIGH
    
    TopicPolicyConfig:
      TopicsConfig:
        - Name: 'Prohibited-Actions'
          Description: 'Block any destructive or prohibited actions'
          Definition: 'Actions that could terminate instances, delete data, modify IAM, or cause irreversible damage'
          Type: DENY
          Examples:
            - 'Terminate the instance'
            - 'Delete the EBS volume'
            - 'Remove the IAM role'
            - 'Drop the database'
        - Name: 'Scope-Creep'
          Description: 'Block actions outside patching remediation'
          Definition: 'Any actions not directly related to fixing patching failures'
          Type: DENY
          Examples:
            - 'Deploy new application'
            - 'Create new resources'
            - 'Modify application configuration'
    
    WordPolicyConfig:
      ManagedWordListsConfig:
        - Type: PROFANITY
      WordsConfig:
        - Text: 'terminate'
        - Text: 'destroy'
        - Text: 'delete permanently'
        - Text: 'DROP TABLE'
        - Text: 'rm -rf'
```

### 4.2 Custom Validation Layer

```python
"""
Action Validation Layer
Validates all remediation actions before execution
"""

import json
from typing import Dict, Any, Optional
from dataclasses import dataclass
from enum import Enum

class ActionTier(Enum):
    TIER_1_AUTO = 1
    TIER_2_THRESHOLD = 2
    TIER_3_APPROVAL = 3
    TIER_4_PROHIBITED = 4


@dataclass
class ValidationResult:
    allowed: bool
    requires_approval: bool
    denial_reason: Optional[str] = None
    warnings: list = None
    approval_id: Optional[str] = None


PROHIBITED_PATTERNS = [
    r'terminate.*instance',
    r'delete.*volume',
    r'remove.*iam',
    r'modify.*security.*group',  # Except in emergency
    r'rm\s+-rf',
    r'format\s+',
    r'DROP\s+',
]


def validate_action(action: Dict[str, Any], context: Dict[str, Any]) -> ValidationResult:
    """Validate remediation action before execution"""
    
    action_type = action.get('type')
    targets = action.get('targets', [])
    
    # Check if action type is known
    if action_type not in ACTION_REGISTRY:
        return ValidationResult(
            allowed=False,
            requires_approval=False,
            denial_reason=f"Unknown action type: {action_type}"
        )
    
    action_config = ACTION_REGISTRY[action_type]
    tier = action_config['tier']
    
    # TIER 4 - Always denied
    if tier == ActionTier.TIER_4_PROHIBITED:
        return ValidationResult(
            allowed=False,
            requires_approval=False,
            denial_reason=f"Action '{action_type}' is prohibited for automation"
        )
    
    # Check blast radius
    if len(targets) > action_config['max_targets']:
        return ValidationResult(
            allowed=False,
            requires_approval=False,
            denial_reason=f"Target count {len(targets)} exceeds maximum {action_config['max_targets']}"
        )
    
    # Check rate limits
    if not check_rate_limit(action_type, context.get('account_id')):
        return ValidationResult(
            allowed=False,
            requires_approval=False,
            denial_reason=f"Rate limit exceeded for {action_type}"
        )
    
    # TIER 3 - Always requires approval
    if tier == ActionTier.TIER_3_APPROVAL:
        approval_id = request_approval(action, context)
        return ValidationResult(
            allowed=False,
            requires_approval=True,
            approval_id=approval_id
        )
    
    # TIER 2 - Check threshold
    if tier == ActionTier.TIER_2_THRESHOLD:
        action_count = get_recent_action_count(action_type, context)
        if action_count >= action_config['auto_threshold']:
            approval_id = request_approval(action, context)
            return ValidationResult(
                allowed=False,
                requires_approval=True,
                approval_id=approval_id,
                warnings=[f"Threshold of {action_config['auto_threshold']} reached"]
            )
    
    # TIER 1 or within TIER 2 threshold - Allowed
    return ValidationResult(
        allowed=True,
        requires_approval=False,
        warnings=generate_warnings(action, context)
    )


ACTION_REGISTRY = {
    'restart_ssm_agent': {
        'tier': ActionTier.TIER_1_AUTO,
        'max_targets': 1,
        'cooldown_seconds': 300,
        'rate_limit_per_hour': 20
    },
    'clear_temp_files': {
        'tier': ActionTier.TIER_1_AUTO,
        'max_targets': 1,
        'cooldown_seconds': 300,
        'rate_limit_per_hour': 20
    },
    'retry_patch_scan': {
        'tier': ActionTier.TIER_1_AUTO,
        'max_targets': 5,
        'cooldown_seconds': 600,
        'rate_limit_per_hour': 20
    },
    'retry_patch_install': {
        'tier': ActionTier.TIER_2_THRESHOLD,
        'max_targets': 3,
        'cooldown_seconds': 900,
        'rate_limit_per_hour': 10,
        'auto_threshold': 3
    },
    'clear_package_cache': {
        'tier': ActionTier.TIER_2_THRESHOLD,
        'max_targets': 3,
        'cooldown_seconds': 600,
        'rate_limit_per_hour': 10,
        'auto_threshold': 3
    },
    'batch_ssm_restart': {
        'tier': ActionTier.TIER_2_THRESHOLD,
        'max_targets': 5,
        'cooldown_seconds': 1800,
        'rate_limit_per_hour': 5,
        'auto_threshold': 1  # Always approve for batch
    },
    'force_stop_start': {
        'tier': ActionTier.TIER_3_APPROVAL,
        'max_targets': 1,
        'cooldown_seconds': 3600,
        'rate_limit_per_hour': 3
    },
    'rollback_patches': {
        'tier': ActionTier.TIER_3_APPROVAL,
        'max_targets': 1,
        'cooldown_seconds': None,  # No auto-retry
        'rate_limit_per_hour': 2
    },
    'terminate_instance': {
        'tier': ActionTier.TIER_4_PROHIBITED,
        'max_targets': 0
    }
}
```

---

## 5. Action Groups (Tools)

### 5.1 Action Group: `recovery-actions`

#### 5.1.1 Tool: `restart_ssm_agent`

**Purpose:** Restart unresponsive SSM agent

**OpenAPI Schema:**
```yaml
openapi: 3.0.0
info:
  title: Auto-Remediation API
  version: 1.0.0

paths:
  /restart-ssm-agent:
    post:
      operationId: restartSsmAgent
      summary: Restart SSM agent on target instance
      description: |
        Restarts the SSM agent on a single instance to recover
        from connectivity issues. Limited to 1 instance per action.
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              properties:
                instanceId:
                  type: string
                  description: Target instance ID
                reason:
                  type: string
                  description: Reason for restart (for audit log)
                executionId:
                  type: string
                  description: Related patching execution ID
              required:
                - instanceId
                - reason
      responses:
        '200':
          description: Action result
          content:
            application/json:
              schema:
                type: object
                properties:
                  status:
                    type: string
                    enum: [executed, pending_approval, denied, rate_limited]
                  actionId:
                    type: string
                  commandId:
                    type: string
                    description: SSM command ID if executed
                  message:
                    type: string
                  nextAllowedAction:
                    type: string
                    format: date-time
```

**Lambda Handler:**
```python
"""
SSM Agent Recovery Handler
Restarts SSM agent on unresponsive instances
"""

import json
import boto3
from datetime import datetime, timedelta
from typing import Dict, Any
import uuid

ssm = boto3.client('ssm')
ec2 = boto3.client('ec2')
dynamodb = boto3.resource('dynamodb')

audit_table = dynamodb.Table(os.environ['AUDIT_TABLE'])
rate_limit_table = dynamodb.Table(os.environ['RATE_LIMIT_TABLE'])


def handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """Restart SSM agent on instance"""
    
    params = event.get('requestBody', {}).get('content', {}).get('application/json', {})
    
    instance_id = params.get('instanceId')
    reason = params.get('reason')
    execution_id = params.get('executionId')
    
    action_id = f"rem-{uuid.uuid4().hex[:12]}"
    
    # Validate action
    validation = validate_action({
        'type': 'restart_ssm_agent',
        'targets': [instance_id]
    }, {
        'account_id': get_instance_account(instance_id)
    })
    
    if not validation.allowed:
        # Log denied action
        log_action(action_id, 'restart_ssm_agent', instance_id, 'DENIED', 
                   reason=validation.denial_reason)
        
        if validation.requires_approval:
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'status': 'pending_approval',
                    'actionId': action_id,
                    'approvalId': validation.approval_id,
                    'message': 'Action requires approval. Approval request sent.'
                })
            }
        else:
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'status': 'denied',
                    'actionId': action_id,
                    'message': validation.denial_reason
                })
            }
    
    # Get instance platform
    instance_info = get_instance_info(instance_id)
    platform = instance_info.get('platform', 'linux')
    
    # Prepare command based on platform
    if platform == 'windows':
        command = 'Restart-Service AmazonSSMAgent -Force'
        document_name = 'AWS-RunPowerShellScript'
    else:
        command = 'sudo systemctl restart amazon-ssm-agent || sudo service amazon-ssm-agent restart'
        document_name = 'AWS-RunShellScript'
    
    # Execute via SSM (through EC2 Systems Manager - Run Command)
    try:
        # First, try direct SSM command
        response = ssm.send_command(
            InstanceIds=[instance_id],
            DocumentName=document_name,
            Parameters={'commands': [command]},
            TimeoutSeconds=120,
            Comment=f'Auto-remediation: {reason}'
        )
        
        command_id = response['Command']['CommandId']
        
        # Log successful execution
        log_action(action_id, 'restart_ssm_agent', instance_id, 'EXECUTED',
                   reason=reason, command_id=command_id, execution_id=execution_id)
        
        # Update rate limit
        record_action('restart_ssm_agent', get_instance_account(instance_id))
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'status': 'executed',
                'actionId': action_id,
                'commandId': command_id,
                'message': f'SSM agent restart initiated on {instance_id}',
                'nextAllowedAction': (datetime.utcnow() + timedelta(seconds=300)).isoformat()
            })
        }
        
    except ssm.exceptions.InvalidInstanceId:
        # Instance not reachable via SSM - try alternative method
        log_action(action_id, 'restart_ssm_agent', instance_id, 'FAILED',
                   reason='Instance not reachable via SSM', escalate=True)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'status': 'escalated',
                'actionId': action_id,
                'message': f'Instance {instance_id} not reachable via SSM. Escalated to on-call.',
                'escalationTicket': create_escalation_ticket(instance_id, reason)
            })
        }


def log_action(action_id: str, action_type: str, target: str, status: str, **kwargs):
    """Log remediation action to audit table"""
    
    item = {
        'action_id': action_id,
        'action_type': action_type,
        'target': target,
        'status': status,
        'timestamp': datetime.utcnow().isoformat(),
        'agent': 'auto-remediation-agent',
        'ttl': int((datetime.utcnow() + timedelta(days=365)).timestamp())
    }
    item.update(kwargs)
    
    audit_table.put_item(Item=item)
```

#### 5.1.2 Tool: `retry_patch_operation`

**Purpose:** Retry failed patch operation

**OpenAPI Schema:**
```yaml
paths:
  /retry-patch:
    post:
      operationId: retryPatchOperation
      summary: Retry a failed patch operation
      description: |
        Retries a failed patch scan or installation on specific instances.
        Subject to rate limiting and approval thresholds.
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              properties:
                instanceIds:
                  type: array
                  items:
                    type: string
                  maxItems: 5
                  description: Target instances (max 5)
                operation:
                  type: string
                  enum: [scan, install]
                  description: Patch operation type
                originalExecutionId:
                  type: string
                  description: Original failed execution ID
                reason:
                  type: string
              required:
                - instanceIds
                - operation
                - reason
      responses:
        '200':
          description: Retry result
          content:
            application/json:
              schema:
                type: object
                properties:
                  status:
                    type: string
                  actionId:
                    type: string
                  commandIds:
                    type: object
                    additionalProperties:
                      type: string
                  message:
                    type: string
```

#### 5.1.3 Tool: `force_stop_start_instance`

**Purpose:** Force stop and start a hung instance (requires approval)

**OpenAPI Schema:**
```yaml
paths:
  /force-stop-start:
    post:
      operationId: forceStopStartInstance
      summary: Force stop and start an instance
      description: |
        Forces a stop and start cycle on a hung instance.
        This is a TIER 3 action and always requires human approval.
        
        WARNING: This action will interrupt any running processes.
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              properties:
                instanceId:
                  type: string
                  description: Target instance (single instance only)
                reason:
                  type: string
                  minLength: 20
                  description: Detailed justification (min 20 chars)
                executionId:
                  type: string
                evidenceUrls:
                  type: array
                  items:
                    type: string
                  description: Links to logs/evidence supporting this action
                acknowledgeRisk:
                  type: boolean
                  description: Must be true to proceed
              required:
                - instanceId
                - reason
                - acknowledgeRisk
      responses:
        '200':
          description: Action result
          content:
            application/json:
              schema:
                type: object
                properties:
                  status:
                    type: string
                    enum: [pending_approval, executed, denied]
                  approvalId:
                    type: string
                  approvers:
                    type: array
                    items:
                      type: string
                  timeout:
                    type: string
                    format: date-time
                  message:
                    type: string
```

**Lambda Handler:**
```python
"""
Force Stop/Start Handler
Recovers hung instances (requires approval)
"""

import json
import boto3
from datetime import datetime, timedelta
from typing import Dict, Any
import uuid

ec2 = boto3.client('ec2')
sns = boto3.client('sns')
dynamodb = boto3.resource('dynamodb')

approvals_table = dynamodb.Table(os.environ['APPROVALS_TABLE'])


def handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """Force stop/start instance (with approval)"""
    
    params = event.get('requestBody', {}).get('content', {}).get('application/json', {})
    
    instance_id = params.get('instanceId')
    reason = params.get('reason', '')
    evidence = params.get('evidenceUrls', [])
    acknowledge = params.get('acknowledgeRisk', False)
    
    action_id = f"rem-{uuid.uuid4().hex[:12]}"
    
    # Validation checks
    if not acknowledge:
        return {
            'statusCode': 400,
            'body': json.dumps({
                'status': 'denied',
                'message': 'acknowledgeRisk must be true to proceed with force stop/start'
            })
        }
    
    if len(reason) < 20:
        return {
            'statusCode': 400,
            'body': json.dumps({
                'status': 'denied',
                'message': 'Reason must be at least 20 characters'
            })
        }
    
    # This is ALWAYS a TIER 3 action - requires approval
    approval_id = f"approval-{uuid.uuid4().hex[:12]}"
    
    # Get instance details for approval request
    instance_info = get_instance_info(instance_id)
    
    # Store approval request
    approvals_table.put_item(Item={
        'approval_id': approval_id,
        'action_id': action_id,
        'action_type': 'force_stop_start',
        'instance_id': instance_id,
        'instance_info': instance_info,
        'reason': reason,
        'evidence': evidence,
        'status': 'pending',
        'requested_at': datetime.utcnow().isoformat(),
        'expires_at': (datetime.utcnow() + timedelta(minutes=30)).isoformat(),
        'ttl': int((datetime.utcnow() + timedelta(hours=24)).timestamp())
    })
    
    # Notify approvers
    approvers = get_approvers_for_account(instance_info.get('account_id'))
    
    send_approval_notification(
        approval_id=approval_id,
        action_type='Force Stop/Start Instance',
        target=instance_id,
        instance_info=instance_info,
        reason=reason,
        evidence=evidence,
        approvers=approvers
    )
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'status': 'pending_approval',
            'actionId': action_id,
            'approvalId': approval_id,
            'approvers': [a['name'] for a in approvers],
            'timeout': (datetime.utcnow() + timedelta(minutes=30)).isoformat(),
            'message': f'Force stop/start requires approval. Request sent to {len(approvers)} approvers.'
        })
    }


def execute_force_stop_start(approval: dict) -> dict:
    """Execute approved force stop/start"""
    
    instance_id = approval['instance_id']
    
    # Pre-action state capture
    pre_state = capture_instance_state(instance_id)
    
    try:
        # Force stop
        ec2.stop_instances(
            InstanceIds=[instance_id],
            Force=True
        )
        
        # Wait for stopped state (max 5 minutes)
        waiter = ec2.get_waiter('instance_stopped')
        waiter.wait(
            InstanceIds=[instance_id],
            WaiterConfig={'Delay': 15, 'MaxAttempts': 20}
        )
        
        # Start instance
        ec2.start_instances(
            InstanceIds=[instance_id]
        )
        
        # Wait for running state
        waiter = ec2.get_waiter('instance_running')
        waiter.wait(
            InstanceIds=[instance_id],
            WaiterConfig={'Delay': 15, 'MaxAttempts': 20}
        )
        
        # Post-action state capture
        post_state = capture_instance_state(instance_id)
        
        return {
            'status': 'success',
            'pre_state': pre_state,
            'post_state': post_state
        }
        
    except Exception as e:
        return {
            'status': 'failed',
            'error': str(e),
            'pre_state': pre_state
        }


def capture_instance_state(instance_id: str) -> dict:
    """Capture instance state for audit and rollback"""
    
    response = ec2.describe_instances(InstanceIds=[instance_id])
    instance = response['Reservations'][0]['Instances'][0]
    
    return {
        'instance_id': instance_id,
        'state': instance['State']['Name'],
        'private_ip': instance.get('PrivateIpAddress'),
        'public_ip': instance.get('PublicIpAddress'),
        'timestamp': datetime.utcnow().isoformat()
    }
```

### 5.2 Action Group: `escalation`

#### 5.2.1 Tool: `escalate_to_human`

**Purpose:** Escalate issue to human operators

**OpenAPI Schema:**
```yaml
paths:
  /escalate:
    post:
      operationId: escalateToHuman
      summary: Escalate issue to human operators
      description: |
        Creates an escalation ticket and optionally pages on-call.
        Used when automated remediation is not possible or appropriate.
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              properties:
                severity:
                  type: string
                  enum: [low, medium, high, critical]
                  description: Escalation severity
                summary:
                  type: string
                  description: Brief summary of the issue
                details:
                  type: string
                  description: Detailed context and investigation so far
                affectedInstances:
                  type: array
                  items:
                    type: string
                executionId:
                  type: string
                attemptedRemediations:
                  type: array
                  items:
                    type: object
                    properties:
                      action:
                        type: string
                      result:
                        type: string
                pageOnCall:
                  type: boolean
                  default: false
                  description: Whether to page on-call immediately
              required:
                - severity
                - summary
                - details
      responses:
        '200':
          description: Escalation result
          content:
            application/json:
              schema:
                type: object
                properties:
                  escalationId:
                    type: string
                  ticketUrl:
                    type: string
                  oncallPaged:
                    type: boolean
                  message:
                    type: string
```

---

## 6. Approval Workflow

### 6.1 Approval Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          APPROVAL WORKFLOW                                   │
│                                                                              │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────┐                │
│  │ Agent        │────▶│ Validation   │────▶│ Approval     │                │
│  │ Request      │     │ Layer        │     │ Required?    │                │
│  └──────────────┘     └──────────────┘     └──────┬───────┘                │
│                                                    │                         │
│                              ┌────────────────────┴────────────────────┐    │
│                              │                                          │    │
│                              ▼ NO                                   YES ▼    │
│                    ┌──────────────────┐                    ┌──────────────┐ │
│                    │ Execute          │                    │ Create       │ │
│                    │ Immediately      │                    │ Approval     │ │
│                    └──────────────────┘                    │ Request      │ │
│                                                            └──────┬───────┘ │
│                                                                   │         │
│                                                                   ▼         │
│                                                     ┌──────────────────────┐│
│                                                     │ Notify Approvers     ││
│                                                     │ • Slack              ││
│                                                     │ • Email              ││
│                                                     │ • PagerDuty          ││
│                                                     └──────────┬───────────┘│
│                                                                │            │
│                                        ┌───────────────────────┴──────────┐ │
│                                        │                                   │ │
│                                        ▼                                   ▼ │
│                              ┌──────────────┐                   ┌──────────┐│
│                              │ APPROVED     │                   │ TIMEOUT  ││
│                              └──────┬───────┘                   │ (30 min) ││
│                                     │                           └────┬─────┘│
│                                     ▼                                │      │
│                           ┌──────────────────┐                       │      │
│                           │ Execute Action   │                       │      │
│                           │ with Audit Log   │                       │      │
│                           └──────────────────┘                       │      │
│                                                                      ▼      │
│                                                           ┌──────────────┐  │
│                                                           │ Escalate to  │  │
│                                                           │ Management   │  │
│                                                           └──────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 6.2 Approval Notification

```python
"""
Approval Notification Handler
Sends approval requests through multiple channels
"""

import json
import boto3
from typing import Dict, Any, List

slack = boto3.client('secretsmanager')
sns = boto3.client('sns')


def send_approval_notification(approval_id: str, action_type: str, target: str,
                              instance_info: dict, reason: str, evidence: List[str],
                              approvers: List[dict]):
    """Send approval request through multiple channels"""
    
    # Format Slack message
    slack_message = {
        'blocks': [
            {
                'type': 'header',
                'text': {'type': 'plain_text', 'text': '🔐 Approval Required: Auto-Remediation'}
            },
            {
                'type': 'section',
                'fields': [
                    {'type': 'mrkdwn', 'text': f"*Action:*\n{action_type}"},
                    {'type': 'mrkdwn', 'text': f"*Target:*\n`{target}`"},
                    {'type': 'mrkdwn', 'text': f"*Account:*\n{instance_info.get('account_id')}"},
                    {'type': 'mrkdwn', 'text': f"*Environment:*\n{instance_info.get('environment', 'Unknown')}"}
                ]
            },
            {
                'type': 'section',
                'text': {
                    'type': 'mrkdwn',
                    'text': f"*Reason:*\n{reason}"
                }
            },
            {
                'type': 'context',
                'elements': [
                    {'type': 'mrkdwn', 'text': f"Approval ID: `{approval_id}` | Expires in 30 minutes"}
                ]
            },
            {
                'type': 'actions',
                'elements': [
                    {
                        'type': 'button',
                        'text': {'type': 'plain_text', 'text': '✅ Approve'},
                        'style': 'primary',
                        'action_id': 'approve_action',
                        'value': approval_id,
                        'confirm': {
                            'title': {'type': 'plain_text', 'text': 'Confirm Approval'},
                            'text': {'type': 'mrkdwn', 'text': f"Approve {action_type} on `{target}`?"},
                            'confirm': {'type': 'plain_text', 'text': 'Approve'},
                            'deny': {'type': 'plain_text', 'text': 'Cancel'}
                        }
                    },
                    {
                        'type': 'button',
                        'text': {'type': 'plain_text', 'text': '❌ Deny'},
                        'style': 'danger',
                        'action_id': 'deny_action',
                        'value': approval_id
                    },
                    {
                        'type': 'button',
                        'text': {'type': 'plain_text', 'text': '🔍 View Details'},
                        'action_id': 'view_details',
                        'value': approval_id
                    }
                ]
            }
        ]
    }
    
    # Send to Slack
    send_slack_message(get_approval_channel(), slack_message)
    
    # Send to SNS (for email, PagerDuty)
    sns.publish(
        TopicArn=os.environ['APPROVAL_TOPIC'],
        Subject=f'Approval Required: {action_type} on {target}',
        Message=json.dumps({
            'approval_id': approval_id,
            'action_type': action_type,
            'target': target,
            'instance_info': instance_info,
            'reason': reason,
            'evidence': evidence,
            'approve_url': f"https://patching.example.com/approve/{approval_id}",
            'deny_url': f"https://patching.example.com/deny/{approval_id}"
        }),
        MessageAttributes={
            'action': {'DataType': 'String', 'StringValue': 'approval_request'},
            'severity': {'DataType': 'String', 'StringValue': 'high'}
        }
    )
```

---

## 7. System Prompt

```text
You are an Auto-Remediation Agent for the EC2 Patching Platform. Your role is to
automatically recover from common patching failures when safe to do so, and to
escalate to humans when automated remediation is not appropriate.

## CRITICAL SAFETY RULES

1. **NEVER** perform actions that could:
   - Terminate instances
   - Delete volumes or data
   - Modify IAM permissions
   - Change security groups (except in pre-approved emergency scenarios)

2. **ALWAYS** operate within defined limits:
   - Maximum 5 instances per autonomous action
   - Rate limits per action type
   - Approval requirements for Tier 3 actions

3. **WHEN IN DOUBT**, escalate to a human operator.

## Your Capabilities

### Tier 1 Actions (Autonomous)
- Restart SSM agent on single instance
- Clear temp files on single instance
- Retry scan operation

### Tier 2 Actions (Threshold-Based)
- Retry failed patch installation (auto up to 3, then approval)
- Clear package manager cache
- Batch SSM agent restart (approval for >1)

### Tier 3 Actions (Always Approval)
- Force stop/start instance
- Rollback patches
- Emergency reboot

### Tier 4 Actions (PROHIBITED)
- Terminate instance
- Delete volumes
- Modify IAM

## Decision Framework

When encountering a failure:

1. **Identify** the failure type from error message/pattern
2. **Assess** if automated remediation is appropriate:
   - Is the failure a known recoverable type?
   - How many instances are affected?
   - What is the blast radius of the action?
3. **Check** rate limits and approval thresholds
4. **Execute** if allowed, or request approval if required
5. **Verify** the outcome and log everything
6. **Escalate** if remediation fails or is not possible

## Response Format

When taking action:
```
🔧 REMEDIATION ACTION

Action: [action type]
Target: [instance(s)]
Reason: [why this action]
Risk Level: [tier 1/2/3]
Status: [executed/pending_approval/denied]

[If executed]
Result: [success/failure]
Next Steps: [verification/escalation if needed]
```

When escalating:
```
⚠️ ESCALATION REQUIRED

Issue: [description]
Affected: [instances]
Attempted: [what was tried]
Recommendation: [suggested manual action]
Ticket: [escalation ticket ID]
```

## Logging Requirements

Every action MUST be logged with:
- Timestamp
- Action type
- Target resources
- Triggering condition
- Approval chain (if applicable)
- Pre-action state
- Post-action state
- Outcome
```

---

## 8. IAM Permissions

```yaml
AutoRemediationAgentRole:
  Type: AWS::IAM::Role
  Properties:
    RoleName: !Sub '${NamePrefix}-${Environment}-auto-remediation-role'
    AssumeRolePolicyDocument:
      Version: '2012-10-17'
      Statement:
        - Effect: Allow
          Principal:
            Service: bedrock.amazonaws.com
          Action: sts:AssumeRole
    Policies:
      - PolicyName: AutoRemediationPolicy
        PolicyDocument:
          Version: '2012-10-17'
          Statement:
            # SSM Command Execution (limited documents)
            - Effect: Allow
              Action:
                - ssm:SendCommand
                - ssm:GetCommandInvocation
              Resource:
                - !Sub 'arn:aws:ssm:${AWS::Region}::document/AWS-RunShellScript'
                - !Sub 'arn:aws:ssm:${AWS::Region}::document/AWS-RunPowerShellScript'
                - !Sub 'arn:aws:ssm:${AWS::Region}::document/AWS-RunPatchBaseline'
              Condition:
                StringEquals:
                  'aws:ResourceTag/ManagedByPatching': 'true'
            
            # EC2 Stop/Start (requires tag)
            - Effect: Allow
              Action:
                - ec2:StopInstances
                - ec2:StartInstances
              Resource: '*'
              Condition:
                StringEquals:
                  'aws:ResourceTag/AutoRemediationEnabled': 'true'
            
            # EC2 Read (for state capture)
            - Effect: Allow
              Action:
                - ec2:DescribeInstances
                - ec2:DescribeInstanceStatus
              Resource: '*'
            
            # DynamoDB (audit, approvals, rate limits)
            - Effect: Allow
              Action:
                - dynamodb:PutItem
                - dynamodb:GetItem
                - dynamodb:Query
                - dynamodb:UpdateItem
              Resource:
                - !Sub 'arn:aws:dynamodb:${AWS::Region}:${AWS::AccountId}:table/${AuditTable}'
                - !Sub 'arn:aws:dynamodb:${AWS::Region}:${AWS::AccountId}:table/${ApprovalsTable}'
                - !Sub 'arn:aws:dynamodb:${AWS::Region}:${AWS::AccountId}:table/${RateLimitTable}'
            
            # SNS (escalation, approvals)
            - Effect: Allow
              Action:
                - sns:Publish
              Resource:
                - !Sub 'arn:aws:sns:${AWS::Region}:${AWS::AccountId}:${NamePrefix}-*'
            
            # EXPLICIT DENY for dangerous actions
            - Effect: Deny
              Action:
                - ec2:TerminateInstances
                - ec2:DeleteVolume
                - ec2:DeleteSnapshot
                - iam:*
                - organizations:*
              Resource: '*'

  # Additional explicit boundary
  PermissionsBoundary: !Ref AutoRemediationBoundary

AutoRemediationBoundary:
  Type: AWS::IAM::ManagedPolicy
  Properties:
    ManagedPolicyName: !Sub '${NamePrefix}-auto-remediation-boundary'
    Description: 'Permission boundary for auto-remediation - prevents dangerous actions'
    PolicyDocument:
      Version: '2012-10-17'
      Statement:
        - Effect: Deny
          Action:
            - ec2:TerminateInstances
            - ec2:DeleteVolume
            - ec2:DeleteSnapshot
            - ec2:ModifyInstanceAttribute
            - ec2:CreateSecurityGroup
            - ec2:DeleteSecurityGroup
            - ec2:AuthorizeSecurityGroupIngress
            - ec2:RevokeSecurityGroupIngress
            - iam:*
            - organizations:*
            - sts:AssumeRole
          Resource: '*'
        - Effect: Allow
          Action: '*'
          Resource: '*'
```

---

## 9. Sample Conversations

### 9.1 Autonomous Recovery

**Trigger:** SSM agent timeout detected on i-0123456789abcdef0

**Agent Response:**
```
🔧 REMEDIATION ACTION

Action: restart_ssm_agent
Target: i-0123456789abcdef0
Reason: SSM agent timeout during patch scan (error: InvocationDoesNotExist)
Risk Level: Tier 1 (Autonomous)
Status: ✅ Executed

Result: SUCCESS
Command ID: cmd-0a1b2c3d4e5f6g7h8
Agent Status: Restarted successfully

Verification:
• SSM agent responding: Yes
• Instance reachable: Yes
• Ready for retry: Yes

Next Steps:
The patch scan will be automatically retried in 2 minutes.
```

### 9.2 Approval Required

**Trigger:** Instance i-0987654321fedcba0 hung during reboot for 15 minutes

**Agent Response:**
```
🔐 APPROVAL REQUIRED

Action: force_stop_start
Target: i-0987654321fedcba0 (prod-api-server-3)
Account: 123456789012 (Production)
Environment: production

Reason: Instance has been unresponsive for 15 minutes after reboot.
SSM agent not responding. EC2 status checks failing.

Attempted Remediations:
1. ❌ SSM agent restart - Failed (instance unreachable)
2. ❌ Wait for recovery (15 min) - No improvement

Risk Assessment:
• This is a production instance
• Force stop may interrupt active connections
• Application team notified

Approval Request: approval-abc123def456
Approvers Notified: @oncall-platform, @prod-approvers
Expires: 30 minutes

[Approve] [Deny] [View Details]
```

### 9.3 Escalation

**Trigger:** Multiple instances failing with unknown error pattern

**Agent Response:**
```
⚠️ ESCALATION REQUIRED

I've detected an unusual failure pattern that I cannot automatically remediate.

Issue: Package dependency conflict during patch installation
Affected: 8 instances across 2 accounts
Error: "unmet dependencies: libc6 (>= 2.28) but 2.27-3ubuntu1 is installed"

Why Escalation:
• This error requires manual package resolution
• Multiple instances affected
• Not a known auto-recoverable pattern
• Risk of broader impact if wrong action taken

Investigation Summary:
• All affected instances are Ubuntu 18.04
• Third-party repository may be conflicting
• Last successful patch: 45 days ago

Recommended Manual Actions:
1. SSH to affected instance
2. Run: sudo apt-get update --fix-missing
3. Check third-party repos: /etc/apt/sources.list.d/
4. If needed: sudo dpkg --configure -a

Escalation Ticket: PATCH-2024-0542
PagerDuty: Not paged (severity: high, not critical)
Slack: Posted to #patching-alerts
```

---

## 10. Monitoring and Observability

### 10.1 Agent Metrics

```python
def publish_remediation_metrics(action: str, status: str, duration_ms: int):
    """Publish remediation agent metrics"""
    
    cloudwatch.put_metric_data(
        Namespace='EC2Patching/Agents/AutoRemediation',
        MetricData=[
            {
                'MetricName': 'ActionsExecuted',
                'Dimensions': [
                    {'Name': 'ActionType', 'Value': action},
                    {'Name': 'Status', 'Value': status}
                ],
                'Value': 1,
                'Unit': 'Count'
            },
            {
                'MetricName': 'ActionDuration',
                'Dimensions': [
                    {'Name': 'ActionType', 'Value': action}
                ],
                'Value': duration_ms,
                'Unit': 'Milliseconds'
            }
        ]
    )
```

### 10.2 Alarms

```yaml
RemediationAnomalyAlarm:
  Type: AWS::CloudWatch::Alarm
  Properties:
    AlarmName: !Sub '${NamePrefix}-remediation-anomaly'
    AlarmDescription: 'Unusual number of remediation actions'
    MetricName: ActionsExecuted
    Namespace: EC2Patching/Agents/AutoRemediation
    Statistic: Sum
    Period: 300
    EvaluationPeriods: 1
    Threshold: 20
    ComparisonOperator: GreaterThanThreshold
    TreatMissingData: notBreaching
    AlarmActions:
      - !Ref AlertTopic

RemediationFailureAlarm:
  Type: AWS::CloudWatch::Alarm
  Properties:
    AlarmName: !Sub '${NamePrefix}-remediation-failures'
    AlarmDescription: 'High remediation failure rate'
    Metrics:
      - Id: failures
        MetricStat:
          Metric:
            Namespace: EC2Patching/Agents/AutoRemediation
            MetricName: ActionsExecuted
            Dimensions:
              - Name: Status
                Value: FAILED
          Period: 300
          Stat: Sum
        ReturnData: false
      - Id: total
        MetricStat:
          Metric:
            Namespace: EC2Patching/Agents/AutoRemediation
            MetricName: ActionsExecuted
          Period: 300
          Stat: Sum
        ReturnData: false
      - Id: failure_rate
        Expression: 'failures / total * 100'
        ReturnData: true
    EvaluationPeriods: 2
    Threshold: 30
    ComparisonOperator: GreaterThanThreshold
```

---

*This completes the 6-Agent technical design series for the EC2 Patching Platform's multi-agent system.*
