# Agent 4: ChatOps & Conversational Interface Agent - Technical Design

## Document Information
| Attribute | Value |
|-----------|-------|
| Version | 1.0 |
| Last Updated | January 14, 2026 |
| Status | Draft |
| Owner | Platform Engineering |
| Agent ID | `chatops-agent` |

---

## 1. Executive Summary

The **ChatOps Agent** provides a conversational interface to the EC2 Patching Platform through popular messaging platforms (Slack, Microsoft Teams). It enables operations teams to query patch status, receive notifications, and execute approved runbook operations directly from their collaboration tools.

### 1.1 Key Capabilities

| Capability | Description | Priority |
|------------|-------------|----------|
| Status Queries | Real-time patch execution status | P0 |
| Interactive Notifications | Rich, actionable notifications | P0 |
| Runbook Operations | Execute pre-approved operations | P0 |
| Natural Language Search | Find instances, executions, failures | P1 |
| On-Call Assistance | Help on-call engineers investigate issues | P1 |
| Approval Workflows | Request and grant operation approvals | P2 |

### 1.2 Supported Platforms

| Platform | Integration Method | Features |
|----------|-------------------|----------|
| Slack | Slack App + Events API | Slash commands, Block Kit, modals, threads |
| Microsoft Teams | Bot Framework + Adaptive Cards | Cards, task modules, @mentions |
| Discord | Webhook + Bot | Embeds, slash commands (future) |
| CLI | Direct API | Full access (authenticated) |

---

## 2. Architecture

```
┌──────────────────────────────────────────────────────────────────────────────────────┐
│                          CHATOPS AGENT ARCHITECTURE                                   │
│                                                                                       │
│  ┌─────────────────────────────────────────────────────────────────────────────────┐ │
│  │                              AGENT CORE                                          │ │
│  │  Model: anthropic.claude-3-sonnet-20240229-v1:0                                 │ │
│  │  Temperature: 0.15 (precise, consistent responses)                              │ │
│  │  Max Tokens: 2048 (concise chat responses)                                      │ │
│  └─────────────────────────────────────────────────────────────────────────────────┘ │
│                                        │                                              │
│         ┌──────────────────────────────┼──────────────────────────────┐               │
│         │                              │                              │               │
│         ▼                              ▼                              ▼               │
│  ┌─────────────────┐     ┌────────────────────────┐    ┌─────────────────────────┐  │
│  │ KNOWLEDGE BASES │     │     ACTION GROUPS       │    │    CHAT ADAPTERS        │  │
│  │                 │     │                         │    │                         │  │
│  │ • runbooks      │     │ • Status Queries        │    │ • Slack Adapter         │  │
│  │ • operational-docs│   │ • Instance Lookup       │    │ • Teams Adapter         │  │
│  │ • troubleshoot-kb│    │ • Runbook Actions       │    │ • CLI Adapter           │  │
│  └─────────────────┘     │ • Notification Manager  │    │ • Response Formatter    │  │
│                          └────────────────────────┘    └─────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────────────────────┘
                                        │
                                        ▼
┌──────────────────────────────────────────────────────────────────────────────────────┐
│                          MESSAGE PROCESSING LAYER                                     │
│                                                                                       │
│  ┌─────────────────────────────────────────────────────────────────────────────────┐ │
│  │                              API GATEWAY                                         │ │
│  │                                                                                  │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐ │ │
│  │  │ /slack       │  │ /teams       │  │ /api/chat    │  │ /webhook/notify      │ │ │
│  │  │ webhook      │  │ webhook      │  │ (CLI/API)    │  │ (outbound)           │ │ │
│  │  └──────────────┘  └──────────────┘  └──────────────┘  └──────────────────────┘ │ │
│  │                                                                                  │ │
│  └─────────────────────────────────────────────────────────────────────────────────┘ │
│                                        │                                              │
│  ┌─────────────────────────────────────────────────────────────────────────────────┐ │
│  │                         MESSAGE ROUTER (Lambda)                                  │ │
│  │                                                                                  │ │
│  │  • Verify Slack/Teams signatures                                                │ │
│  │  • Parse platform-specific message formats                                      │ │
│  │  • Route to Agent or direct handlers                                            │ │
│  │  • Format responses for platform                                                │ │
│  │  • Handle conversation threading                                                │ │
│  └─────────────────────────────────────────────────────────────────────────────────┘ │
│                                                                                       │
│  ┌─────────────────────────────────────────────────────────────────────────────────┐ │
│  │                        SESSION MANAGEMENT (DynamoDB)                             │ │
│  │                                                                                  │ │
│  │  • User context and preferences                                                 │ │
│  │  • Conversation history (per thread)                                            │ │
│  │  • Pending approvals                                                            │ │
│  │  • Rate limiting state                                                          │ │
│  └─────────────────────────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Slack Integration

### 3.1 Slack App Manifest

```yaml
display_information:
  name: EC2 Patching Bot
  description: Chat interface for EC2 Patching Platform
  background_color: "#2C5F2D"
  long_description: |
    Query patch status, receive notifications, and execute runbook operations
    for the EC2 Patching Platform directly from Slack.

features:
  app_home:
    home_tab_enabled: true
    messages_tab_enabled: true
  bot_user:
    display_name: Patching Bot
    always_online: true
  slash_commands:
    - command: /patch-status
      url: https://api.patching.example.com/slack/commands
      description: Get current patching status
      usage_hint: "[execution-id] [--account <id>] [--region <region>]"
    - command: /patch-find
      url: https://api.patching.example.com/slack/commands
      description: Find instances or executions
      usage_hint: "<instance-id|tag:value|account-id>"
    - command: /patch-runbook
      url: https://api.patching.example.com/slack/commands
      description: Execute a runbook operation
      usage_hint: "<runbook-name> [--target <instance-id>]"

oauth_config:
  scopes:
    bot:
      - app_mentions:read
      - chat:write
      - commands
      - im:history
      - im:write
      - reactions:write
      - users:read
      - files:write

