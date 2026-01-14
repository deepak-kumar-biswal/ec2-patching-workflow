# Agent 1: Audit & Compliance Agent - Technical Design

## Document Information
| Attribute | Value |
|-----------|-------|
| Version | 1.0 |
| Last Updated | January 14, 2026 |
| Status | Draft |
| Owner | Platform Engineering |
| Agent ID | `audit-compliance-agent` |

---

## 1. Executive Summary

The **Audit & Compliance Agent** is designed to automate compliance verification, audit evidence collection, and patch gap analysis across the enterprise EC2 patching platform. It serves compliance officers, security teams, and auditors by providing natural language access to patching compliance data.

### 1.1 Key Capabilities

| Capability | Description | Priority |
|------------|-------------|----------|
| Compliance Status Queries | Natural language queries for patch compliance status | P0 |
| Audit Report Generation | Automated SOC2, PCI-DSS, HIPAA compliance reports | P0 |
| Patch Gap Analysis | Identify instances missing required patches | P0 |
| Evidence Collection | Gather audit evidence with S3 path references | P1 |
| SLA Violation Detection | Identify accounts/instances violating patch SLAs | P1 |
| Historical Trend Analysis | Compliance trends over time | P2 |

### 1.2 User Personas

| Persona | Use Cases | Access Level |
|---------|-----------|--------------|
| Compliance Officer | Generate audit reports, verify compliance status | Read-only |
| Security Analyst | Patch gap analysis, vulnerability correlation | Read-only |
| External Auditor | Review evidence, validate controls | Read-only (scoped) |
| Platform Engineer | Troubleshoot compliance failures | Read-only |

---

## 2. Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                         AUDIT & COMPLIANCE AGENT                                 │
│                                                                                  │
│  ┌───────────────────────────────────────────────────────────────────────────┐  │
│  │                           AGENT CORE                                       │  │
│  │  Model: anthropic.claude-3-sonnet-20240229-v1:0                           │  │
│  │  Temperature: 0.1 (low for factual accuracy)                              │  │
│  │  Max Tokens: 4096                                                          │  │
│  │                                                                            │  │
│  │  ┌─────────────────────────────────────────────────────────────────────┐  │  │
│  │  │                      SYSTEM PROMPT                                   │  │  │
│  │  │  You are an expert AWS EC2 Patching Audit Agent...                  │  │  │
│  │  │  (See Section 4 for full prompt)                                    │  │  │
│  │  └─────────────────────────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────────────────────┘  │
│                                      │                                           │
│         ┌────────────────────────────┼────────────────────────────┐              │
│         │                            │                            │              │
│         ▼                            ▼                            ▼              │
│  ┌─────────────────┐    ┌─────────────────────┐    ┌─────────────────────┐      │
│  │ KNOWLEDGE BASES │    │    ACTION GROUPS     │    │     GUARDRAILS      │      │
│  │                 │    │                      │    │                     │      │
│  │ • patch-artifacts│   │ • DynamoDB Query    │    │ • Content filters   │      │
│  │ • execution-records│ │ • S3 Read           │    │ • PII masking       │      │
│  │ • compliance-fw  │   │ • CloudWatch Query  │    │ • Topic restriction │      │
│  │ • operational-docs│  │ • Report Generator  │    │ • Audit logging     │      │
│  └─────────────────┘    │ • SSM Describe      │    └─────────────────────┘      │
│                         └─────────────────────┘                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              AWS SERVICES                                        │
│                                                                                  │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐ │
│  │ DynamoDB    │  │ S3          │  │ CloudWatch  │  │ SSM                     │ │
│  │ (PatchRuns) │  │ (Snapshots) │  │ (Metrics)   │  │ (Patch States)          │ │
│  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────────────────┘ │
│                                                                                  │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                              │
│  │ Step        │  │ OpenSearch  │  │ Lambda      │                              │
│  │ Functions   │  │ Serverless  │  │ (Reports)   │                              │
│  └─────────────┘  └─────────────┘  └─────────────┘                              │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Action Groups (Tools)

### 3.1 Action Group: `compliance-queries`

This action group provides tools for querying compliance and patch status data.

#### 3.1.1 Tool: `query_patch_execution_history`

**Purpose:** Query patch execution history from DynamoDB

**OpenAPI Schema:**
```yaml
openapi: 3.0.0
info:
  title: Compliance Queries API
  version: 1.0.0

paths:
  /query-executions:
    post:
      operationId: queryPatchExecutionHistory
      summary: Query patch execution history
      description: |
        Retrieves patch execution records from DynamoDB based on filters.
        Use this to find executions by date range, status, account, or region.
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              properties:
                scope:
                  type: string
                  enum: [wave, account, region, instance]
                  description: Scope level to query
                status:
                  type: string
                  enum: [success, partial, failed, all]
                  description: Filter by execution status
                accountIds:
                  type: array
                  items:
                    type: string
                  description: Filter by specific account IDs
                regions:
                  type: array
                  items:
                    type: string
                  description: Filter by specific regions
                startDate:
                  type: string
                  format: date
                  description: Start date for query range (YYYY-MM-DD)
                endDate:
                  type: string
                  format: date
                  description: End date for query range (YYYY-MM-DD)
                limit:
                  type: integer
                  default: 50
                  maximum: 200
                  description: Maximum records to return
              required:
                - scope
      responses:
        '200':
          description: Successful response
          content:
            application/json:
              schema:
                type: object
                properties:
                  executions:
                    type: array
                    items:
                      $ref: '#/components/schemas/ExecutionRecord'
                  totalCount:
                    type: integer
                  hasMore:
                    type: boolean

components:
  schemas:
    ExecutionRecord:
      type: object
      properties:
        executionId:
          type: string
        scope:
          type: string
        scopeId:
          type: string
        status:
          type: string
        startTime:
          type: string
        endTime:
          type: string
        instanceCount:
          type: integer
        successCount:
          type: integer
        failureCount:
          type: integer
        patchesInstalled:
          type: integer
        accounts:
          type: array
          items:
            type: string
        regions:
          type: array
          items:
            type: string
```

