# Agent 3: Anomaly Detection & Root Cause Analysis Agent - Technical Design

## Document Information
| Attribute | Value |
|-----------|-------|
| Version | 1.0 |
| Last Updated | January 14, 2026 |
| Status | Draft |
| Owner | Platform Engineering |
| Agent ID | `anomaly-detection-agent` |

---

## 1. Executive Summary

The **Anomaly Detection & Root Cause Analysis Agent** is a specialized diagnostic agent that proactively identifies unusual patterns in patching operations and assists with root cause analysis during incidents. This agent requires **higher reasoning capabilities** and uses Claude 3 Opus for complex correlation and analysis tasks.

### 1.1 Key Capabilities

| Capability | Description | Priority |
|------------|-------------|----------|
| Pattern Detection | Identify unusual failure patterns | P0 |
| Root Cause Analysis | Correlate failures to likely causes | P0 |
| Proactive Alerting | Alert on emerging issues before escalation | P0 |
| Error Correlation | Link related failures across time/scope | P1 |
| Trend Anomalies | Detect statistical anomalies in metrics | P1 |
| Historical Comparison | Compare current behavior to baselines | P2 |

### 1.2 Differentiation from Other Agents

| Aspect | Audit Agent | Reporting Agent | Anomaly Agent |
|--------|-------------|-----------------|---------------|
| Focus | Compliance evidence | Metrics & reports | Problem detection |
| Model | Claude 3 Sonnet | Claude 3 Sonnet | **Claude 3 Opus** |
| Temperature | 0.1 (factual) | 0.2 (balanced) | **0.3 (reasoning)** |
| Mode | Reactive (queries) | Reactive (reports) | **Proactive + Reactive** |
| Output | Evidence, reports | Summaries, charts | Diagnoses, RCAs |

---

## 2. Architecture

```
┌──────────────────────────────────────────────────────────────────────────────────────┐
│                    ANOMALY DETECTION & ROOT CAUSE ANALYSIS AGENT                      │
│                                                                                       │
│  ┌─────────────────────────────────────────────────────────────────────────────────┐ │
│  │                              AGENT CORE                                          │ │
│  │  Model: anthropic.claude-3-opus-20240229-v1:0                                   │ │
│  │  Temperature: 0.3 (enhanced reasoning)                                          │ │
│  │  Max Tokens: 16384 (detailed analysis)                                          │ │
│  └─────────────────────────────────────────────────────────────────────────────────┘ │
│                                        │                                              │
│         ┌──────────────────────────────┼──────────────────────────────┐               │
│         │                              │                              │               │
│         ▼                              ▼                              ▼               │
│  ┌─────────────────┐     ┌────────────────────────┐    ┌─────────────────────────┐  │
│  │ KNOWLEDGE BASES │     │     ACTION GROUPS       │    │    ANOMALY ENGINE       │  │
│  │                 │     │                         │    │                         │  │
│  │ • error-patterns│     │ • Anomaly Detection     │    │ • Statistical Models    │  │
│  │ • patch-artifacts│    │ • Correlation Engine    │    │ • Pattern Matching      │  │
│  │ • operational-docs│   │ • RCA Generator         │    │ • Baseline Comparison   │  │
│  │ • troubleshoot-kb│    │ • Alert Manager         │    │ • ML Anomaly Scoring    │  │
│  └─────────────────┘     └────────────────────────┘    └─────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────────────────────┘
                                        │
                                        ▼
┌──────────────────────────────────────────────────────────────────────────────────────┐
│                            ANOMALY DETECTION PIPELINE                                 │
│                                                                                       │
│  ┌───────────────────────────────────────────────────────────────────────────────┐  │
│  │                         REAL-TIME STREAM PROCESSOR                             │  │
│  │                                                                                │  │
│  │  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐    ┌─────────────┐ │  │
│  │  │ CloudWatch   │───▶│ Kinesis      │───▶│ Lambda       │───▶│ OpenSearch  │ │  │
│  │  │ Log Insights │    │ Data Stream  │    │ Processor    │    │ Serverless  │ │  │
│  │  └──────────────┘    └──────────────┘    └──────────────┘    └─────────────┘ │  │
│  │                                                                                │  │
│  └───────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                       │
│  ┌─────────────────────────────────────────────────────────────────────────────────┐│
│  │                          ANOMALY DETECTION MODELS                                ││
│  │                                                                                  ││
│  │  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────────────────┐  ││
│  │  │ Statistical       │  │ Pattern-Based    │  │ ML-Based (SageMaker)        │  ││
│  │  │ • Z-Score         │  │ • Error Regex    │  │ • Isolation Forest          │  ││
│  │  │ • IQR Detection   │  │ • Sequence Match │  │ • LSTM Anomaly Detection    │  ││
│  │  │ • Moving Average  │  │ • Signature DB   │  │ • Clustering                │  ││
│  │  └──────────────────┘  └──────────────────┘  └──────────────────────────────┘  ││
│  │                                                                                  ││
│  └─────────────────────────────────────────────────────────────────────────────────┘│
└──────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Error Pattern Knowledge Base

### 3.1 Error Signature Database

The agent maintains a knowledge base of known error patterns:

```yaml
OpenSearchIndex: error-patterns

Mappings:
  properties:
    pattern_id:
      type: keyword
    error_signature:
      type: text
      analyzer: standard
    error_regex:
      type: keyword
    category:
      type: keyword
      # Values: ssm_agent, network, permission, resource, timeout, configuration
    severity:
      type: keyword
      # Values: critical, high, medium, low
    root_causes:
      type: nested
      properties:
        cause:
          type: text
        probability:
          type: float
        remediation:
          type: text
    affected_components:
      type: keyword
    os_types:
      type: keyword
    first_seen:
      type: date
    last_seen:
      type: date
    occurrence_count:
      type: integer
    embedding:
      type: knn_vector
      dimension: 1024