settings:
  event_subscriptions:
    request_url: https://api.patching.example.com/slack/events
    bot_events:
      - app_mention
      - message.im
  interactivity:
    is_enabled: true
    request_url: https://api.patching.example.com/slack/interactions
```

### 3.2 Slack Message Handler

```python
"""
Slack Message Handler
Processes incoming Slack messages and routes to ChatOps Agent
"""

import json
import boto3
import hashlib
import hmac
import time
from typing import Dict, Any, Optional
from slack_sdk import WebClient
from slack_sdk.signature import SignatureVerifier

bedrock_agent = boto3.client('bedrock-agent-runtime')
dynamodb = boto3.resource('dynamodb')
sessions_table = dynamodb.Table(os.environ['SESSIONS_TABLE'])

SLACK_SIGNING_SECRET = os.environ['SLACK_SIGNING_SECRET']
SLACK_BOT_TOKEN = os.environ['SLACK_BOT_TOKEN']
AGENT_ID = os.environ['CHATOPS_AGENT_ID']
AGENT_ALIAS_ID = os.environ['CHATOPS_AGENT_ALIAS_ID']

slack_client = WebClient(token=SLACK_BOT_TOKEN)
signature_verifier = SignatureVerifier(SLACK_SIGNING_SECRET)


def handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """Process Slack webhook events"""
    
    # Verify Slack signature
    if not verify_slack_signature(event):
        return {'statusCode': 401, 'body': 'Invalid signature'}
    
    body = json.loads(event.get('body', '{}'))
    
    # Handle URL verification challenge
    if body.get('type') == 'url_verification':
        return {'statusCode': 200, 'body': body['challenge']}
    
    # Handle events
    if body.get('type') == 'event_callback':
        slack_event = body.get('event', {})
        event_type = slack_event.get('type')
        
        if event_type in ['message', 'app_mention']:
            return handle_message(slack_event, body)
    
    # Handle slash commands
    if 'command' in body:
        return handle_slash_command(body)
    
    # Handle interactive components
    if 'payload' in body:
        payload = json.loads(body['payload'])
        return handle_interaction(payload)
    
    return {'statusCode': 200, 'body': 'OK'}


def handle_message(event: Dict, body: Dict) -> Dict:
    """Handle incoming message or app mention"""
    
    # Ignore bot messages
    if event.get('bot_id'):
        return {'statusCode': 200, 'body': 'OK'}
    
    user_id = event.get('user')
    channel_id = event.get('channel')
    thread_ts = event.get('thread_ts') or event.get('ts')
    text = event.get('text', '').strip()
    
    # Remove bot mention from text
    text = remove_bot_mention(text)
    
    if not text:
        return {'statusCode': 200, 'body': 'OK'}
    
    # Get or create session
    session_id = get_or_create_session(user_id, channel_id, thread_ts)
    
    # Add thinking indicator
    slack_client.reactions_add(
        channel=channel_id,
        timestamp=event.get('ts'),
        name='hourglass_flowing_sand'
    )
    
    try:
        # Invoke ChatOps Agent
        response = bedrock_agent.invoke_agent(
            agentId=AGENT_ID,
            agentAliasId=AGENT_ALIAS_ID,
            sessionId=session_id,
            inputText=text,
            sessionState={
                'sessionAttributes': {
                    'platform': 'slack',
                    'user_id': user_id,
                    'channel_id': channel_id
                }
            }
        )
        
        # Process agent response
        agent_response = process_agent_response(response)
        
        # Format for Slack
        blocks = format_slack_response(agent_response)
        
        # Send response
        slack_client.chat_postMessage(
            channel=channel_id,
            thread_ts=thread_ts,
            blocks=blocks,
            text=agent_response.get('text', 'Response from Patching Bot')
        )
        
        # Update reaction
        slack_client.reactions_remove(
            channel=channel_id,
            timestamp=event.get('ts'),
            name='hourglass_flowing_sand'
        )
        slack_client.reactions_add(
            channel=channel_id,
            timestamp=event.get('ts'),
            name='white_check_mark'
        )
        
    except Exception as e:
        # Error response
        slack_client.chat_postMessage(
            channel=channel_id,
            thread_ts=thread_ts,
            text=f"❌ Sorry, I encountered an error: {str(e)}"
        )
        slack_client.reactions_add(
            channel=channel_id,
            timestamp=event.get('ts'),
            name='x'
        )
    
    return {'statusCode': 200, 'body': 'OK'}


def handle_slash_command(command: Dict) -> Dict:
    """Handle slash commands"""
    
    command_name = command.get('command', '').replace('/', '')
    text = command.get('text', '')
    user_id = command.get('user_id')
    channel_id = command.get('channel_id')
    response_url = command.get('response_url')
    
    # Map commands to agent queries
    queries = {
        'patch-status': f"Get the current patch execution status. {text}",
        'patch-find': f"Find instances or executions matching: {text}",
        'patch-runbook': f"Execute runbook operation: {text}"
    }
    
    query = queries.get(command_name, text)
    
    # Acknowledge immediately (Slack 3-second timeout)
    acknowledge_response = {
        'statusCode': 200,
        'body': json.dumps({'response_type': 'ephemeral', 'text': '🔄 Processing your request...'})
    }
    
    # Process asynchronously
    invoke_async_handler(query, user_id, channel_id, response_url)
    
    return acknowledge_response