**Lambda Handler:**
```python
"""
Lambda handler for query_patch_execution_history action
"""

import json
import boto3
from datetime import datetime
from typing import Dict, Any, List
from boto3.dynamodb.conditions import Key, Attr

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['PATCH_RUNS_TABLE'])

def handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """Query patch execution history from DynamoDB"""
    
    params = event.get('requestBody', {}).get('content', {}).get('application/json', {})
    
    scope = params.get('scope', 'wave')
    status = params.get('status', 'all')
    account_ids = params.get('accountIds', [])
    regions = params.get('regions', [])
    start_date = params.get('startDate')
    end_date = params.get('endDate')
    limit = min(params.get('limit', 50), 200)
    
    # Build query
    key_condition = Key('scope').eq(scope)
    
    filter_expression = None
    
    # Add status filter
    if status != 'all':
        filter_expression = Attr('status').eq(status)
    
    # Add account filter
    if account_ids:
        account_filter = Attr('metadata.accounts').contains(account_ids[0])
        for account_id in account_ids[1:]:
            account_filter = account_filter | Attr('metadata.accounts').contains(account_id)
        filter_expression = account_filter if not filter_expression else filter_expression & account_filter
    
    # Add date range filter
    if start_date:
        date_filter = Attr('start_time').gte(start_date)
        filter_expression = date_filter if not filter_expression else filter_expression & date_filter
    if end_date:
        date_filter = Attr('start_time').lte(end_date + 'T23:59:59Z')
        filter_expression = date_filter if not filter_expression else filter_expression & date_filter
    
    # Execute query
    query_params = {
        'KeyConditionExpression': key_condition,
        'Limit': limit,
        'ScanIndexForward': False  # Most recent first
    }
    
    if filter_expression:
        query_params['FilterExpression'] = filter_expression
    
    response = table.query(**query_params)
    
    # Transform results
    executions = []
    for item in response.get('Items', []):
        metadata = item.get('metadata', {})
        executions.append({
            'executionId': item.get('execution_id', ''),
            'scope': item['scope'],
            'scopeId': item['id'],
            'status': item.get('status', 'unknown'),
            'startTime': item.get('start_time', ''),
            'endTime': item.get('end_time', ''),
            'instanceCount': metadata.get('instance_count', 0),
            'successCount': metadata.get('success_count', 0),
            'failureCount': metadata.get('failure_count', 0),
            'patchesInstalled': metadata.get('patches_installed', 0),
            'accounts': metadata.get('accounts', []),
            'regions': metadata.get('regions', [])
        })
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'executions': executions,
            'totalCount': len(executions),
            'hasMore': 'LastEvaluatedKey' in response
        })
    }
```

#### 3.1.2 Tool: `get_patch_compliance_summary`

**Purpose:** Get aggregated compliance statistics

**OpenAPI Schema:**
```yaml
paths:
  /compliance-summary:
    post:
      operationId: getPatchComplianceSummary
      summary: Get patch compliance summary statistics
      description: |
        Returns aggregated compliance statistics including success rates,
        SLA adherence, and patch coverage across the fleet.
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              properties:
                timeRange:
                  type: string
                  enum: [7d, 30d, 90d, custom]
                  description: Time range for summary
                startDate:
                  type: string
                  format: date
                  description: Custom start date (required if timeRange is custom)
                endDate:
                  type: string
                  format: date
                  description: Custom end date (required if timeRange is custom)
                groupBy:
                  type: string
                  enum: [account, region, os, wave]
                  description: How to group the summary
                accountIds:
                  type: array
                  items:
                    type: string
                  description: Filter by specific accounts
      responses:
        '200':
          description: Compliance summary
          content:
            application/json:
              schema:
                type: object
                properties:
                  overallComplianceRate:
                    type: number
                    description: Percentage of successful patches
                  totalExecutions:
                    type: integer
                  successfulExecutions:
                    type: integer
                  failedExecutions:
                    type: integer
                  totalInstancesPatched:
                    type: integer
                  totalPatchesInstalled:
                    type: integer
                  slaAdherenceRate:
                    type: number
                    description: Percentage of patches within SLA
                  groupedStats:
                    type: array
                    items:
                      type: object
                      properties:
                        groupKey:
                          type: string
                        complianceRate:
                          type: number
                        executionCount:
                          type: integer
                        instanceCount:
                          type: integer
```