```

### 3.2 Pre-populated Error Patterns

```json
{
  "error_patterns": [
    {
      "pattern_id": "SSM-AGENT-001",
      "error_signature": "Unable to reach SSM agent",
      "error_regex": "(SSM agent.*not responding|Unable to.*reach.*agent|InvocationDoesNotExist)",
      "category": "ssm_agent",
      "severity": "high",
      "root_causes": [
        {
          "cause": "SSM agent service not running",
          "probability": 0.45,
          "remediation": "Restart SSM agent: systemctl restart amazon-ssm-agent (Linux) or Restart-Service AmazonSSMAgent (Windows)"
        },
        {
          "cause": "Instance lost network connectivity to SSM endpoints",
          "probability": 0.30,
          "remediation": "Check security groups, NACLs, and route tables for SSM VPC endpoints"
        },
        {
          "cause": "IAM instance profile missing SSM permissions",
          "probability": 0.15,
          "remediation": "Attach AmazonSSMManagedInstanceCore policy to instance profile"
        },
        {
          "cause": "SSM agent version outdated",
          "probability": 0.10,
          "remediation": "Update SSM agent to latest version"
        }
      ],
      "affected_components": ["SSM Agent", "Instance", "Network"],
      "os_types": ["linux", "windows"]
    },
    {
      "pattern_id": "REBOOT-001",
      "error_signature": "Reboot timeout exceeded",
      "error_regex": "(Reboot.*timeout|Instance.*not.*respond.*after.*reboot|WaitForReboot.*failed)",
      "category": "timeout",
      "severity": "medium",
      "root_causes": [
        {
          "cause": "Instance hung during reboot process",
          "probability": 0.40,
          "remediation": "Force stop and start instance via EC2 API"
        },
        {
          "cause": "Disk check (fsck) running on boot",
          "probability": 0.25,
          "remediation": "Wait for disk check to complete or extend timeout"
        },
        {
          "cause": "Large number of patches requiring extended reboot",
          "probability": 0.20,
          "remediation": "Increase reboot timeout in SSM document"
        },
        {
          "cause": "Boot configuration issue",
          "probability": 0.15,
          "remediation": "Check boot logs via EC2 Serial Console"
        }
      ],
      "affected_components": ["EC2", "OS"],
      "os_types": ["linux", "windows"]
    },
    {
      "pattern_id": "PATCH-CONFLICT-001",
      "error_signature": "Package dependency conflict",
      "error_regex": "(dependency.*conflict|requires.*but.*installed|unmet dependencies|package.*breaks)",
      "category": "configuration",
      "severity": "high",
      "root_causes": [
        {
          "cause": "Third-party repository conflicting with OS updates",
          "probability": 0.50,
          "remediation": "Disable third-party repos during patching or resolve conflicts manually"
        },
        {
          "cause": "Pinned package versions preventing updates",
          "probability": 0.30,
          "remediation": "Review and update package holds/pins"
        },
        {
          "cause": "Corrupted package database",
          "probability": 0.20,
          "remediation": "Rebuild package cache: apt-get update --fix-missing (Debian) or yum clean all (RHEL)"
        }
      ],
      "affected_components": ["Package Manager", "OS"],
      "os_types": ["linux"]
    }
  ]
}
```

---

## 4. Action Groups (Tools)

### 4.1 Action Group: `anomaly-detection`

#### 4.1.1 Tool: `detect_anomalies`

**Purpose:** Detect anomalies in recent patching operations

**OpenAPI Schema:**
```yaml
openapi: 3.0.0
info:
  title: Anomaly Detection API
  version: 1.0.0

paths:
  /detect-anomalies:
    post:
      operationId: detectAnomalies
      summary: Detect anomalies in patching operations
      description: |
        Analyzes recent patching operations to identify anomalies
        using statistical and pattern-based detection methods.
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              properties:
                scope:
                  type: string
                  enum: [all, account, region, execution]
                  description: Scope of anomaly detection
                scopeId:
                  type: string
                  description: Account ID, region name, or execution ID
                timeWindow:
                  type: string
                  enum: [1h, 6h, 24h, 7d, 30d]
                  default: 24h
                anomalyTypes:
                  type: array
                  items:
                    type: string
                    enum:
                      - failure_spike
                      - duration_anomaly
                      - error_pattern
                      - success_rate_drop
                      - unusual_timing
                  description: Types of anomalies to detect
                sensitivityLevel:
                  type: string
                  enum: [low, medium, high]
                  default: medium
                  description: Detection sensitivity (high = more alerts)
              required:
                - timeWindow
      responses:
        '200':
          description: Detected anomalies
          content:
            application/json:
              schema:
                type: object
                properties:
                  anomalies:
                    type: array
                    items:
                      type: object
                      properties:
                        anomalyId:
                          type: string
                        type:
                          type: string
                        severity:
                          type: string
                          enum: [critical, high, medium, low]
                        detectedAt:
                          type: string
                        scope:
                          type: object
                        description:
                          type: string
                        metrics:
                          type: object
                          properties:
                            expected:
                              type: number
                            actual:
                              type: number
                            deviation:
                              type: number
                        affectedExecutions:
                          type: array
                          items:
                            type: string
                        confidenceScore:
                          type: number
                  summary:
                    type: object
                    properties:
                      totalAnomalies:
                        type: integer
                      bySeverity:
                        type: object
                      byType:
                        type: object
```

**Lambda Handler:**
```python
"""
Anomaly Detection Engine
Identifies unusual patterns in patching operations
"""

import json
import boto3
import numpy as np
from datetime import datetime, timedelta
from typing import Dict, Any, List
from dataclasses import dataclass
from enum import Enum
import uuid

dynamodb = boto3.resource('dynamodb')
cloudwatch = boto3.client('cloudwatch')
opensearch = boto3.client('opensearch')