def format_slack_response(response: Dict) -> list:
    """Format agent response as Slack Block Kit blocks"""
    
    blocks = []
    
    # Header if present
    if response.get('title'):
        blocks.append({
            'type': 'header',
            'text': {'type': 'plain_text', 'text': response['title']}
        })
    
    # Main content
    if response.get('text'):
        blocks.append({
            'type': 'section',
            'text': {'type': 'mrkdwn', 'text': response['text'][:3000]}  # Slack limit
        })
    
    # Table data as fields
    if response.get('table'):
        for row in response['table'][:10]:  # Limit rows
            blocks.append({
                'type': 'section',
                'fields': [
                    {'type': 'mrkdwn', 'text': f"*{k}:*\n{v}"}
                    for k, v in list(row.items())[:10]  # Limit fields per row
                ]
            })
    
    # Actions if present
    if response.get('actions'):
        blocks.append({
            'type': 'actions',
            'elements': [
                {
                    'type': 'button',
                    'text': {'type': 'plain_text', 'text': action['label']},
                    'action_id': action['id'],
                    'value': action.get('value', action['id']),
                    'style': action.get('style', 'primary') if action.get('primary') else None
                }
                for action in response['actions'][:5]  # Limit buttons
            ]
        })
    
    # Divider before context
    if response.get('footer'):
        blocks.append({'type': 'divider'})
        blocks.append({
            'type': 'context',
            'elements': [{'type': 'mrkdwn', 'text': response['footer']}]
        })
    
    return blocks
```

---

## 4. Action Groups (Tools)

### 4.1 Action Group: `status-queries`

#### 4.1.1 Tool: `get_execution_status`

**Purpose:** Get current status of patching execution

**OpenAPI Schema:**
```yaml
openapi: 3.0.0
info:
  title: ChatOps Status API
  version: 1.0.0

paths:
  /execution-status:
    post:
      operationId: getExecutionStatus
      summary: Get patching execution status
      description: |
        Returns the current status of a patching execution or a summary
        of recent/active executions.
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              properties:
                executionId:
                  type: string
                  description: Specific execution ID to query
                scope:
                  type: string
                  enum: [active, recent, all]
                  default: active
                  description: Scope of status query
                accountId:
                  type: string
                  description: Filter by account
                region:
                  type: string
                  description: Filter by region
                limit:
                  type: integer
                  default: 5
                  maximum: 20
      responses:
        '200':
          description: Execution status
          content:
            application/json:
              schema:
                type: object
                properties:
                  executions:
                    type: array
                    items:
                      type: object
                      properties:
                        executionId:
                          type: string
                        status:
                          type: string
                          enum: [RUNNING, SUCCEEDED, FAILED, TIMED_OUT, ABORTED]
                        startTime:
                          type: string
                        endTime:
                          type: string
                        progress:
                          type: object
                          properties:
                            total:
                              type: integer
                            completed:
                              type: integer
                            failed:
                              type: integer
                            pending:
                              type: integer
                            percentComplete:
                              type: number
                        waves:
                          type: array
                          items:
                            type: object
                            properties:
                              waveIndex:
                                type: integer
                              status:
                                type: string
                              accounts:
                                type: integer
                              instances:
                                type: integer
                  summary:
                    type: object
                    properties:
                      activeExecutions:
                        type: integer
                      successRate:
                        type: number
                      lastExecution:
                        type: string
```

**Lambda Handler:**
```python
"""
Execution Status Handler for ChatOps
Returns concise status suitable for chat responses
"""

import json
import boto3
from datetime import datetime, timedelta
from typing import Dict, Any, List

sfn = boto3.client('stepfunctions')
dynamodb = boto3.resource('dynamodb')
runs_table = dynamodb.Table(os.environ['PATCH_RUNS_TABLE'])

STATE_MACHINE_ARN = os.environ['STATE_MACHINE_ARN']


def handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """Get execution status for ChatOps"""
    
    params = event.get('requestBody', {}).get('content', {}).get('application/json', {})
    
    execution_id = params.get('executionId')
    scope = params.get('scope', 'active')
    account_id = params.get('accountId')
    region = params.get('region')
    limit = min(params.get('limit', 5), 20)
    
    executions = []
    
    if execution_id:
        # Get specific execution
        execution = get_execution_details(execution_id)
        if execution:
            executions.append(execution)
    else:
        # Get executions based on scope
        if scope == 'active':
            executions = get_active_executions(account_id, region, limit)
        elif scope == 'recent':
            executions = get_recent_executions(account_id, region, limit)
        else:
            executions = get_all_executions(account_id, region, limit)
    
    # Calculate summary
    summary = calculate_summary(executions)
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'executions': executions,
            'summary': summary
        })
    }


def get_active_executions(account_id: str, region: str, limit: int) -> List[dict]:
    """Get currently running executions"""
    
    response = sfn.list_executions(
        stateMachineArn=STATE_MACHINE_ARN,
        statusFilter='RUNNING',
        maxResults=limit
    )
    
    executions = []
    for exec_info in response.get('executions', []):
        exec_detail = get_execution_details(exec_info['executionArn'].split(':')[-1])
        if exec_detail:
            # Apply filters
            if account_id and not matches_account(exec_detail, account_id):
                continue
            if region and not matches_region(exec_detail, region):
                continue
            executions.append(exec_detail)
    
    return executions[:limit]


def get_execution_details(execution_id: str) -> dict:
    """Get detailed status for an execution"""
    
    # Query DynamoDB for execution record
    response = runs_table.query(
        KeyConditionExpression='scope = :scope AND id = :id',
        ExpressionAttributeValues={
            ':scope': 'execution',
            ':id': execution_id
        }
    )
    
    if not response['Items']:
        return None
    
    item = response['Items'][0]
    metadata = item.get('metadata', {})
    
    # Get progress from waves
    waves = get_wave_progress(execution_id)
    
    total_instances = sum(w.get('instances', 0) for w in waves)
    completed = sum(w.get('completed', 0) for w in waves)
    failed = sum(w.get('failed', 0) for w in waves)
    
    return {
        'executionId': execution_id,
        'status': item.get('status', 'UNKNOWN'),
        'startTime': item.get('start_time'),
        'endTime': item.get('end_time'),
        'progress': {
            'total': total_instances,
            'completed': completed,
            'failed': failed,
            'pending': total_instances - completed - failed,
            'percentComplete': round((completed + failed) / total_instances * 100, 1) if total_instances else 0
        },
        'waves': waves
    }