**Lambda Handler:**
```python
"""
Lambda handler for get_patch_compliance_summary action
"""

import json
import boto3
from datetime import datetime, timedelta
from typing import Dict, Any
from collections import defaultdict

dynamodb = boto3.resource('dynamodb')
cloudwatch = boto3.client('cloudwatch')
table = dynamodb.Table(os.environ['PATCH_RUNS_TABLE'])

def handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """Calculate patch compliance summary statistics"""
    
    params = event.get('requestBody', {}).get('content', {}).get('application/json', {})
    
    time_range = params.get('timeRange', '30d')
    group_by = params.get('groupBy', 'account')
    account_ids = params.get('accountIds', [])
    
    # Calculate date range
    end_date = datetime.utcnow()
    if time_range == '7d':
        start_date = end_date - timedelta(days=7)
    elif time_range == '30d':
        start_date = end_date - timedelta(days=30)
    elif time_range == '90d':
        start_date = end_date - timedelta(days=90)
    else:
        start_date = datetime.fromisoformat(params.get('startDate'))
        end_date = datetime.fromisoformat(params.get('endDate'))
    
    # Scan for executions in range
    executions = scan_executions(start_date.isoformat(), end_date.isoformat(), account_ids)
    
    # Calculate overall stats
    total_executions = len(executions)
    successful = sum(1 for e in executions if e.get('status') == 'success')
    failed = sum(1 for e in executions if e.get('status') == 'failed')
    partial = sum(1 for e in executions if e.get('status') == 'partial')
    
    total_instances = sum(e.get('metadata', {}).get('instance_count', 0) for e in executions)
    total_patches = sum(e.get('metadata', {}).get('patches_installed', 0) for e in executions)
    
    compliance_rate = (successful / total_executions * 100) if total_executions > 0 else 0
    
    # Calculate SLA adherence (assuming 48-hour SLA for critical patches)
    sla_adherent = sum(1 for e in executions if is_sla_compliant(e))
    sla_rate = (sla_adherent / total_executions * 100) if total_executions > 0 else 0
    
    # Group statistics
    grouped_stats = calculate_grouped_stats(executions, group_by)
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'overallComplianceRate': round(compliance_rate, 2),
            'totalExecutions': total_executions,
            'successfulExecutions': successful,
            'failedExecutions': failed,
            'partialExecutions': partial,
            'totalInstancesPatched': total_instances,
            'totalPatchesInstalled': total_patches,
            'slaAdherenceRate': round(sla_rate, 2),
            'groupedStats': grouped_stats,
            'timeRange': {
                'start': start_date.isoformat(),
                'end': end_date.isoformat()
            }
        })
    }


def scan_executions(start_date: str, end_date: str, account_ids: list) -> list:
    """Scan DynamoDB for executions in date range"""
    # Implementation details...
    pass


def is_sla_compliant(execution: dict) -> bool:
    """Check if execution meets SLA requirements"""
    # SLA: Patches must be applied within 48 hours of scheduled window
    # Implementation details...
    return True


def calculate_grouped_stats(executions: list, group_by: str) -> list:
    """Calculate statistics grouped by specified dimension"""
    grouped = defaultdict(lambda: {
        'executions': 0,
        'successful': 0,
        'instances': 0
    })
    
    for execution in executions:
        metadata = execution.get('metadata', {})
        
        if group_by == 'account':
            keys = metadata.get('accounts', ['unknown'])
        elif group_by == 'region':
            keys = metadata.get('regions', ['unknown'])
        elif group_by == 'wave':
            keys = [metadata.get('wave_name', 'unknown')]
        else:
            keys = ['all']
        
        for key in keys:
            grouped[key]['executions'] += 1
            if execution.get('status') == 'success':
                grouped[key]['successful'] += 1
            grouped[key]['instances'] += metadata.get('instance_count', 0)
    
    return [
        {
            'groupKey': key,
            'complianceRate': round(stats['successful'] / stats['executions'] * 100, 2) if stats['executions'] > 0 else 0,
            'executionCount': stats['executions'],
            'instanceCount': stats['instances']
        }
        for key, stats in sorted(grouped.items())
    ]
```

#### 3.1.3 Tool: `get_unpatched_instances`

**Purpose:** Identify instances that haven't been patched within SLA

**OpenAPI Schema:**
```yaml
paths:
  /unpatched-instances:
    post:
      operationId: getUnpatchedInstances
      summary: Get instances not patched within specified timeframe
      description: |
        Identifies EC2 instances that haven't received patches within the 
        specified number of days. Useful for SLA compliance and patch gap analysis.
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              properties:
                daysSinceLastPatch:
                  type: integer
                  default: 30
                  description: Threshold days since last patch
                accountIds:
                  type: array
                  items:
                    type: string
                  description: Filter by specific accounts
                regions:
                  type: array
                  items:
                    type: string
                  description: Filter by specific regions
                patchGroup:
                  type: string
                  description: Filter by patch group tag value
                limit:
                  type: integer
                  default: 100
                  maximum: 500
      responses:
        '200':
          description: List of unpatched instances
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
                        lastPatchDate:
                          type: string
                        daysSinceLastPatch:
                          type: integer
                        patchGroup:
                          type: string
                        operatingSystem:
                          type: string
                        complianceStatus:
                          type: string
                  totalCount:
                    type: integer
                  criticalCount:
                    type: integer
                    description: Instances missing critical patches
```

#### 3.1.4 Tool: `get_patch_evidence`

**Purpose:** Retrieve audit evidence for specific patch execution