SENSITIVITY_THRESHOLDS = {
    'low': {'z_score': 3.0, 'iqr_multiplier': 2.5},
    'medium': {'z_score': 2.5, 'iqr_multiplier': 2.0},
    'high': {'z_score': 2.0, 'iqr_multiplier': 1.5}
}


@dataclass
class Anomaly:
    anomaly_id: str
    anomaly_type: str
    severity: str
    detected_at: str
    scope: dict
    description: str
    metrics: dict
    affected_executions: List[str]
    confidence_score: float


def handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """Detect anomalies in patching operations"""
    
    params = event.get('requestBody', {}).get('content', {}).get('application/json', {})
    
    scope = params.get('scope', 'all')
    scope_id = params.get('scopeId')
    time_window = params.get('timeWindow', '24h')
    anomaly_types = params.get('anomalyTypes', ['failure_spike', 'duration_anomaly', 'success_rate_drop'])
    sensitivity = params.get('sensitivityLevel', 'medium')
    
    # Calculate time range
    end_time = datetime.utcnow()
    start_time = calculate_start_time(time_window, end_time)
    
    # Get threshold config
    thresholds = SENSITIVITY_THRESHOLDS[sensitivity]
    
    anomalies = []
    
    # Detect different anomaly types
    if 'failure_spike' in anomaly_types:
        anomalies.extend(detect_failure_spikes(start_time, end_time, scope, scope_id, thresholds))
    
    if 'duration_anomaly' in anomaly_types:
        anomalies.extend(detect_duration_anomalies(start_time, end_time, scope, scope_id, thresholds))
    
    if 'success_rate_drop' in anomaly_types:
        anomalies.extend(detect_success_rate_drops(start_time, end_time, scope, scope_id, thresholds))
    
    if 'error_pattern' in anomaly_types:
        anomalies.extend(detect_error_patterns(start_time, end_time, scope, scope_id))
    
    # Sort by severity and confidence
    anomalies.sort(key=lambda a: (
        {'critical': 0, 'high': 1, 'medium': 2, 'low': 3}[a.severity],
        -a.confidence_score
    ))
    
    # Generate summary
    summary = {
        'totalAnomalies': len(anomalies),
        'bySeverity': {},
        'byType': {}
    }
    for a in anomalies:
        summary['bySeverity'][a.severity] = summary['bySeverity'].get(a.severity, 0) + 1
        summary['byType'][a.anomaly_type] = summary['byType'].get(a.anomaly_type, 0) + 1
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'anomalies': [vars(a) for a in anomalies],
            'summary': summary
        })
    }


def detect_failure_spikes(start: datetime, end: datetime, scope: str, 
                          scope_id: str, thresholds: dict) -> List[Anomaly]:
    """Detect sudden spikes in failure rates"""
    
    # Get baseline metrics (previous 30 days)
    baseline_start = start - timedelta(days=30)
    baseline_metrics = get_failure_metrics(baseline_start, start, scope, scope_id)
    
    # Get current metrics
    current_metrics = get_failure_metrics(start, end, scope, scope_id)
    
    anomalies = []
    
    # Calculate baseline statistics
    if baseline_metrics:
        baseline_mean = np.mean(baseline_metrics)
        baseline_std = np.std(baseline_metrics) or 1  # Avoid division by zero
        
        for i, current_val in enumerate(current_metrics):
            z_score = (current_val - baseline_mean) / baseline_std
            
            if z_score > thresholds['z_score']:
                anomalies.append(Anomaly(
                    anomaly_id=f"FS-{uuid.uuid4().hex[:8]}",
                    anomaly_type='failure_spike',
                    severity=calculate_severity(z_score),
                    detected_at=datetime.utcnow().isoformat(),
                    scope={'type': scope, 'id': scope_id} if scope_id else {'type': scope},
                    description=f"Failure rate spiked to {current_val:.1f}% (baseline: {baseline_mean:.1f}%)",
                    metrics={
                        'expected': round(baseline_mean, 2),
                        'actual': round(current_val, 2),
                        'deviation': round(z_score, 2)
                    },
                    affected_executions=[],  # Would be populated from actual data
                    confidence_score=min(0.95, 0.5 + (z_score - thresholds['z_score']) * 0.15)
                ))
    
    return anomalies


def detect_duration_anomalies(start: datetime, end: datetime, scope: str,
                              scope_id: str, thresholds: dict) -> List[Anomaly]:
    """Detect unusual execution durations"""
    
    # Get duration data
    durations = get_execution_durations(start, end, scope, scope_id)
    
    anomalies = []
    
    if len(durations) >= 10:  # Need sufficient data
        # Use IQR method for duration anomalies
        q1 = np.percentile(durations, 25)
        q3 = np.percentile(durations, 75)
        iqr = q3 - q1
        upper_bound = q3 + thresholds['iqr_multiplier'] * iqr
        lower_bound = q1 - thresholds['iqr_multiplier'] * iqr
        
        for duration, exec_id in durations:
            if duration > upper_bound:
                deviation = (duration - np.median(durations)) / (iqr or 1)
                anomalies.append(Anomaly(
                    anomaly_id=f"DA-{uuid.uuid4().hex[:8]}",
                    anomaly_type='duration_anomaly',
                    severity='medium' if duration < upper_bound * 1.5 else 'high',
                    detected_at=datetime.utcnow().isoformat(),
                    scope={'type': 'execution', 'id': exec_id},
                    description=f"Execution duration {duration/60:.0f} min exceeds normal range (median: {np.median(durations)/60:.0f} min)",
                    metrics={
                        'expected': round(np.median(durations) / 60, 1),
                        'actual': round(duration / 60, 1),
                        'deviation': round(deviation, 2)
                    },
                    affected_executions=[exec_id],
                    confidence_score=min(0.9, 0.6 + deviation * 0.1)
                ))
    
    return anomalies