def format_for_chat(executions: List[dict]) -> str:
    """Format execution status for chat display"""
    
    if not executions:
        return "No matching executions found."
    
    lines = []
    
    for exec_info in executions:
        status_emoji = {
            'RUNNING': '🔄',
            'SUCCEEDED': '✅',
            'FAILED': '❌',
            'TIMED_OUT': '⏰',
            'ABORTED': '⛔'
        }.get(exec_info['status'], '❓')
        
        progress = exec_info.get('progress', {})
        percent = progress.get('percentComplete', 0)
        
        lines.append(
            f"{status_emoji} `{exec_info['executionId'][:12]}...` - "
            f"{exec_info['status']} ({percent:.0f}% complete)"
        )
        
        if exec_info['status'] == 'RUNNING':
            lines.append(
                f"   └ {progress.get('completed', 0)}/{progress.get('total', 0)} instances, "
                f"{progress.get('failed', 0)} failed"
            )
    
    return '\n'.join(lines)
```

#### 4.1.2 Tool: `find_instance`

**Purpose:** Find instances by ID, tag, or account

**OpenAPI Schema:**
```yaml
paths:
  /find-instance:
    post:
      operationId: findInstance
      summary: Find instances by various criteria
      description: |
        Searches for EC2 instances by instance ID, tag values,
        account, or other attributes.
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              properties:
                query:
                  type: string
                  description: Search query (instance ID, tag value, etc.)
                searchType:
                  type: string
                  enum: [instance_id, tag, account, name, any]
                  default: any
                includeStatus:
                  type: boolean
                  default: true
                  description: Include recent patch status
                limit:
                  type: integer
                  default: 10
              required:
                - query
      responses:
        '200':
          description: Found instances
          content:
            application/json:
              schema:
                type: object
                properties:
                  instances:
                    type: array
                    items:
                      type: object
                      properties:
                        instanceId:
                          type: string
                        accountId:
                          type: string
                        region:
                          type: string
                        name:
                          type: string
                        platform:
                          type: string
                        lastPatchStatus:
                          type: string
                        lastPatchDate:
                          type: string
                  totalMatches:
                    type: integer
```

#### 4.1.3 Tool: `get_failure_summary`

**Purpose:** Get summary of recent failures

**OpenAPI Schema:**
```yaml
paths:
  /failure-summary:
    post:
      operationId: getFailureSummary
      summary: Get summary of recent patching failures
      description: |
        Returns a summary of recent patching failures, grouped by
        error type, account, or other dimensions.
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              properties:
                timeRange:
                  type: string
                  enum: [1h, 6h, 24h, 7d]
                  default: 24h
                groupBy:
                  type: string
                  enum: [error_type, account, region, instance]
                  default: error_type
                executionId:
                  type: string
                  description: Limit to specific execution
                limit:
                  type: integer
                  default: 10
      responses:
        '200':
          description: Failure summary
          content:
            application/json:
              schema:
                type: object
                properties:
                  totalFailures:
                    type: integer
                  groups:
                    type: array
                    items:
                      type: object
                      properties:
                        groupValue:
                          type: string
                        count:
                          type: integer
                        percentage:
                          type: number
                        examples:
                          type: array
                          items:
                            type: string
                  topErrors:
                    type: array
                    items:
                      type: object
```

### 4.2 Action Group: `runbook-operations`

#### 4.2.1 Tool: `list_runbooks`

**Purpose:** List available runbook operations

**OpenAPI Schema:**
```yaml
paths:
  /list-runbooks:
    post:
      operationId: listRunbooks
      summary: List available runbook operations
      description: |
        Returns a list of runbook operations available for execution
        through ChatOps, with required permissions noted.
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              properties:
                category:
                  type: string
                  enum: [all, diagnostic, remediation, status]
                  default: all
                requiredApproval:
                  type: boolean
                  description: Filter by approval requirement
      responses:
        '200':
          description: Available runbooks
          content:
            application/json:
              schema:
                type: object
                properties:
                  runbooks:
                    type: array
                    items:
                      type: object
                      properties:
                        id:
                          type: string
                        name:
                          type: string
                        description:
                          type: string
                        category:
                          type: string
                        requiresApproval:
                          type: boolean
                        requiredRole:
                          type: string
                        parameters:
                          type: array
                          items:
                            type: object
```

#### 4.2.2 Tool: `execute_runbook`

**Purpose:** Execute an approved runbook operation

**OpenAPI Schema:**
```yaml
paths:
  /execute-runbook:
    post:
      operationId: executeRunbook
      summary: Execute a runbook operation
      description: |
        Executes an approved runbook operation. Some operations require
        additional approval before execution.
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              properties:
                runbookId:
                  type: string
                  description: ID of the runbook to execute
                parameters:
                  type: object
                  description: Parameters for the runbook
                targetInstanceId:
                  type: string
                  description: Target instance (if applicable)
                targetAccountId:
                  type: string
                  description: Target account (if applicable)
                justification:
                  type: string
                  description: Reason for execution (required for some runbooks)
              required:
                - runbookId
      responses:
        '200':
          description: Execution result
          content:
            application/json:
              schema:
                type: object
                properties:
                  status:
                    type: string
                    enum: [executed, pending_approval, denied, error]
                  executionId:
                    type: string
                  message:
                    type: string
                  approvalRequired:
                    type: boolean
                  approvers:
                    type: array
                    items:
                      type: string
```

**Lambda Handler:**
```python
"""
Runbook Execution Handler
Executes approved runbook operations from ChatOps
"""

import json
import boto3
from datetime import datetime
from typing import Dict, Any

ssm = boto3.client('ssm')
dynamodb = boto3.resource('dynamodb')
sns = boto3.client('sns')