**OpenAPI Schema:**
```yaml
paths:
  /patch-evidence:
    post:
      operationId: getPatchEvidence
      summary: Get detailed evidence for a patch execution
      description: |
        Retrieves detailed evidence for a specific patch execution including
        S3 artifact paths, execution logs, and status details. Used for audit
        evidence collection.
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              properties:
                executionId:
                  type: string
                  description: Step Functions execution ID
                instanceId:
                  type: string
                  description: Optional - filter to specific instance
                evidenceTypes:
                  type: array
                  items:
                    type: string
                    enum: [pre-collection, pre-patch, patch, post-patch, verification]
                  description: Types of evidence to retrieve
              required:
                - executionId
      responses:
        '200':
          description: Patch evidence details
          content:
            application/json:
              schema:
                type: object
                properties:
                  executionId:
                    type: string
                  executionStatus:
                    type: string
                  executionStart:
                    type: string
                  executionEnd:
                    type: string
                  evidence:
                    type: array
                    items:
                      type: object
                      properties:
                        instanceId:
                          type: string
                        phase:
                          type: string
                        status:
                          type: string
                        s3Path:
                          type: string
                        contentPreview:
                          type: string
                          description: First 500 chars of output
                        timestamp:
                          type: string
```

### 3.2 Action Group: `compliance-reports`

#### 3.2.1 Tool: `generate_compliance_report`

**Purpose:** Generate formatted compliance report for audit

**OpenAPI Schema:**
```yaml
paths:
  /generate-report:
    post:
      operationId: generateComplianceReport
      summary: Generate a compliance report
      description: |
        Generates a formatted compliance report based on specified framework
        and time period. Report can be returned as markdown or stored in S3.
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              properties:
                framework:
                  type: string
                  enum: [soc2, pci-dss, hipaa, nist-800-53, custom]
                  description: Compliance framework for report
                reportType:
                  type: string
                  enum: [executive-summary, detailed, evidence-pack]
                  description: Level of detail in report
                timeRange:
                  type: string
                  enum: [weekly, monthly, quarterly, yearly, custom]
                startDate:
                  type: string
                  format: date
                endDate:
                  type: string
                  format: date
                accountScope:
                  type: array
                  items:
                    type: string
                  description: Accounts to include (empty = all)
                outputFormat:
                  type: string
                  enum: [markdown, html, pdf, json]
                  default: markdown
                saveToS3:
                  type: boolean
                  default: false
                  description: Whether to save report to S3
              required:
                - framework
                - reportType
      responses:
        '200':
          description: Generated report
          content:
            application/json:
              schema:
                type: object
                properties:
                  reportContent:
                    type: string
                    description: Report content (if not saved to S3)
                  s3Path:
                    type: string
                    description: S3 path (if saved to S3)
                  generatedAt:
                    type: string
                  controls:
                    type: array
                    items:
                      type: object
                      properties:
                        controlId:
                          type: string
                        controlName:
                          type: string
                        status:
                          type: string
                          enum: [compliant, non-compliant, partial, not-applicable]
                        evidenceCount:
                          type: integer
                        findings:
                          type: string
```