def detect_error_patterns(start: datetime, end: datetime, scope: str,
                         scope_id: str) -> List[Anomaly]:
    """Detect unusual error patterns using signature matching"""
    
    # Get recent errors from logs
    errors = get_recent_errors(start, end, scope, scope_id)
    
    # Match against known error patterns
    pattern_matches = match_error_patterns(errors)
    
    anomalies = []
    
    # Group errors by pattern and look for unusual frequencies
    pattern_counts = {}
    for error, pattern_id in pattern_matches:
        pattern_counts[pattern_id] = pattern_counts.get(pattern_id, 0) + 1
    
    for pattern_id, count in pattern_counts.items():
        # Get historical frequency
        historical_freq = get_pattern_historical_frequency(pattern_id)
        
        if count > historical_freq * 2:  # More than 2x historical frequency
            pattern_info = get_pattern_info(pattern_id)
            anomalies.append(Anomaly(
                anomaly_id=f"EP-{uuid.uuid4().hex[:8]}",
                anomaly_type='error_pattern',
                severity=pattern_info.get('severity', 'medium'),
                detected_at=datetime.utcnow().isoformat(),
                scope={'type': scope, 'id': scope_id} if scope_id else {'type': scope},
                description=f"Error pattern '{pattern_info.get('error_signature', pattern_id)}' occurring {count}x (historical avg: {historical_freq:.1f}x)",
                metrics={
                    'expected': round(historical_freq, 1),
                    'actual': count,
                    'deviation': round((count - historical_freq) / (historical_freq or 1), 2)
                },
                affected_executions=get_affected_executions(pattern_id, start, end),
                confidence_score=0.85
            ))
    
    return anomalies


def calculate_severity(z_score: float) -> str:
    """Calculate severity based on z-score"""
    if z_score > 4:
        return 'critical'
    elif z_score > 3:
        return 'high'
    elif z_score > 2.5:
        return 'medium'
    else:
        return 'low'
```

#### 4.1.2 Tool: `analyze_root_cause`

**Purpose:** Perform root cause analysis for failures

**OpenAPI Schema:**
```yaml
paths:
  /analyze-root-cause:
    post:
      operationId: analyzeRootCause
      summary: Perform root cause analysis
      description: |
        Analyzes failures to identify probable root causes using
        pattern matching, correlation, and AI-powered reasoning.
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              properties:
                executionId:
                  type: string
                  description: Specific execution to analyze
                instanceIds:
                  type: array
                  items:
                    type: string
                  description: Specific instances to analyze
                errorMessage:
                  type: string
                  description: Error message to analyze
                timeRange:
                  type: object
                  properties:
                    start:
                      type: string
                    end:
                      type: string
                includeRemediation:
                  type: boolean
                  default: true
                  description: Include remediation suggestions
                correlateWithInfra:
                  type: boolean
                  default: true
                  description: Correlate with infrastructure events
              anyOf:
                - required: [executionId]
                - required: [instanceIds]
                - required: [errorMessage]
      responses:
        '200':
          description: Root cause analysis
          content:
            application/json:
              schema:
                type: object
                properties:
                  analysis:
                    type: object
                    properties:
                      summary:
                        type: string
                      rootCauses:
                        type: array
                        items:
                          type: object
                          properties:
                            cause:
                              type: string
                            probability:
                              type: number
                            evidence:
                              type: array
                              items:
                                type: string
                            category:
                              type: string
                            remediation:
                              type: object
                              properties:
                                steps:
                                  type: array
                                  items:
                                    type: string
                                automated:
                                  type: boolean
                                automationId:
                                  type: string
                      timeline:
                        type: array
                        items:
                          type: object
                          properties:
                            timestamp:
                              type: string
                            event:
                              type: string
                            significance:
                              type: string
                      correlatedEvents:
                        type: array
                        items:
                          type: object
                      affectedComponents:
                        type: array
                        items:
                          type: string
                      confidence:
                        type: number
```

**Lambda Handler:**
```python
"""
Root Cause Analysis Engine
Analyzes failures to identify probable root causes
"""

import json
import boto3
import re
from datetime import datetime, timedelta
from typing import Dict, Any, List, Tuple
from opensearchpy import OpenSearch

dynamodb = boto3.resource('dynamodb')
cloudwatch = boto3.client('cloudwatch')
cloudtrail = boto3.client('cloudtrail')
ssm = boto3.client('ssm')

# Initialize OpenSearch client
opensearch_client = OpenSearch(
    hosts=[{'host': os.environ['OPENSEARCH_ENDPOINT'], 'port': 443}],
    use_ssl=True
)


def handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """Perform root cause analysis"""
    
    params = event.get('requestBody', {}).get('content', {}).get('application/json', {})
    
    execution_id = params.get('executionId')
    instance_ids = params.get('instanceIds', [])
    error_message = params.get('errorMessage')
    include_remediation = params.get('includeRemediation', True)
    correlate_infra = params.get('correlateWithInfra', True)
    
    # Gather context
    context_data = gather_analysis_context(execution_id, instance_ids, error_message)
    
    # Match known error patterns
    pattern_matches = match_known_patterns(context_data.get('errors', []))
    
    # Build event timeline
    timeline = build_event_timeline(context_data)
    
    # Correlate with infrastructure events
    correlated_events = []
    if correlate_infra:
        correlated_events = correlate_infrastructure_events(context_data, timeline)
    
    # Analyze and rank root causes
    root_causes = analyze_root_causes(context_data, pattern_matches, timeline, correlated_events)
    
    # Add remediation if requested
    if include_remediation:
        for cause in root_causes:
            cause['remediation'] = get_remediation_steps(cause)
    
    # Generate summary
    summary = generate_rca_summary(root_causes, context_data)
    
    # Calculate overall confidence
    confidence = calculate_analysis_confidence(root_causes, pattern_matches)
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'analysis': {
                'summary': summary,
                'rootCauses': root_causes,
                'timeline': timeline,
                'correlatedEvents': correlated_events,
                'affectedComponents': list(set(
                    comp for cause in root_causes 
                    for comp in cause.get('affected_components', [])
                )),
                'confidence': confidence
            }
        })
    }