RUNBOOKS = {
    'check-ssm-agent': {
        'name': 'Check SSM Agent Status',
        'category': 'diagnostic',
        'description': 'Check if SSM agent is running on an instance',
        'requiresApproval': False,
        'ssmDocument': 'AWS-RunShellScript',
        'command': 'systemctl status amazon-ssm-agent || service amazon-ssm-agent status'
    },
    'restart-ssm-agent': {
        'name': 'Restart SSM Agent',
        'category': 'remediation',
        'description': 'Restart the SSM agent on an instance',
        'requiresApproval': True,
        'ssmDocument': 'AWS-RunShellScript',
        'command': 'systemctl restart amazon-ssm-agent || service amazon-ssm-agent restart'
    },
    'get-patch-log': {
        'name': 'Get Patch Log',
        'category': 'diagnostic',
        'description': 'Retrieve the last 100 lines of patch log',
        'requiresApproval': False,
        'ssmDocument': 'AWS-RunShellScript',
        'command': 'tail -100 /var/log/amazon/ssm/amazon-ssm-agent.log'
    },
    'check-disk-space': {
        'name': 'Check Disk Space',
        'category': 'diagnostic',
        'description': 'Check available disk space on instance',
        'requiresApproval': False,
        'ssmDocument': 'AWS-RunShellScript',
        'command': 'df -h'
    },
    'force-patch-scan': {
        'name': 'Force Patch Scan',
        'category': 'remediation',
        'description': 'Trigger an immediate patch compliance scan',
        'requiresApproval': True,
        'ssmDocument': 'AWS-RunPatchBaseline',
        'operation': 'Scan'
    }
}


def handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """Execute runbook operation"""
    
    params = event.get('requestBody', {}).get('content', {}).get('application/json', {})
    
    runbook_id = params.get('runbookId')
    target_instance = params.get('targetInstanceId')
    justification = params.get('justification', '')
    
    # Get user context from session
    session_attrs = event.get('sessionAttributes', {})
    user_id = session_attrs.get('user_id')
    platform = session_attrs.get('platform')
    
    # Validate runbook
    if runbook_id not in RUNBOOKS:
        return error_response(f"Unknown runbook: {runbook_id}")
    
    runbook = RUNBOOKS[runbook_id]
    
    # Check if approval is required
    if runbook['requiresApproval']:
        # Check for existing approval
        approval = check_approval(runbook_id, target_instance, user_id)
        
        if not approval:
            # Request approval
            approval_id = request_approval(runbook_id, target_instance, user_id, justification)
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'status': 'pending_approval',
                    'message': f"Approval requested for '{runbook['name']}'. An approver will be notified.",
                    'approvalRequired': True,
                    'approvers': get_approvers()
                })
            }
    
    # Execute the runbook
    try:
        execution_id = execute_ssm_runbook(runbook, target_instance)
        
        # Log execution
        log_execution(runbook_id, target_instance, user_id, execution_id)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'status': 'executed',
                'executionId': execution_id,
                'message': f"✅ Runbook '{runbook['name']}' executed successfully on {target_instance}",
                'approvalRequired': False
            })
        }
    
    except Exception as e:
        return error_response(str(e))


def execute_ssm_runbook(runbook: dict, instance_id: str) -> str:
    """Execute SSM document for runbook"""
    
    if runbook.get('command'):
        # Shell command runbook
        response = ssm.send_command(
            InstanceIds=[instance_id],
            DocumentName=runbook['ssmDocument'],
            Parameters={'commands': [runbook['command']]},
            TimeoutSeconds=120,
            Comment=f"ChatOps runbook: {runbook['name']}"
        )
    else:
        # Patch baseline runbook
        response = ssm.send_command(
            InstanceIds=[instance_id],
            DocumentName=runbook['ssmDocument'],
            Parameters={'Operation': [runbook.get('operation', 'Scan')]},
            TimeoutSeconds=300,
            Comment=f"ChatOps runbook: {runbook['name']}"
        )
    
    return response['Command']['CommandId']


def request_approval(runbook_id: str, instance_id: str, requester: str, 
                     justification: str) -> str:
    """Request approval for a runbook execution"""
    
    approval_id = f"approval-{datetime.utcnow().strftime('%Y%m%d%H%M%S')}"
    
    # Store pending approval
    approvals_table = dynamodb.Table(os.environ['APPROVALS_TABLE'])
    approvals_table.put_item(Item={
        'approval_id': approval_id,
        'runbook_id': runbook_id,
        'instance_id': instance_id,
        'requester': requester,
        'justification': justification,
        'status': 'pending',
        'requested_at': datetime.utcnow().isoformat(),
        'ttl': int((datetime.utcnow() + timedelta(hours=4)).timestamp())
    })
    
    # Notify approvers
    sns.publish(
        TopicArn=os.environ['APPROVAL_TOPIC'],
        Subject=f"Approval Required: {RUNBOOKS[runbook_id]['name']}",
        Message=json.dumps({
            'approval_id': approval_id,
            'runbook': RUNBOOKS[runbook_id]['name'],
            'instance': instance_id,
            'requester': requester,
            'justification': justification
        })
    )
    
    return approval_id
```

---

## 5. Interactive Notifications

### 5.1 Notification Templates

```python
"""
Slack Notification Templates
Rich, interactive notifications for patching events
"""

def execution_started_notification(execution_id: str, details: dict) -> dict:
    """Notification when patching execution starts"""
    
    return {
        'blocks': [
            {
                'type': 'header',
                'text': {'type': 'plain_text', 'text': '🚀 Patching Execution Started'}
            },
            {
                'type': 'section',
                'fields': [
                    {'type': 'mrkdwn', 'text': f"*Execution ID:*\n`{execution_id}`"},
                    {'type': 'mrkdwn', 'text': f"*Started:*\n{details['start_time']}"},
                    {'type': 'mrkdwn', 'text': f"*Instances:*\n{details['instance_count']}"},
                    {'type': 'mrkdwn', 'text': f"*Waves:*\n{details['wave_count']}"}
                ]
            },
            {
                'type': 'actions',
                'elements': [
                    {
                        'type': 'button',
                        'text': {'type': 'plain_text', 'text': '📊 View Progress'},
                        'action_id': 'view_progress',
                        'value': execution_id
                    },
                    {
                        'type': 'button',
                        'text': {'type': 'plain_text', 'text': '🔗 Open Console'},
                        'url': f"https://console.aws.amazon.com/states/home?region=us-east-1#/executions/details/{execution_id}"
                    }
                ]
            }
        ]
    }