**Lambda Handler (Report Generator):**
```python
"""
Compliance Report Generator Lambda
Generates audit-ready compliance reports
"""

import json
import boto3
from datetime import datetime
from typing import Dict, Any, List

s3_client = boto3.client('s3')

# Compliance framework control mappings
COMPLIANCE_CONTROLS = {
    'soc2': {
        'CC6.1': {
            'name': 'Logical and Physical Access Controls',
            'requirement': 'The entity implements logical access security software, infrastructure, and architectures over protected information assets.',
            'patch_relevance': 'Security patches must be applied to maintain access control integrity'
        },
        'CC7.1': {
            'name': 'System Operations - Security Configuration',
            'requirement': 'To meet its objectives, the entity uses detection and monitoring procedures.',
            'patch_relevance': 'Patch management monitoring and verification'
        },
        'CC7.2': {
            'name': 'System Operations - Incident Detection',
            'requirement': 'The entity monitors system components and the operation of those components for anomalies.',
            'patch_relevance': 'Vulnerability patching as incident prevention'
        },
        'CC8.1': {
            'name': 'Change Management',
            'requirement': 'The entity authorizes, designs, develops or acquires, configures, documents, tests, approves, and implements changes.',
            'patch_relevance': 'Patch deployment follows change management procedures'
        }
    },
    'pci-dss': {
        '6.2': {
            'name': 'Security Patches',
            'requirement': 'Install critical security patches within one month of release.',
            'patch_relevance': 'Direct - timely patch installation required'
        },
        '6.3': {
            'name': 'Secure Development',
            'requirement': 'Develop software applications in accordance with security standards.',
            'patch_relevance': 'Patches address security vulnerabilities in software'
        },
        '11.2': {
            'name': 'Vulnerability Scans',
            'requirement': 'Run internal and external network vulnerability scans quarterly.',
            'patch_relevance': 'Patches remediate identified vulnerabilities'
        }
    },
    'hipaa': {
        '164.308(a)(5)': {
            'name': 'Security Awareness and Training',
            'requirement': 'Implement procedures for guarding against malicious software.',
            'patch_relevance': 'Patches protect against malicious software vulnerabilities'
        },
        '164.312(a)(1)': {
            'name': 'Access Control',
            'requirement': 'Implement technical policies and procedures for access control.',
            'patch_relevance': 'Patches maintain access control mechanism integrity'
        }
    }
}


def handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """Generate compliance report"""
    
    params = event.get('requestBody', {}).get('content', {}).get('application/json', {})
    
    framework = params.get('framework', 'soc2')
    report_type = params.get('reportType', 'executive-summary')
    time_range = params.get('timeRange', 'monthly')
    output_format = params.get('outputFormat', 'markdown')
    save_to_s3 = params.get('saveToS3', False)
    
    # Get date range
    start_date, end_date = calculate_date_range(time_range, params)
    
    # Gather compliance data
    compliance_data = gather_compliance_data(start_date, end_date, params.get('accountScope', []))
    
    # Evaluate controls
    control_evaluations = evaluate_controls(framework, compliance_data)
    
    # Generate report content
    if report_type == 'executive-summary':
        report_content = generate_executive_summary(framework, control_evaluations, compliance_data)
    elif report_type == 'detailed':
        report_content = generate_detailed_report(framework, control_evaluations, compliance_data)
    else:
        report_content = generate_evidence_pack(framework, control_evaluations, compliance_data)
    
    # Format output
    if output_format == 'markdown':
        formatted_report = format_markdown(report_content)
    elif output_format == 'html':
        formatted_report = format_html(report_content)
    elif output_format == 'json':
        formatted_report = json.dumps(report_content, indent=2)
    
    # Save to S3 if requested
    s3_path = None
    if save_to_s3:
        s3_path = save_report_to_s3(formatted_report, framework, report_type)
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'reportContent': formatted_report if not save_to_s3 else None,
            's3Path': s3_path,
            'generatedAt': datetime.utcnow().isoformat(),
            'controls': [
                {
                    'controlId': ctrl_id,
                    'controlName': ctrl['name'],
                    'status': ctrl['status'],
                    'evidenceCount': ctrl['evidence_count'],
                    'findings': ctrl.get('findings', '')
                }
                for ctrl_id, ctrl in control_evaluations.items()
            ]
        })
    }


def generate_executive_summary(framework: str, controls: dict, data: dict) -> dict:
    """Generate executive summary report"""
    
    compliant_count = sum(1 for c in controls.values() if c['status'] == 'compliant')
    total_controls = len(controls)
    compliance_percentage = (compliant_count / total_controls * 100) if total_controls > 0 else 0
    
    return {
        'title': f'{framework.upper()} Patch Compliance Executive Summary',
        'generated_at': datetime.utcnow().isoformat(),
        'summary': {
            'overall_compliance': f'{compliance_percentage:.1f}%',
            'compliant_controls': compliant_count,
            'total_controls': total_controls,
            'patch_success_rate': f"{data['success_rate']:.1f}%",
            'total_patches_applied': data['total_patches'],
            'instances_patched': data['instances_patched']
        },
        'control_summary': controls,
        'recommendations': generate_recommendations(controls),
        'evidence_references': data.get('evidence_paths', [])
    }


def format_markdown(report: dict) -> str:
    """Format report as Markdown"""
    
    md = f"""# {report['title']}

**Generated:** {report['generated_at']}

## Executive Summary

| Metric | Value |
|--------|-------|
| Overall Compliance | {report['summary']['overall_compliance']} |
| Compliant Controls | {report['summary']['compliant_controls']} / {report['summary']['total_controls']} |
| Patch Success Rate | {report['summary']['patch_success_rate']} |
| Total Patches Applied | {report['summary']['total_patches_applied']} |
| Instances Patched | {report['summary']['instances_patched']} |

## Control Status

| Control ID | Control Name | Status | Evidence |
|------------|--------------|--------|----------|
"""
    
    for ctrl_id, ctrl in report['control_summary'].items():
        status_icon = '✅' if ctrl['status'] == 'compliant' else '❌' if ctrl['status'] == 'non-compliant' else '⚠️'
        md += f"| {ctrl_id} | {ctrl['name']} | {status_icon} {ctrl['status']} | {ctrl['evidence_count']} items |\n"
    
    md += """
## Recommendations

"""
    for rec in report.get('recommendations', []):
        md += f"- {rec}\n"
    
    md += """
## Evidence References

"""
    for ref in report.get('evidence_references', [])[:10]:
        md += f"- `{ref}`\n"
    
    return md
```

---

## 4. System Prompt