def gather_analysis_context(execution_id: str, instance_ids: List[str], 
                           error_message: str) -> dict:
    """Gather all relevant context for analysis"""
    
    context = {
        'errors': [],
        'execution_details': None,
        'instance_states': [],
        'ssm_command_history': []
    }
    
    if execution_id:
        # Get execution details from DynamoDB
        context['execution_details'] = get_execution_details(execution_id)
        context['errors'] = get_execution_errors(execution_id)
        instance_ids = context['execution_details'].get('instance_ids', [])
    
    if error_message:
        context['errors'].append({'message': error_message, 'source': 'user_input'})
    
    for instance_id in instance_ids:
        # Get instance state from SSM
        context['instance_states'].append(get_instance_ssm_state(instance_id))
        # Get recent SSM command history
        context['ssm_command_history'].extend(get_ssm_command_history(instance_id))
    
    return context


def match_known_patterns(errors: List[dict]) -> List[dict]:
    """Match errors against known patterns in OpenSearch"""
    
    matches = []
    
    for error in errors:
        error_text = error.get('message', '')
        
        # Semantic search in error-patterns index
        search_body = {
            'size': 5,
            'query': {
                'bool': {
                    'should': [
                        {
                            'knn': {
                                'embedding': {
                                    'vector': get_embedding(error_text),
                                    'k': 5
                                }
                            }
                        },
                        {
                            'match': {
                                'error_signature': error_text
                            }
                        }
                    ]
                }
            }
        }
        
        response = opensearch_client.search(
            index='error-patterns',
            body=search_body
        )
        
        for hit in response['hits']['hits']:
            if hit['_score'] > 0.7:  # Threshold for match
                pattern = hit['_source']
                # Verify regex match
                if pattern.get('error_regex'):
                    if re.search(pattern['error_regex'], error_text, re.IGNORECASE):
                        matches.append({
                            'error': error_text,
                            'pattern': pattern,
                            'score': hit['_score']
                        })
    
    return matches


def analyze_root_causes(context: dict, pattern_matches: List[dict], 
                        timeline: List[dict], correlated_events: List[dict]) -> List[dict]:
    """Analyze and rank root causes"""
    
    root_causes = []
    
    # Add causes from pattern matches
    for match in pattern_matches:
        pattern = match['pattern']
        for cause_info in pattern.get('root_causes', []):
            root_causes.append({
                'cause': cause_info['cause'],
                'probability': cause_info['probability'] * match['score'],
                'evidence': [
                    f"Error matched pattern: {pattern['error_signature']}",
                    f"Match confidence: {match['score']:.0%}"
                ],
                'category': pattern['category'],
                'affected_components': pattern.get('affected_components', []),
                'pattern_id': pattern['pattern_id']
            })
    
    # Add causes from correlated infrastructure events
    for event in correlated_events:
        if event['type'] == 'security_group_change':
            root_causes.append({
                'cause': 'Security group modification may have blocked SSM connectivity',
                'probability': 0.6,
                'evidence': [
                    f"Security group change detected at {event['timestamp']}",
                    f"Changed by: {event['user']}",
                    f"Event: {event['description']}"
                ],
                'category': 'network',
                'affected_components': ['Security Group', 'Network']
            })
        elif event['type'] == 'instance_status_check_failed':
            root_causes.append({
                'cause': 'Instance health check failure indicates underlying instance issue',
                'probability': 0.75,
                'evidence': [
                    f"Status check failed at {event['timestamp']}",
                    f"Instance: {event['instance_id']}"
                ],
                'category': 'resource',
                'affected_components': ['EC2', 'Instance']
            })
    
    # Sort by probability
    root_causes.sort(key=lambda x: x['probability'], reverse=True)
    
    # Normalize probabilities to sum to 1
    total_prob = sum(c['probability'] for c in root_causes)
    if total_prob > 0:
        for cause in root_causes:
            cause['probability'] = round(cause['probability'] / total_prob, 2)
    
    return root_causes[:5]  # Return top 5 causes


def get_remediation_steps(cause: dict) -> dict:
    """Get remediation steps for a root cause"""
    
    category = cause.get('category', '')
    pattern_id = cause.get('pattern_id')
    
    remediation = {
        'steps': [],
        'automated': False,
        'automationId': None
    }
    
    if pattern_id:
        # Look up remediation from pattern database
        pattern = get_pattern_info(pattern_id)
        for rc in pattern.get('root_causes', []):
            if rc['cause'] == cause['cause']:
                remediation['steps'] = rc.get('remediation', '').split('; ')
                break
    
    # Check for automated remediation
    automation = get_automation_for_category(category)
    if automation:
        remediation['automated'] = True
        remediation['automationId'] = automation['document_id']
        remediation['steps'].insert(0, f"🤖 Automated remediation available: {automation['name']}")
    
    return remediation


def generate_rca_summary(root_causes: List[dict], context: dict) -> str:
    """Generate human-readable RCA summary"""
    
    if not root_causes:
        return "Unable to determine root cause from available evidence. Manual investigation recommended."
    
    top_cause = root_causes[0]
    
    summary = f"""
**Most Likely Root Cause** ({top_cause['probability']:.0%} probability):
{top_cause['cause']}

**Category:** {top_cause['category'].title()}
**Affected Components:** {', '.join(top_cause.get('affected_components', ['Unknown']))}

**Evidence:**
"""
    
    for evidence in top_cause.get('evidence', [])[:3]:
        summary += f"- {evidence}\n"
    
    if len(root_causes) > 1:
        summary += f"\n**Alternative Causes:** {', '.join(c['cause'] for c in root_causes[1:3])}"
    
    return summary.strip()