def execution_completed_notification(execution_id: str, details: dict) -> dict:
    """Notification when patching execution completes"""
    
    status = details.get('status', 'UNKNOWN')
    emoji = {'SUCCEEDED': '✅', 'FAILED': '❌', 'PARTIAL': '⚠️'}.get(status, '❓')
    
    blocks = [
        {
            'type': 'header',
            'text': {'type': 'plain_text', 'text': f'{emoji} Patching Execution Completed'}
        },
        {
            'type': 'section',
            'fields': [
                {'type': 'mrkdwn', 'text': f"*Status:*\n{status}"},
                {'type': 'mrkdwn', 'text': f"*Duration:*\n{details['duration']}"},
                {'type': 'mrkdwn', 'text': f"*Success Rate:*\n{details['success_rate']:.1f}%"},
                {'type': 'mrkdwn', 'text': f"*Instances:*\n{details['success']}/{details['total']} succeeded"}
            ]
        }
    ]
    
    # Add failure summary if applicable
    if details.get('failed', 0) > 0:
        blocks.append({
            'type': 'section',
            'text': {
                'type': 'mrkdwn',
                'text': f"*Failed Instances ({details['failed']}):*\n" + 
                        '\n'.join(f"• `{i}`" for i in details.get('failed_instances', [])[:5])
            }
        })
        blocks.append({
            'type': 'actions',
            'elements': [
                {
                    'type': 'button',
                    'text': {'type': 'plain_text', 'text': '🔍 Investigate Failures'},
                    'action_id': 'investigate_failures',
                    'value': execution_id,
                    'style': 'danger'
                }
            ]
        })
    
    return {'blocks': blocks}


def failure_alert_notification(instance_id: str, error: dict) -> dict:
    """Alert notification for instance failure"""
    
    return {
        'blocks': [
            {
                'type': 'header',
                'text': {'type': 'plain_text', 'text': '⚠️ Instance Patch Failure'}
            },
            {
                'type': 'section',
                'fields': [
                    {'type': 'mrkdwn', 'text': f"*Instance:*\n`{instance_id}`"},
                    {'type': 'mrkdwn', 'text': f"*Account:*\n{error.get('account_id')}"},
                    {'type': 'mrkdwn', 'text': f"*Region:*\n{error.get('region')}"},
                    {'type': 'mrkdwn', 'text': f"*Error Type:*\n{error.get('error_type')}"}
                ]
            },
            {
                'type': 'section',
                'text': {
                    'type': 'mrkdwn',
                    'text': f"```{error.get('error_message', 'Unknown error')[:500]}```"
                }
            },
            {
                'type': 'actions',
                'elements': [
                    {
                        'type': 'button',
                        'text': {'type': 'plain_text', 'text': '🔧 Restart SSM Agent'},
                        'action_id': 'runbook_restart_ssm',
                        'value': instance_id,
                        'confirm': {
                            'title': {'type': 'plain_text', 'text': 'Confirm Action'},
                            'text': {'type': 'mrkdwn', 'text': f"Restart SSM agent on `{instance_id}`?"},
                            'confirm': {'type': 'plain_text', 'text': 'Restart'},
                            'deny': {'type': 'plain_text', 'text': 'Cancel'}
                        }
                    },
                    {
                        'type': 'button',
                        'text': {'type': 'plain_text', 'text': '📋 View Logs'},
                        'action_id': 'view_instance_logs',
                        'value': instance_id
                    },
                    {
                        'type': 'button',
                        'text': {'type': 'plain_text', 'text': '🤖 Analyze'},
                        'action_id': 'analyze_failure',
                        'value': instance_id
                    }
                ]
            }
        ]
    }
```

---

## 6. System Prompt

```text
You are a helpful ChatOps Agent for the EC2 Patching Platform. You provide a conversational
interface for operations teams to query patch status, investigate issues, and execute
approved runbook operations.

## Your Personality

- Be concise and action-oriented
- Use emojis appropriately for status indicators
- Format responses for easy scanning (tables, bullet points)
- Acknowledge requests promptly
- Ask clarifying questions when needed

## Capabilities

### Status Queries
- Current execution status (active, recent, specific ID)
- Instance lookup (by ID, name, tag, account)
- Failure summaries and error breakdowns
- Quick health checks

### Runbook Operations
You can execute these approved operations:
- ✅ check-ssm-agent - Check SSM agent status (no approval)
- ✅ get-patch-log - Get patch log tail (no approval)
- ✅ check-disk-space - Check disk usage (no approval)
- ⚠️ restart-ssm-agent - Restart SSM agent (requires approval)
- ⚠️ force-patch-scan - Trigger patch scan (requires approval)

### Investigation
- Link to relevant logs and dashboards
- Suggest troubleshooting steps
- Escalate to Anomaly Detection Agent for complex issues

## Response Format

### For Status Queries
Use compact tables and status indicators:
```
🟢 Active Executions: 2
┌──────────────────┬─────────┬───────────┐
│ Execution        │ Status  │ Progress  │
├──────────────────┼─────────┼───────────┤
│ abc123...        │ RUNNING │ 45%       │
│ def456...        │ RUNNING │ 12%       │
└──────────────────┴─────────┴───────────┘
```

### For Errors/Failures
Prioritize actionable information:
```
❌ 3 failures in last hour

Top error: SSM Agent Unreachable (2 instances)
• i-0123abc - us-east-1 (prod-web)
• i-0456def - us-east-1 (prod-api)

💡 Quick fix: Run `/patch-runbook restart-ssm-agent`
```

### For Runbook Execution
Confirm clearly:
```
✅ Runbook 'Check SSM Agent' executed
Instance: i-0123456789abcdef0
Command ID: abc123-def456

Output will be available in ~30 seconds.
```

## Guidelines

1. **Security First**: Never expose credentials, keys, or sensitive data
2. **Verify Targets**: Confirm instance IDs and accounts before destructive actions
3. **Rate Limit Awareness**: Don't allow rapid repeated operations
4. **Escalation Path**: Suggest human review for complex issues
5. **Context Preservation**: Remember conversation context within a thread