```text
You are an expert AWS EC2 Patching Audit and Compliance Agent. Your role is to help 
compliance officers, security analysts, and auditors assess patch compliance across 
a multi-account AWS enterprise environment.

## Your Capabilities

You have access to the following information sources:
1. **Patch Execution History** - DynamoDB records of all patch runs (waves, accounts, regions, instances)
2. **Patch Artifacts** - S3 stored outputs from pre-patch, patch, and post-patch operations
3. **Compliance Frameworks** - SOC 2, PCI-DSS, HIPAA, and NIST 800-53 control mappings
4. **Operational Documentation** - Runbooks, troubleshooting guides, and API references

You can perform the following actions:
- Query patch execution history by date, account, region, or status
- Calculate compliance statistics and success rates
- Identify instances that haven't been patched within SLA
- Retrieve detailed evidence for specific patch executions
- Generate compliance reports for various frameworks

## Guidelines

### Data Accuracy
1. Always cite specific evidence when making compliance claims
2. Include execution IDs, timestamps, and S3 paths for audit trails
3. If data is incomplete or uncertain, state this clearly
4. Never fabricate or assume data - use tools to retrieve actual information

### Response Format
1. Structure responses in clear, audit-ready format
2. Use tables for summarizing statistics
3. Include specific counts and percentages
4. Reference evidence locations (S3 paths, execution IDs)

### Compliance Context
1. Map findings to specific control requirements when relevant
2. Highlight gaps and risks with severity levels
3. Provide actionable recommendations
4. Consider SLA timelines (critical patches: 48 hours, high: 7 days, medium: 30 days)

### Security and Privacy
1. Do not expose sensitive instance details beyond what's necessary
2. Aggregate data when discussing large-scale statistics
3. Focus on compliance status rather than technical vulnerability details

## Example Interactions

User: "What's our SOC 2 patch compliance status for Q4 2025?"

Response Structure:
1. Query execution history for Q4 2025
2. Calculate overall compliance rate
3. Map to SOC 2 controls (CC6.1, CC7.1, CC7.2, CC8.1)
4. Identify any gaps or failures
5. Provide evidence references
6. Offer recommendations

User: "Which instances haven't been patched in the last 30 days?"

Response Structure:
1. Query for unpatched instances with 30-day threshold
2. Group by account and region
3. Highlight any critical systems
4. Provide count and list (limited for readability)
5. Recommend remediation actions

## Current Context

- Platform: EC2 Patching Orchestrator (Hub-Spoke Architecture)
- Coverage: 50+ AWS accounts, 1000s of EC2 instances
- Patching Frequency: Weekly maintenance windows (Sundays, 2 AM UTC default)
- SLAs: Critical (48h), High (7d), Medium (30d), Low (90d)
- Artifacts Location: S3 bucket `${SnapshotsBucket}` under `runs/{executionId}/`
```

---

## 5. Knowledge Base Integration

### 5.1 Knowledge Base Sources

| Source | Index | Use Case |
|--------|-------|----------|
| Patch Artifacts (S3) | `patch-artifacts` | Evidence retrieval, output analysis |
| Execution Records (DDB) | `execution-records` | History queries, statistics |
| Compliance Frameworks (S3) | `compliance-frameworks` | Control mapping, requirements |
| Operational Docs (Git) | `operational-docs` | Procedures, troubleshooting |

### 5.2 Retrieval Configuration

```yaml
RetrievalConfiguration:
  vectorSearchConfiguration:
    numberOfResults: 15
    overrideSearchType: HYBRID
  
  filterConfiguration:
    # Filter by recency for time-sensitive queries
    andAll:
      - greaterThan:
          key: "timestamp"
          value: "${dynamicTimestamp}"  # Calculated based on query
```

### 5.3 Example RAG Queries

**Query:** "Show me patch failures for account 222222222222 in January 2026"

**Retrieval:**
```json
{
  "retrievalQuery": {
    "text": "patch failures account 222222222222 January 2026"
  },
  "retrievalConfiguration": {
    "vectorSearchConfiguration": {
      "numberOfResults": 10,
      "filter": {
        "andAll": [
          { "equals": { "key": "account_id", "value": "222222222222" } },
          { "equals": { "key": "status", "value": "failed" } },
          { "greaterThanOrEquals": { "key": "timestamp", "value": "2026-01-01" } },
          { "lessThanOrEquals": { "key": "timestamp", "value": "2026-01-31" } }
        ]
      }
    }
  }
}
```

---

## 6. Guardrails Configuration

### 6.1 Content Filters

```yaml
GuardrailConfiguration:
  name: audit-compliance-guardrails
  blockedInputMessaging: "I can't help with that request as it's outside my audit and compliance scope."
  blockedOutputsMessaging: "I'm unable to provide that information due to policy restrictions."
  
  contentPolicyConfig:
    filtersConfig:
      - type: HATE
        inputStrength: HIGH
        outputStrength: HIGH
      - type: INSULTS
        inputStrength: HIGH
        outputStrength: HIGH
      - type: SEXUAL
        inputStrength: HIGH
        outputStrength: HIGH
      - type: VIOLENCE
        inputStrength: HIGH
        outputStrength: HIGH
  
  topicPolicyConfig:
    topicsConfig:
      - name: off-topic-requests
        definition: "Requests not related to patch compliance, audit, or EC2 patching operations"
        examples:
          - "Tell me about AWS pricing"
          - "How do I deploy a Lambda function?"
          - "What's the weather today?"
        type: DENY
  
  sensitiveInformationPolicyConfig:
    piiEntitiesConfig:
      - type: EMAIL
        action: ANONYMIZE
      - type: PHONE
        action: ANONYMIZE
      - type: NAME
        action: ANONYMIZE
      - type: AWS_ACCESS_KEY
        action: BLOCK
      - type: AWS_SECRET_KEY
        action: BLOCK
```

### 6.2 Word Filters

```yaml
WordPolicyConfig:
  wordsConfig:
    - text: "password"
    - text: "secret"
    - text: "credential"
  managedWordListsConfig:
    - type: PROFANITY
```

---

## 7. Sample Conversations

### 7.1 Compliance Status Query

**User:** What's our overall patch compliance status for the last 30 days?