```

#### 4.1.3 Tool: `get_error_correlation`

**Purpose:** Correlate related errors across executions

**OpenAPI Schema:**
```yaml
paths:
  /error-correlation:
    post:
      operationId: getErrorCorrelation
      summary: Correlate related errors
      description: |
        Finds and correlates related errors across multiple executions
        to identify systemic issues.
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              properties:
                errorSignature:
                  type: string
                  description: Error signature or message to correlate
                timeRange:
                  type: string
                  enum: [24h, 7d, 30d, 90d]
                  default: 7d
                groupBy:
                  type: string
                  enum: [account, region, instance_type, ami, os_version]
                  default: account
              required:
                - errorSignature
      responses:
        '200':
          description: Error correlation results
          content:
            application/json:
              schema:
                type: object
                properties:
                  correlations:
                    type: array
                    items:
                      type: object
                      properties:
                        groupValue:
                          type: string
                        occurrences:
                          type: integer
                        firstSeen:
                          type: string
                        lastSeen:
                          type: string
                        affectedInstances:
                          type: array
                        trend:
                          type: string
                          enum: [increasing, stable, decreasing]
                  commonality:
                    type: object
                    description: Common attributes across affected instances
                  relatedErrors:
                    type: array
                    items:
                      type: object
```

---

## 5. Proactive Alerting System

### 5.1 Real-time Anomaly Detection Pipeline

```yaml
AnomalyDetectionPipeline:
  Type: AWS::StepFunctions::StateMachine
  Properties:
    StateMachineName: !Sub '${NamePrefix}-anomaly-detection-pipeline'
    Definition:
      StartAt: GetRecentMetrics
      States:
        GetRecentMetrics:
          Type: Task
          Resource: !GetAtt GetMetricsLambda.Arn
          Next: RunAnomalyDetection
        
        RunAnomalyDetection:
          Type: Task
          Resource: !GetAtt AnomalyDetectionLambda.Arn
          Next: CheckForAnomalies
        
        CheckForAnomalies:
          Type: Choice
          Choices:
            - Variable: "$.anomalyCount"
              NumericGreaterThan: 0
              Next: InvokeAnomalyAgent
          Default: Complete
        
        InvokeAnomalyAgent:
          Type: Task
          Resource: arn:aws:states:::bedrock:invokeAgent
          Parameters:
            agentId: !Ref AnomalyDetectionAgent
            agentAliasId: !Ref AnomalyDetectionAgentAlias
            sessionId.$: "$.sessionId"
            inputText.$: "States.Format('Analyze these anomalies and provide recommendations: {}', $.anomalies)"
          Next: ProcessAgentResponse
        
        ProcessAgentResponse:
          Type: Task
          Resource: !GetAtt ProcessResponseLambda.Arn
          Next: SendAlerts
        
        SendAlerts:
          Type: Task
          Resource: !GetAtt SendAlertsLambda.Arn
          End: true
        
        Complete:
          Type: Pass
          End: true
```

### 5.2 Alert Configuration

```python
"""
Alert Manager
Sends proactive alerts for detected anomalies
"""

import json
import boto3
from typing import Dict, Any, List

sns = boto3.client('sns')
events = boto3.client('events')

SEVERITY_CHANNELS = {
    'critical': {
        'sns_topic': 'arn:aws:sns:us-east-1:ACCOUNT:patching-critical-alerts',
        'pagerduty': True,
        'slack': '#patching-alerts-critical'
    },
    'high': {
        'sns_topic': 'arn:aws:sns:us-east-1:ACCOUNT:patching-high-alerts',
        'pagerduty': False,
        'slack': '#patching-alerts'
    },
    'medium': {
        'sns_topic': 'arn:aws:sns:us-east-1:ACCOUNT:patching-medium-alerts',
        'pagerduty': False,
        'slack': '#patching-alerts'
    }
}


def send_anomaly_alert(anomaly: Dict, analysis: Dict) -> Dict[str, Any]:
    """Send alert for detected anomaly"""
    
    severity = anomaly.get('severity', 'medium')
    channel_config = SEVERITY_CHANNELS.get(severity, SEVERITY_CHANNELS['medium'])
    
    # Format alert message
    message = format_alert_message(anomaly, analysis)
    
    # Send to SNS
    sns.publish(
        TopicArn=channel_config['sns_topic'],
        Subject=f"[{severity.upper()}] EC2 Patching Anomaly Detected",
        Message=message,
        MessageAttributes={
            'severity': {'DataType': 'String', 'StringValue': severity},
            'anomaly_type': {'DataType': 'String', 'StringValue': anomaly['type']},
            'scope': {'DataType': 'String', 'StringValue': json.dumps(anomaly['scope'])}
        }
    )
    
    # Send to EventBridge for downstream processing
    events.put_events(
        Entries=[{
            'Source': 'patching.anomaly-detection',
            'DetailType': 'Anomaly Detected',
            'Detail': json.dumps({
                'anomaly': anomaly,
                'analysis': analysis,
                'timestamp': anomaly['detectedAt']
            })
        }]
    )
    
    return {'status': 'sent', 'channels': list(channel_config.keys())}


def format_alert_message(anomaly: Dict, analysis: Dict) -> str:
    """Format alert message for notification"""
    
    message = f"""
🚨 EC2 PATCHING ANOMALY DETECTED

Type: {anomaly['type']}
Severity: {anomaly['severity'].upper()}
Detected: {anomaly['detectedAt']}
Scope: {json.dumps(anomaly['scope'])}

DESCRIPTION:
{anomaly['description']}

METRICS:
  Expected: {anomaly['metrics'].get('expected', 'N/A')}
  Actual: {anomaly['metrics'].get('actual', 'N/A')}
  Deviation: {anomaly['metrics'].get('deviation', 'N/A')}σ

ROOT CAUSE ANALYSIS:
{analysis.get('summary', 'Analysis in progress...')}

RECOMMENDED ACTIONS:
"""
    
    for i, cause in enumerate(analysis.get('rootCauses', [])[:3], 1):
        message += f"\n{i}. {cause['cause']} ({cause['probability']:.0%})"
        if cause.get('remediation', {}).get('steps'):
            message += f"\n   → {cause['remediation']['steps'][0]}"
    
    message += "\n\n---\nThis alert was generated by the EC2 Patching Anomaly Detection Agent"
    
    return message