## Common Queries & Responses

| Query | Response Type |
|-------|---------------|
| "status" / "what's running" | Active execution summary |
| "find i-xxx" / "@patchbot i-xxx" | Instance lookup with patch history |
| "failures" / "what failed" | Recent failure summary |
| "help" / "commands" | Available commands list |
| "restart ssm on i-xxx" | Runbook execution (with confirmation) |

## Off-Topic Handling

For questions outside patching scope:
"I'm specialized in EC2 patching operations. For [topic], please contact [relevant team/resource]."
```

---

## 7. Microsoft Teams Integration

### 7.1 Teams Bot Configuration

```json
{
  "$schema": "https://developer.microsoft.com/en-us/json-schemas/teams/v1.14/MicrosoftTeams.schema.json",
  "manifestVersion": "1.14",
  "version": "1.0.0",
  "id": "patching-bot-uuid",
  "packageName": "com.example.patching.bot",
  "name": {
    "short": "Patching Bot",
    "full": "EC2 Patching Platform Bot"
  },
  "description": {
    "short": "Chat interface for EC2 patching operations",
    "full": "Query patch status, receive notifications, and execute runbook operations for the EC2 Patching Platform."
  },
  "bots": [
    {
      "botId": "{{BOT_APP_ID}}",
      "scopes": ["personal", "team", "groupchat"],
      "supportsFiles": false,
      "isNotificationOnly": false,
      "commandLists": [
        {
          "scopes": ["personal", "team"],
          "commands": [
            {"title": "status", "description": "Get current patching status"},
            {"title": "find", "description": "Find an instance by ID or name"},
            {"title": "failures", "description": "Show recent failures"},
            {"title": "runbook", "description": "Execute a runbook operation"}
          ]
        }
      ]
    }
  ],
  "composeExtensions": [],
  "permissions": ["identity", "messageTeamMembers"],
  "validDomains": ["api.patching.example.com"]
}
```

### 7.2 Adaptive Card Templates

```python
"""
Microsoft Teams Adaptive Card Templates
"""

def execution_status_card(execution_id: str, details: dict) -> dict:
    """Adaptive Card for execution status"""
    
    status_color = {
        'RUNNING': 'attention',
        'SUCCEEDED': 'good',
        'FAILED': 'warning',
    }.get(details.get('status'), 'default')
    
    return {
        'type': 'AdaptiveCard',
        'version': '1.4',
        '$schema': 'http://adaptivecards.io/schemas/adaptive-card.json',
        'body': [
            {
                'type': 'TextBlock',
                'text': '📊 Patching Execution Status',
                'weight': 'bolder',
                'size': 'large'
            },
            {
                'type': 'FactSet',
                'facts': [
                    {'title': 'Execution ID', 'value': execution_id[:20] + '...'},
                    {'title': 'Status', 'value': details.get('status', 'Unknown')},
                    {'title': 'Progress', 'value': f"{details.get('progress', 0):.0f}%"},
                    {'title': 'Instances', 'value': f"{details.get('completed', 0)}/{details.get('total', 0)}"}
                ]
            },
            {
                'type': 'ColumnSet',
                'columns': [
                    {
                        'type': 'Column',
                        'width': 'stretch',
                        'items': [{
                            'type': 'TextBlock',
                            'text': f"✅ {details.get('success', 0)} succeeded",
                            'color': 'good'
                        }]
                    },
                    {
                        'type': 'Column',
                        'width': 'stretch',
                        'items': [{
                            'type': 'TextBlock',
                            'text': f"❌ {details.get('failed', 0)} failed",
                            'color': 'warning'
                        }]
                    }
                ]
            }
        ],
        'actions': [
            {
                'type': 'Action.Submit',
                'title': 'Refresh Status',
                'data': {'action': 'refresh_status', 'execution_id': execution_id}
            },
            {
                'type': 'Action.OpenUrl',
                'title': 'Open Console',
                'url': f"https://console.aws.amazon.com/states/home#/executions/details/{execution_id}"
            }
        ]
    }
```

---

## 8. IAM Permissions

```yaml
ChatOpsAgentRole:
  Type: AWS::IAM::Role
  Properties:
    RoleName: !Sub '${NamePrefix}-${Environment}-chatops-agent-role'
    AssumeRolePolicyDocument:
      Version: '2012-10-17'
      Statement:
        - Effect: Allow
          Principal:
            Service: bedrock.amazonaws.com
          Action: sts:AssumeRole
    Policies:
      - PolicyName: ChatOpsAgentPolicy
        PolicyDocument:
          Version: '2012-10-17'
          Statement:
            # DynamoDB Read
            - Effect: Allow
              Action:
                - dynamodb:Query
                - dynamodb:GetItem
              Resource:
                - !Sub 'arn:aws:dynamodb:${AWS::Region}:${AWS::AccountId}:table/${PatchRunsTable}'
                - !Sub 'arn:aws:dynamodb:${AWS::Region}:${AWS::AccountId}:table/${PatchRunsTable}/index/*'
            
            # Step Functions Read
            - Effect: Allow
              Action:
                - states:ListExecutions
                - states:DescribeExecution
                - states:GetExecutionHistory
              Resource:
                - !Sub 'arn:aws:states:${AWS::Region}:${AWS::AccountId}:stateMachine:${NamePrefix}*'
            
            # SSM Read + Limited Execute
            - Effect: Allow
              Action:
                - ssm:DescribeInstanceInformation
                - ssm:ListCommands
                - ssm:GetCommandInvocation
              Resource: '*'
            
            # SSM Execute for approved runbooks only
            - Effect: Allow
              Action:
                - ssm:SendCommand
              Resource:
                - !Sub 'arn:aws:ssm:${AWS::Region}::document/AWS-RunShellScript'
                - !Sub 'arn:aws:ssm:${AWS::Region}::document/AWS-RunPatchBaseline'
              Condition:
                StringEquals:
                  'ssm:DocumentName':
                    - 'AWS-RunShellScript'
                    - 'AWS-RunPatchBaseline'
            
            # EC2 Read for instance lookup
            - Effect: Allow
              Action:
                - ec2:DescribeInstances
                - ec2:DescribeTags
              Resource: '*'
            
            # Secrets Manager for Slack/Teams tokens
            - Effect: Allow
              Action:
                - secretsmanager:GetSecretValue
              Resource:
                - !Sub 'arn:aws:secretsmanager:${AWS::Region}:${AWS::AccountId}:secret:${NamePrefix}/chatops/*'