**Agent Response:**
```
## Patch Compliance Summary (Last 30 Days)

Based on my analysis of patch execution records from December 15, 2025 to January 14, 2026:

### Overall Statistics

| Metric | Value |
|--------|-------|
| **Overall Compliance Rate** | 94.2% |
| **Total Executions** | 48 |
| **Successful** | 45 |
| **Partial** | 2 |
| **Failed** | 1 |
| **Instances Patched** | 2,847 |
| **Patches Installed** | 12,456 |

### Compliance by Account

| Account | Compliance Rate | Instances | Status |
|---------|-----------------|-----------|--------|
| 111111111111 | 100% | 234 | ✅ Compliant |
| 222222222222 | 96.5% | 456 | ✅ Compliant |
| 333333333333 | 87.2% | 312 | ⚠️ Review Needed |
| 444444444444 | 100% | 189 | ✅ Compliant |

### Findings

1. **Account 333333333333** has a lower compliance rate due to 3 instance failures in us-west-2 on January 8, 2026.
   - Root cause: SSM Agent connectivity issues
   - Evidence: `s3://ec2-patch-prod-snapshots/runs/ex-20260108-wave3/custom-patch/account-333333333333/region-us-west-2/`

### Recommendations

1. Investigate SSM Agent health in Account 333333333333 / us-west-2
2. Review failed instances: i-0abc123, i-0def456, i-0ghi789
3. Consider adding pre-patch SSM Agent validation

Would you like me to generate a detailed compliance report or investigate the failed instances?
```

### 7.2 Audit Report Generation

**User:** Generate a SOC 2 compliance report for Q4 2025

**Agent Response:**
```
## SOC 2 Patch Compliance Report - Q4 2025

**Report Generated:** January 14, 2026  
**Period:** October 1, 2025 - December 31, 2025  
**Framework:** SOC 2 Type II  

---

### Executive Summary

The EC2 Patching Platform maintained **97.3% compliance** with SOC 2 patch-related 
controls during Q4 2025. All critical and high-severity patches were applied within 
SLA requirements.

### Control Assessment

| Control | Requirement | Status | Evidence |
|---------|-------------|--------|----------|
| **CC6.1** | Logical Access Controls | ✅ Compliant | 156 patch runs with access logging |
| **CC7.1** | Security Configuration | ✅ Compliant | Pre/post verification enabled |
| **CC7.2** | Incident Detection | ✅ Compliant | Failure alerting operational |
| **CC8.1** | Change Management | ✅ Compliant | All patches follow workflow |

### Detailed Findings

#### CC6.1 - Logical and Physical Access Controls
- **Status:** COMPLIANT
- **Evidence:** All patch operations executed via cross-account IAM roles with external ID verification
- **Execution Count:** 156 patch waves
- **Evidence Path:** `s3://ec2-patch-prod-snapshots/runs/*/`

#### CC7.1 - System Operations
- **Status:** COMPLIANT
- **Evidence:** 100% of patch runs include pre-collection and post-verification steps
- **Monitoring:** CloudWatch dashboards and alarms operational
- **Evidence Path:** CloudWatch Dashboard `ec2-patch-prod-orchestrator`

#### CC7.2 - Incident Detection
- **Status:** COMPLIANT
- **Evidence:** 8 patch failures detected and alerted within 5 minutes
- **Mean Time to Detect:** 3.2 minutes
- **Alert Channel:** SNS Topic `ec2-patch-prod-notifications`

#### CC8.1 - Change Management
- **Status:** COMPLIANT
- **Evidence:** All patches executed via Step Functions with full audit trail
- **Approval Process:** Scheduled maintenance windows with pre-defined scope
- **Evidence Path:** Step Functions execution history

### Statistics Summary

| Metric | Value |
|--------|-------|
| Total Patch Waves | 156 |
| Successful Waves | 151 |
| Partial Success | 4 |
| Failed Waves | 1 |
| Instances Patched | 8,234 |
| Patches Installed | 34,567 |
| Avg Wave Duration | 42 minutes |
| SLA Adherence | 99.1% |

### Recommendations

1. Continue current patch management practices
2. Implement additional pre-patch validation for high-failure accounts
3. Consider reducing patch wave concurrency to improve reliability

---

**Report stored at:** `s3://ec2-patch-prod-snapshots/compliance-reports/soc2-q4-2025.md`