```

---

## 6. System Prompt

```text
You are an expert Anomaly Detection and Root Cause Analysis Agent for the EC2 Patching Platform.
Your role is to proactively identify issues, analyze failures, and help operations teams
quickly diagnose and resolve patching problems.

## Your Capabilities

You specialize in:
1. **Anomaly Detection** - Identify unusual patterns in failure rates, durations, and error frequencies
2. **Root Cause Analysis** - Correlate evidence to determine probable causes of failures
3. **Pattern Recognition** - Match errors against known failure signatures
4. **Correlation Analysis** - Find relationships between failures across time, accounts, and regions
5. **Proactive Alerting** - Identify emerging issues before they become critical

## Expertise Areas

You have deep knowledge of:
- AWS Systems Manager (SSM) agent issues and troubleshooting
- EC2 instance connectivity and status checks
- Network configuration (VPCs, Security Groups, NACLs)
- IAM permissions and role assumption
- Package manager issues (yum, apt, Windows Update)
- Patch installation and reboot processes

## Analysis Approach

When analyzing issues:
1. Gather all available evidence (logs, metrics, error messages)
2. Build a timeline of events leading to the failure
3. Match against known error patterns
4. Correlate with infrastructure events (CloudTrail, Config)
5. Rank root causes by probability with supporting evidence
6. Provide specific, actionable remediation steps

## Output Format

For Root Cause Analysis, structure your response as:

### Summary
Brief description of the most likely root cause.

### Evidence Timeline
Chronological sequence of relevant events.

### Probable Root Causes
1. **[Most Likely - X%]** Description
   - Evidence: List of supporting evidence
   - Remediation: Steps to resolve
   
2. **[Alternative - Y%]** Description
   - Evidence: ...
   - Remediation: ...

### Recommendations
Prioritized list of recommended actions.

### Prevention
Suggestions to prevent similar issues in the future.

## Severity Classification

- **CRITICAL**: Complete patching failure, data loss risk, security exposure
- **HIGH**: >25% failure rate, multiple accounts affected, SLA breach risk
- **MEDIUM**: 10-25% failure rate, isolated failures, performance degradation
- **LOW**: <10% failure rate, single instance issues, minor anomalies

## Guidelines

1. Always provide evidence-based analysis - never speculate without data
2. Include confidence levels for all root cause determinations
3. Prioritize actionable insights over verbose descriptions
4. Consider both immediate remediation and long-term prevention
5. Flag potential security implications of failures
6. Escalate critical issues proactively

## Known Common Issues Reference

| Issue | Signature | Quick Remediation |
|-------|-----------|-------------------|
| SSM Agent Down | "Unable to reach SSM agent" | Restart via EC2 Console or SSH |
| IAM Permission | "AccessDenied" | Check instance profile |
| Network Block | "Connection timed out" | Verify SG/NACL/Routes |
| Disk Full | "No space left" | Clean logs, extend volume |
| Reboot Hung | "Reboot timeout" | Force stop/start |
```

---

## 7. Guardrails Configuration

```yaml
AnomalyAgentGuardrails:
  Type: AWS::Bedrock::Guardrail
  Properties:
    Name: !Sub '${NamePrefix}-anomaly-agent-guardrails'
    Description: 'Guardrails for Anomaly Detection Agent'
    
    ContentPolicyConfig:
      FiltersConfig:
        - Type: VIOLENCE
          InputStrength: HIGH
          OutputStrength: HIGH
        - Type: HATE
          InputStrength: HIGH
          OutputStrength: HIGH
        - Type: INSULTS
          InputStrength: HIGH
          OutputStrength: HIGH
        - Type: MISCONDUCT
          InputStrength: HIGH
          OutputStrength: HIGH
    
    TopicPolicyConfig:
      TopicsConfig:
        - Name: 'Non-Patching-Topics'
          Description: 'Block topics unrelated to patching and troubleshooting'
          Definition: 'Any topics not related to EC2 patching, SSM, system administration, or troubleshooting'
          Type: DENY
          Examples:
            - 'How to hack into a system'
            - 'Cryptocurrency mining on instances'
            - 'Personal advice or opinions'
        - Name: 'Destructive-Actions'
          Description: 'Block suggestions for destructive actions without proper safeguards'
          Definition: 'Suggestions to terminate instances, delete data, or perform irreversible actions without mentioning safeguards'
          Type: DENY
    
    SensitiveInformationPolicyConfig:
      PiiEntitiesConfig:
        - Type: EMAIL
          Action: ANONYMIZE
        - Type: PHONE
          Action: ANONYMIZE
        - Type: NAME
          Action: ANONYMIZE
        - Type: AWS_ACCESS_KEY
          Action: BLOCK
        - Type: AWS_SECRET_KEY
          Action: BLOCK
        - Type: PASSWORD
          Action: BLOCK