```

---

## 9. Rate Limiting and Security

### 9.1 Rate Limiting Configuration

```python
"""
Rate Limiter for ChatOps
Prevents abuse and ensures fair usage
"""

import time
from typing import Dict, Optional
import boto3

dynamodb = boto3.resource('dynamodb')
rate_limit_table = dynamodb.Table(os.environ['RATE_LIMIT_TABLE'])

LIMITS = {
    'queries': {'window': 60, 'max': 30},      # 30 queries per minute
    'runbooks': {'window': 300, 'max': 5},     # 5 runbooks per 5 minutes
    'approvals': {'window': 3600, 'max': 10}   # 10 approvals per hour
}


def check_rate_limit(user_id: str, action_type: str) -> tuple[bool, Optional[int]]:
    """Check if user is within rate limits"""
    
    limit = LIMITS.get(action_type, LIMITS['queries'])
    window_start = int(time.time()) - limit['window']
    
    # Get recent actions
    response = rate_limit_table.query(
        KeyConditionExpression='user_id = :uid AND action_time > :start',
        ExpressionAttributeValues={
            ':uid': f"{user_id}#{action_type}",
            ':start': window_start
        }
    )
    
    action_count = response['Count']
    
    if action_count >= limit['max']:
        # Calculate retry-after
        oldest = min(item['action_time'] for item in response['Items'])
        retry_after = oldest + limit['window'] - int(time.time())
        return False, retry_after
    
    # Record action
    rate_limit_table.put_item(Item={
        'user_id': f"{user_id}#{action_type}",
        'action_time': int(time.time()),
        'ttl': int(time.time()) + limit['window'] + 60
    })
    
    return True, None
```

### 9.2 User Authorization

```python
"""
User Authorization for ChatOps
Maps platform users to permissions
"""

def get_user_permissions(platform: str, user_id: str) -> dict:
    """Get user permissions for ChatOps operations"""
    
    # Look up user in directory
    user = lookup_user(platform, user_id)
    
    if not user:
        return {'level': 'readonly', 'can_execute_runbooks': False, 'can_approve': False}
    
    # Map groups to permissions
    permissions = {
        'level': 'readonly',
        'can_execute_runbooks': False,
        'can_approve': False,
        'allowed_runbooks': []
    }
    
    if 'patching-operators' in user.get('groups', []):
        permissions['level'] = 'operator'
        permissions['can_execute_runbooks'] = True
        permissions['allowed_runbooks'] = ['check-ssm-agent', 'get-patch-log', 'check-disk-space']
    
    if 'patching-admins' in user.get('groups', []):
        permissions['level'] = 'admin'
        permissions['can_execute_runbooks'] = True
        permissions['can_approve'] = True
        permissions['allowed_runbooks'] = list(RUNBOOKS.keys())
    
    return permissions
```

---

## 10. Sample Conversations

### 10.1 Status Query

**User:** What's the current patching status?

**Bot:** 
```
🔄 Active Executions: 1

┌──────────────────┬─────────┬──────────┬─────────────┐
│ ID               │ Status  │ Progress │ Instances   │
├──────────────────┼─────────┼──────────┼─────────────┤
│ exec-7f3a2b...   │ RUNNING │ 62%      │ 187/302     │
└──────────────────┴─────────┴──────────┴─────────────┘

📊 Wave Progress:
• Wave 1: ✅ Complete (45/45 - 100%)
• Wave 2: 🔄 In Progress (142/212 - 67%)
• Wave 3: ⏳ Pending (0/45)

⏱️ Started: 2h 15m ago | ETA: ~45 min
```

### 10.2 Failure Investigation

**User:** Show me recent failures

**Bot:**
```
❌ 7 failures in last 6 hours

By Error Type:
┌────────────────────────┬───────┬────────────┐
│ Error                  │ Count │ % of Total │
├────────────────────────┼───────┼────────────┤
│ SSM Agent Unreachable  │ 4     │ 57%        │
│ Reboot Timeout         │ 2     │ 29%        │
│ Package Conflict       │ 1     │ 14%        │
└────────────────────────┴───────┴────────────┘

💡 Most failures (4) are SSM connectivity issues.

Quick Actions:
• View affected instances: `find failures:ssm-agent`
• Run diagnostics: `/patch-runbook check-ssm-agent`
• Get detailed analysis: `@PatchBot analyze failures`
```

### 10.3 Runbook Execution

**User:** restart ssm agent on i-0123456789abcdef0

**Bot:**
```
⚠️ Runbook 'Restart SSM Agent' requires approval.

Instance: i-0123456789abcdef0
Account: 123456789012 (prod-web)
Region: us-east-1

Please provide a justification for this action:
```

**User:** Instance failed patching due to SSM timeout

**Bot:**
```
📝 Approval requested for 'Restart SSM Agent'

Instance: i-0123456789abcdef0
Justification: Instance failed patching due to SSM timeout
Requested by: @john.doe

Waiting for approval from: @oncall-team

[Approve] [Deny]
```

**Approver clicks Approve**

**Bot:**
```
✅ Runbook 'Restart SSM Agent' approved and executed

Instance: i-0123456789abcdef0
Command ID: cmd-0987654321fedcba0
Approved by: @jane.smith

Output:
Stopping SSM Agent... OK
Starting SSM Agent... OK
Amazon SSM Agent is running.
```

---

*Next: Agent 5 - Predictive Planning & Optimization Agent Technical Design*