Would you like me to generate an evidence pack with detailed execution logs?
```

---

## 8. IAM Permissions

### 8.1 Agent Execution Role

```yaml
AgentExecutionRole:
  Type: AWS::IAM::Role
  Properties:
    RoleName: !Sub '${NamePrefix}-${Environment}-audit-agent-role'
    AssumeRolePolicyDocument:
      Version: '2012-10-17'
      Statement:
        - Effect: Allow
          Principal:
            Service: bedrock.amazonaws.com
          Action: sts:AssumeRole
    Policies:
      - PolicyName: AuditAgentPolicy
        PolicyDocument:
          Version: '2012-10-17'
          Statement:
            # DynamoDB Read Access
            - Effect: Allow
              Action:
                - dynamodb:Query
                - dynamodb:Scan
                - dynamodb:GetItem
              Resource:
                - !Sub 'arn:aws:dynamodb:${AWS::Region}:${AWS::AccountId}:table/${PatchRunsTable}'
                - !Sub 'arn:aws:dynamodb:${AWS::Region}:${AWS::AccountId}:table/${PatchRunsTable}/index/*'
            
            # S3 Read Access
            - Effect: Allow
              Action:
                - s3:GetObject
                - s3:ListBucket
              Resource:
                - !Sub 'arn:aws:s3:::${SnapshotsBucket}'
                - !Sub 'arn:aws:s3:::${SnapshotsBucket}/*'
            
            # S3 Write for Reports
            - Effect: Allow
              Action:
                - s3:PutObject
              Resource:
                - !Sub 'arn:aws:s3:::${SnapshotsBucket}/compliance-reports/*'
            
            # CloudWatch Read Access
            - Effect: Allow
              Action:
                - cloudwatch:GetMetricData
                - cloudwatch:GetMetricStatistics
                - cloudwatch:ListMetrics
              Resource: '*'
              Condition:
                StringEquals:
                  cloudwatch:namespace:
                    - 'EC2Patching/Orchestrator'
                    - 'AWS/States'
                    - 'AWS/Lambda'
            
            # Step Functions Describe
            - Effect: Allow
              Action:
                - states:DescribeExecution
                - states:GetExecutionHistory
                - states:ListExecutions
              Resource:
                - !Sub 'arn:aws:states:${AWS::Region}:${AWS::AccountId}:stateMachine:${NamePrefix}-${Environment}-orchestrator'
                - !Sub 'arn:aws:states:${AWS::Region}:${AWS::AccountId}:execution:${NamePrefix}-${Environment}-orchestrator:*'
            
            # SSM Describe (read-only)
            - Effect: Allow
              Action:
                - ssm:DescribeInstancePatchStates
                - ssm:DescribeInstancePatchStatesForPatchGroup
                - ssm:ListCommands
                - ssm:ListCommandInvocations
              Resource: '*'
            
            # OpenSearch Read Access
            - Effect: Allow
              Action:
                - aoss:APIAccessAll
              Resource:
                - !Sub 'arn:aws:aoss:${AWS::Region}:${AWS::AccountId}:collection/*'
            
            # Bedrock Permissions
            - Effect: Allow
              Action:
                - bedrock:InvokeModel
              Resource:
                - 'arn:aws:bedrock:*::foundation-model/anthropic.claude-3-sonnet*'
                - 'arn:aws:bedrock:*::foundation-model/amazon.titan-embed-text-v2*'
            
            # Knowledge Base Access
            - Effect: Allow
              Action:
                - bedrock:Retrieve
                - bedrock:RetrieveAndGenerate
              Resource:
                - !Sub 'arn:aws:bedrock:${AWS::Region}:${AWS::AccountId}:knowledge-base/*'
```

---

## 9. Deployment

### 9.1 CloudFormation Snippet

```yaml
AuditComplianceAgent:
  Type: AWS::Bedrock::Agent
  Properties:
    AgentName: !Sub '${NamePrefix}-${Environment}-audit-compliance-agent'
    Description: 'Audit and Compliance Agent for EC2 Patching Platform'
    AgentResourceRoleArn: !GetAtt AuditAgentRole.Arn
    FoundationModel: 'anthropic.claude-3-sonnet-20240229-v1:0'
    IdleSessionTTLInSeconds: 1800
    Instruction: !Sub |
      ${AuditAgentSystemPrompt}
    
    KnowledgeBases:
      - KnowledgeBaseId: !Ref PatchingKnowledgeBase
        Description: 'Patch execution history and artifacts'
        KnowledgeBaseState: ENABLED
    
    ActionGroups:
      - ActionGroupName: compliance-queries
        ActionGroupExecutor:
          Lambda: !GetAtt ComplianceQueriesFunction.Arn
        ApiSchema:
          S3:
            S3BucketName: !Ref ArtifactBucket
            S3ObjectKey: 'agent-schemas/compliance-queries.yaml'
      
      - ActionGroupName: compliance-reports
        ActionGroupExecutor:
          Lambda: !GetAtt ComplianceReportsFunction.Arn
        ApiSchema:
          S3:
            S3BucketName: !Ref ArtifactBucket
            S3ObjectKey: 'agent-schemas/compliance-reports.yaml'
    
    GuardrailConfiguration:
      GuardrailIdentifier: !Ref AuditAgentGuardrail
      GuardrailVersion: DRAFT

AuditAgentAlias:
  Type: AWS::Bedrock::AgentAlias
  Properties:
    AgentAliasName: 'prod'
    AgentId: !Ref AuditComplianceAgent
    Description: 'Production alias for Audit Compliance Agent'
```

---

## 10. Testing

### 10.1 Test Cases

| Test Case | Input | Expected Output |
|-----------|-------|-----------------|
| Basic Status Query | "What's our patch status?" | Compliance summary with stats |
| Time-Bounded Query | "Show failures in January 2026" | Filtered execution list |
| Account-Specific | "Compliance for account 123456789012" | Account-specific metrics |
| Report Generation | "Generate SOC 2 report for Q4" | Formatted compliance report |
| Evidence Retrieval | "Get evidence for execution ex-123" | S3 paths and content preview |
| SLA Violation | "Which instances missed SLA?" | Unpatched instance list |

### 10.2 Validation Queries

```python
# Test harness for Audit Agent
import boto3

bedrock_agent = boto3.client('bedrock-agent-runtime')

test_queries = [
    "What is the overall patch compliance rate for the last 30 days?",
    "Show me all failed patch executions in us-east-1",
    "Generate an executive summary for SOC 2 compliance",
    "Which accounts have the lowest patch compliance?",
    "Get detailed evidence for execution ex-20260114-wave1"
]

for query in test_queries:
    response = bedrock_agent.invoke_agent(
        agentId='AGENT_ID',
        agentAliasId='ALIAS_ID',
        sessionId='test-session',
        inputText=query
    )
    print(f"Query: {query}")
    print(f"Response: {response['completion']}\n")
```

---

*Next: Agent 2 - Reporting & Analytics Agent Technical Design*