```

---

## 8. Sample Conversations

### 8.1 Failure Investigation

**User:** "We're seeing a spike in patching failures in the us-west-2 region over the last few hours. What's going on?"

**Agent:** "I'll analyze the recent failures in us-west-2. Let me detect anomalies and investigate the root cause.

### Anomaly Detection Results

I've detected **1 high-severity anomaly** in us-west-2:

| Metric | Expected | Actual | Deviation |
|--------|----------|--------|-----------|
| Failure Rate | 3.2% | 18.7% | +4.8σ |
| Affected Instances | ~5 | 23 | - |
| Time Window | Last 3 hours | - | - |

### Root Cause Analysis

**Most Likely Cause (67%):** SSM VPC Endpoint Connectivity Issue

**Evidence:**
- 19 of 23 failures show error: `Unable to reach SSM agent`
- All affected instances are in subnet `subnet-0abc123def456789`
- VPC endpoint `vpce-ssm-us-west-2` shows elevated `4xx` responses starting at 14:32 UTC
- No changes to Security Groups detected

**Timeline:**
| Time | Event |
|------|-------|
| 14:32 | First SSM connectivity failure detected |
| 14:35 | Patch wave 2 started for us-west-2 |
| 14:38 | Failure rate exceeded 10% threshold |
| 14:45 | 23 instances showing SSM unreachable |

### Recommended Actions

1. **Immediate:** Check VPC Endpoint health:
   ```bash
   aws ec2 describe-vpc-endpoints --vpc-endpoint-ids vpce-ssm-us-west-2
   ```

2. **Verify route table:** Ensure routes to SSM endpoints are correct for subnet `subnet-0abc123def456789`

3. **Check endpoint policy:** Verify VPC endpoint policy allows SSM actions

4. **Fallback option:** If VPC endpoint is misconfigured, affected instances may need NAT gateway access to public SSM endpoints

### Prevention
Consider implementing VPC endpoint health monitoring with CloudWatch alarms to detect connectivity issues before patching windows."

---

## 9. IAM Permissions

```yaml
AnomalyAgentRole:
  Type: AWS::IAM::Role
  Properties:
    RoleName: !Sub '${NamePrefix}-${Environment}-anomaly-agent-role'
    AssumeRolePolicyDocument:
      Version: '2012-10-17'
      Statement:
        - Effect: Allow
          Principal:
            Service: bedrock.amazonaws.com
          Action: sts:AssumeRole
    Policies:
      - PolicyName: AnomalyAgentPolicy
        PolicyDocument:
          Version: '2012-10-17'
          Statement:
            # DynamoDB Read
            - Effect: Allow
              Action:
                - dynamodb:Query
                - dynamodb:Scan
                - dynamodb:GetItem
              Resource:
                - !Sub 'arn:aws:dynamodb:${AWS::Region}:${AWS::AccountId}:table/${PatchRunsTable}'
                - !Sub 'arn:aws:dynamodb:${AWS::Region}:${AWS::AccountId}:table/${PatchRunsTable}/index/*'
            
            # CloudWatch Logs Read
            - Effect: Allow
              Action:
                - logs:GetLogEvents
                - logs:FilterLogEvents
                - logs:DescribeLogGroups
                - logs:DescribeLogStreams
                - logs:StartQuery
                - logs:GetQueryResults
              Resource:
                - !Sub 'arn:aws:logs:${AWS::Region}:${AWS::AccountId}:log-group:/aws/lambda/${NamePrefix}*'
                - !Sub 'arn:aws:logs:${AWS::Region}:${AWS::AccountId}:log-group:/aws/states/${NamePrefix}*'
            
            # CloudTrail Read (for infrastructure correlation)
            - Effect: Allow
              Action:
                - cloudtrail:LookupEvents
              Resource: '*'
            
            # EC2 Read (for instance status)
            - Effect: Allow
              Action:
                - ec2:DescribeInstances
                - ec2:DescribeInstanceStatus
                - ec2:DescribeVpcEndpoints
                - ec2:DescribeSecurityGroups
                - ec2:DescribeSubnets
              Resource: '*'
            
            # SSM Read (for command history)
            - Effect: Allow
              Action:
                - ssm:DescribeInstanceInformation
                - ssm:ListCommands
                - ssm:ListCommandInvocations
                - ssm:GetCommandInvocation
              Resource: '*'
            
            # OpenSearch Read (for error patterns)
            - Effect: Allow
              Action:
                - aoss:APIAccessAll
              Resource:
                - !Sub 'arn:aws:aoss:${AWS::Region}:${AWS::AccountId}:collection/${OpenSearchCollection}'
            
            # SNS Publish (for alerts)
            - Effect: Allow
              Action:
                - sns:Publish
              Resource:
                - !Sub 'arn:aws:sns:${AWS::Region}:${AWS::AccountId}:${NamePrefix}-*'
            
            # EventBridge (for alert events)
            - Effect: Allow
              Action:
                - events:PutEvents
              Resource:
                - !Sub 'arn:aws:events:${AWS::Region}:${AWS::AccountId}:event-bus/default'
```

---

## 10. Integration with Existing Platform

### 10.1 Event-Driven Anomaly Detection

The agent integrates with the existing patching platform through EventBridge:

```yaml
AnomalyDetectionEventRule:
  Type: AWS::Events::Rule
  Properties:
    Name: !Sub '${NamePrefix}-anomaly-detection-trigger'
    Description: 'Trigger anomaly detection on patching events'
    EventPattern:
      source:
        - 'aws.states'
        - 'patching.orchestrator'
      detail-type:
        - 'Step Functions Execution Status Change'
        - 'Patch Execution Complete'
        - 'Instance Patch Failed'
    Targets:
      - Id: 'AnomalyDetectionPipeline'
        Arn: !GetAtt AnomalyDetectionPipeline.Arn
        RoleArn: !GetAtt EventsRole.Arn
```

### 10.2 Metrics Published

The agent publishes its own metrics for monitoring:

```python
def publish_agent_metrics(anomalies_detected: int, analysis_time_ms: int, confidence: float):
    """Publish agent operational metrics"""
    cloudwatch.put_metric_data(
        Namespace='EC2Patching/Agents/AnomalyDetection',
        MetricData=[
            {
                'MetricName': 'AnomaliesDetected',
                'Value': anomalies_detected,
                'Unit': 'Count'
            },
            {
                'MetricName': 'AnalysisLatency',
                'Value': analysis_time_ms,
                'Unit': 'Milliseconds'
            },
            {
                'MetricName': 'AnalysisConfidence',
                'Value': confidence,
                'Unit': 'None'
            }
        ]
    )
```

---

*Next: Agent 4 - ChatOps & Conversational Interface Agent Technical Design*
