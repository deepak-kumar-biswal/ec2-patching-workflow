# Agent 2: Reporting & Analytics Agent - Technical Design

## Document Information
| Attribute | Value |
|-----------|-------|
| Version | 1.0 |
| Last Updated | January 14, 2026 |
| Status | Draft |
| Owner | Platform Engineering |
| Agent ID | `reporting-analytics-agent` |

---

## 1. Executive Summary

The **Reporting & Analytics Agent** provides self-service reporting and data analytics capabilities for the EC2 patching platform. It enables executives, managers, and operations teams to obtain insights through natural language queries without requiring SQL, PromQL, or CloudWatch expertise.

### 1.1 Key Capabilities

| Capability | Description | Priority |
|------------|-------------|----------|
| Executive Summaries | High-level patch status for leadership | P0 |
| Trend Analysis | Patch success rates over time | P0 |
| Scheduled Reports | Automated weekly/monthly reports | P0 |
| Comparative Analytics | Compare waves, accounts, regions | P1 |
| Cost Analysis | Patch operation cost breakdown | P1 |
| Capacity Forecasting | Predict future patch window needs | P2 |

### 1.2 User Personas

| Persona | Use Cases | Report Types |
|---------|-----------|--------------|
| CTO/CISO | Monthly security posture review | Executive Summary |
| Engineering Manager | Team performance, planning | Trend Analysis, Forecasts |
| Operations Lead | Weekly status, capacity planning | Detailed Status, Metrics |
| Business Unit Owner | Account-specific status | BU-filtered Reports |

---

## 2. Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                       REPORTING & ANALYTICS AGENT                                │
│                                                                                  │
│  ┌───────────────────────────────────────────────────────────────────────────┐  │
│  │                           AGENT CORE                                       │  │
│  │  Model: anthropic.claude-4.5-sonnet-20250101-v1:0                         │  │
│  │  Temperature: 0.2 (balanced for narrative + accuracy)                     │  │
│  │  Max Tokens: 8192 (longer reports)                                        │  │
│  └───────────────────────────────────────────────────────────────────────────┘  │
│                                      │                                           │
│         ┌────────────────────────────┼────────────────────────────┐              │
│         │                            │                            │              │
│         ▼                            ▼                            ▼              │
│  ┌─────────────────┐    ┌─────────────────────┐    ┌─────────────────────┐      │
│  │ KNOWLEDGE BASES │    │    ACTION GROUPS     │    │   REPORT ENGINE     │      │
│  │                 │    │                      │    │                     │      │
│  │ • execution-records│ │ • Metrics Query     │    │ • Template System   │      │
│  │ • patch-artifacts  │ │ • Trend Calculator  │    │ • Chart Generator   │      │
│  │ • org-structure   │  │ • Report Generator  │    │ • PDF/HTML Export   │      │
│  └─────────────────┘    │ • Forecast Engine   │    │ • S3 Publisher      │      │
│                         └─────────────────────┘    └─────────────────────┘      │
└─────────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                           DATA AGGREGATION LAYER                                 │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                    MATERIALIZED VIEWS / CACHES                           │   │
│  │                                                                          │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐ │   │
│  │  │ Daily Stats  │  │ Weekly Stats │  │Monthly Stats │  │ Account KPIs │ │   │
│  │  │ (DynamoDB)   │  │ (DynamoDB)   │  │ (DynamoDB)   │  │ (DynamoDB)   │ │   │
│  │  └──────────────┘  └──────────────┘  └──────────────┘  └──────────────┘ │   │
│  │                                                                          │   │
│  │  ┌──────────────────────────────────────────────────────────────────┐   │   │
│  │  │ ElastiCache (Redis) - Real-time Metrics Cache                    │   │   │
│  │  │ • Current execution status      • Rolling 7-day stats            │   │   │
│  │  │ • Active wave progress          • Top failure reasons            │   │   │
│  │  └──────────────────────────────────────────────────────────────────┘   │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────────────────────┐ │
│  │ DynamoDB        │  │ CloudWatch      │  │ Step Functions                  │ │
│  │ (PatchRuns)     │  │ (Metrics)       │  │ (Execution History)             │ │
│  └─────────────────┘  └─────────────────┘  └─────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Action Groups (Tools)

### 3.1 Action Group: `metrics-analytics`

#### 3.1.1 Tool: `get_patching_metrics`

**Purpose:** Retrieve aggregated patching metrics

**OpenAPI Schema:**
```yaml
openapi: 3.0.0
info:
  title: Metrics Analytics API
  version: 1.0.0

paths:
  /patching-metrics:
    post:
      operationId: getPatchingMetrics
      summary: Get aggregated patching metrics
      description: |
        Retrieves aggregated patching metrics for dashboards and reports.
        Supports various time granularities and grouping options.
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              properties:
                timeRange:
                  type: string
                  enum: [1h, 6h, 24h, 7d, 30d, 90d, 1y, custom]
                  description: Predefined time range
                startTime:
                  type: string
                  format: date-time
                  description: Custom start time (ISO 8601)
                endTime:
                  type: string
                  format: date-time
                  description: Custom end time (ISO 8601)
                granularity:
                  type: string
                  enum: [hourly, daily, weekly, monthly]
                  default: daily
                  description: Data point granularity
                metrics:
                  type: array
                  items:
                    type: string
                    enum:
                      - success_rate
                      - failure_rate
                      - execution_count
                      - instance_count
                      - patches_installed
                      - avg_duration
                      - p95_duration
                      - sla_adherence
                  description: Metrics to retrieve
                groupBy:
                  type: string
                  enum: [none, account, region, os, wave, day_of_week]
                  default: none
                filters:
                  type: object
                  properties:
                    accounts:
                      type: array
                      items:
                        type: string
                    regions:
                      type: array
                      items:
                        type: string
                    osTypes:
                      type: array
                      items:
                        type: string
                        enum: [linux, windows]
              required:
                - metrics
      responses:
        '200':
          description: Metrics data
          content:
            application/json:
              schema:
                type: object
                properties:
                  timeRange:
                    type: object
                    properties:
                      start:
                        type: string
                      end:
                        type: string
                  granularity:
                    type: string
                  dataPoints:
                    type: array
                    items:
                      type: object
                      properties:
                        timestamp:
                          type: string
                        groupKey:
                          type: string
                        metrics:
                          type: object
                          additionalProperties:
                            type: number
                  summary:
                    type: object
                    description: Aggregated summary statistics
```

**Lambda Handler:**
```python
"""
Patching Metrics Aggregator
Retrieves and aggregates patching metrics from multiple sources
"""

import json
import boto3
from datetime import datetime, timedelta
from typing import Dict, Any, List
from decimal import Decimal
from collections import defaultdict

dynamodb = boto3.resource('dynamodb')
cloudwatch = boto3.client('cloudwatch')

# Tables
stats_table = dynamodb.Table(os.environ['STATS_TABLE'])
runs_table = dynamodb.Table(os.environ['PATCH_RUNS_TABLE'])

class DecimalEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, Decimal):
            return float(obj)
        return super().default(obj)


def handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """Get aggregated patching metrics"""
    
    params = event.get('requestBody', {}).get('content', {}).get('application/json', {})
    
    time_range = params.get('timeRange', '7d')
    granularity = params.get('granularity', 'daily')
    metrics = params.get('metrics', ['success_rate', 'execution_count'])
    group_by = params.get('groupBy', 'none')
    filters = params.get('filters', {})
    
    # Calculate time bounds
    end_time = datetime.utcnow()
    start_time = calculate_start_time(time_range, params, end_time)
    
    # Fetch data based on granularity
    if granularity in ['hourly', 'daily'] and time_range in ['1h', '6h', '24h', '7d']:
        # Use CloudWatch for real-time metrics
        data_points = fetch_cloudwatch_metrics(start_time, end_time, granularity, metrics, filters)
    else:
        # Use pre-aggregated DynamoDB stats for historical
        data_points = fetch_dynamodb_stats(start_time, end_time, granularity, metrics, group_by, filters)
    
    # Calculate summary
    summary = calculate_summary(data_points, metrics)
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'timeRange': {
                'start': start_time.isoformat(),
                'end': end_time.isoformat()
            },
            'granularity': granularity,
            'dataPoints': data_points,
            'summary': summary
        }, cls=DecimalEncoder)
    }


def fetch_cloudwatch_metrics(start: datetime, end: datetime, granularity: str, 
                             metrics: List[str], filters: dict) -> List[dict]:
    """Fetch metrics from CloudWatch"""
    
    period = 3600 if granularity == 'hourly' else 86400  # seconds
    
    metric_queries = []
    for i, metric in enumerate(metrics):
        metric_queries.append({
            'Id': f'm{i}',
            'MetricStat': {
                'Metric': {
                    'Namespace': 'EC2Patching/Orchestrator',
                    'MetricName': metric_to_cloudwatch(metric),
                    'Dimensions': build_dimensions(filters)
                },
                'Period': period,
                'Stat': 'Sum' if metric in ['execution_count', 'patches_installed'] else 'Average'
            }
        })
    
    response = cloudwatch.get_metric_data(
        MetricDataQueries=metric_queries,
        StartTime=start,
        EndTime=end
    )
    
    # Transform to data points
    data_points = []
    timestamps = set()
    for result in response['MetricDataResults']:
        for ts, val in zip(result['Timestamps'], result['Values']):
            timestamps.add(ts)
    
    for ts in sorted(timestamps):
        point = {'timestamp': ts.isoformat(), 'metrics': {}}
        for i, metric in enumerate(metrics):
            result = response['MetricDataResults'][i]
            if ts in result['Timestamps']:
                idx = result['Timestamps'].index(ts)
                point['metrics'][metric] = result['Values'][idx]
        data_points.append(point)
    
    return data_points


def fetch_dynamodb_stats(start: datetime, end: datetime, granularity: str,
                         metrics: List[str], group_by: str, filters: dict) -> List[dict]:
    """Fetch pre-aggregated stats from DynamoDB"""
    
    # Query pre-aggregated stats table
    prefix = get_stat_prefix(granularity)
    start_key = f"{prefix}#{start.strftime('%Y-%m-%d')}"
    end_key = f"{prefix}#{end.strftime('%Y-%m-%d')}"
    
    response = stats_table.query(
        KeyConditionExpression='pk = :pk AND sk BETWEEN :start AND :end',
        ExpressionAttributeValues={
            ':pk': f'stats#{granularity}',
            ':start': start_key,
            ':end': end_key
        }
    )
    
    data_points = []
    for item in response['Items']:
        point = {
            'timestamp': item['date'],
            'metrics': {}
        }
        
        if group_by != 'none':
            point['groupKey'] = item.get(f'{group_by}_id', 'all')
        
        for metric in metrics:
            point['metrics'][metric] = item.get(metric, 0)
        
        data_points.append(point)
    
    return data_points


def calculate_summary(data_points: List[dict], metrics: List[str]) -> dict:
    """Calculate summary statistics"""
    
    summary = {}
    
    for metric in metrics:
        values = [dp['metrics'].get(metric, 0) for dp in data_points if metric in dp.get('metrics', {})]
        
        if values:
            summary[metric] = {
                'min': min(values),
                'max': max(values),
                'avg': sum(values) / len(values),
                'total': sum(values) if metric in ['execution_count', 'patches_installed', 'instance_count'] else None,
                'latest': values[-1] if values else None
            }
    
    return summary
```

#### 3.1.2 Tool: `get_trend_analysis`

**Purpose:** Analyze trends over time

**OpenAPI Schema:**
```yaml
paths:
  /trend-analysis:
    post:
      operationId: getTrendAnalysis
      summary: Analyze patching trends over time
      description: |
        Performs trend analysis on patching metrics, identifying patterns,
        improvements, and regressions over the specified time period.
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              properties:
                metric:
                  type: string
                  enum: [success_rate, failure_rate, avg_duration, instances_patched, sla_adherence]
                  description: Metric to analyze
                compareRanges:
                  type: array
                  items:
                    type: object
                    properties:
                      label:
                        type: string
                      startDate:
                        type: string
                        format: date
                      endDate:
                        type: string
                        format: date
                  description: Time ranges to compare (e.g., this month vs last month)
                groupBy:
                  type: string
                  enum: [account, region, os, wave]
                  description: Group trend analysis by dimension
                trendType:
                  type: string
                  enum: [simple, moving_average, regression]
                  default: simple
              required:
                - metric
      responses:
        '200':
          description: Trend analysis results
          content:
            application/json:
              schema:
                type: object
                properties:
                  metric:
                    type: string
                  trendDirection:
                    type: string
                    enum: [improving, stable, declining]
                  changePercent:
                    type: number
                    description: Percentage change over the period
                  trendLine:
                    type: array
                    items:
                      type: object
                      properties:
                        date:
                          type: string
                        actual:
                          type: number
                        trend:
                          type: number
                  comparison:
                    type: array
                    items:
                      type: object
                      properties:
                        label:
                          type: string
                        value:
                          type: number
                        change:
                          type: number
                  insights:
                    type: array
                    items:
                      type: string
                    description: AI-generated insights about the trends
```

**Lambda Handler:**
```python
"""
Trend Analysis Engine
Analyzes patching trends and generates insights
"""

import json
import numpy as np
from scipy import stats as scipy_stats
from datetime import datetime, timedelta
from typing import Dict, Any, List

def handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """Perform trend analysis on patching metrics"""
    
    params = event.get('requestBody', {}).get('content', {}).get('application/json', {})
    
    metric = params.get('metric', 'success_rate')
    compare_ranges = params.get('compareRanges', [])
    group_by = params.get('groupBy')
    trend_type = params.get('trendType', 'simple')
    
    # Fetch historical data
    data = fetch_metric_history(metric, compare_ranges)
    
    # Calculate trend
    trend_result = calculate_trend(data['values'], trend_type)
    
    # Compare ranges if provided
    comparisons = []
    if compare_ranges:
        for i, range_data in enumerate(compare_ranges):
            range_values = data['range_values'].get(range_data['label'], [])
            if range_values:
                avg = sum(range_values) / len(range_values)
                prev_avg = None
                if i > 0:
                    prev_label = compare_ranges[i-1]['label']
                    prev_values = data['range_values'].get(prev_label, [])
                    if prev_values:
                        prev_avg = sum(prev_values) / len(prev_values)
                
                comparisons.append({
                    'label': range_data['label'],
                    'value': round(avg, 2),
                    'change': round((avg - prev_avg) / prev_avg * 100, 2) if prev_avg else None
                })
    
    # Generate insights
    insights = generate_insights(metric, trend_result, comparisons, data)
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'metric': metric,
            'trendDirection': trend_result['direction'],
            'changePercent': trend_result['change_percent'],
            'trendLine': trend_result['trend_line'],
            'comparison': comparisons,
            'insights': insights
        })
    }


def calculate_trend(values: List[float], trend_type: str) -> dict:
    """Calculate trend from values"""
    
    if not values or len(values) < 2:
        return {
            'direction': 'stable',
            'change_percent': 0,
            'trend_line': []
        }
    
    x = np.arange(len(values))
    y = np.array(values)
    
    if trend_type == 'regression':
        # Linear regression
        slope, intercept, r_value, p_value, std_err = scipy_stats.linregress(x, y)
        trend_values = slope * x + intercept
    elif trend_type == 'moving_average':
        # 7-day moving average
        window = min(7, len(values))
        trend_values = np.convolve(y, np.ones(window)/window, mode='valid')
        # Pad to match length
        trend_values = np.concatenate([y[:window-1], trend_values])
    else:
        # Simple trend (first to last comparison)
        trend_values = y
    
    # Determine direction
    change_percent = ((values[-1] - values[0]) / values[0] * 100) if values[0] != 0 else 0
    
    if change_percent > 5:
        direction = 'improving'
    elif change_percent < -5:
        direction = 'declining'
    else:
        direction = 'stable'
    
    return {
        'direction': direction,
        'change_percent': round(change_percent, 2),
        'trend_line': [
            {'date': f'day_{i}', 'actual': float(y[i]), 'trend': float(trend_values[i])}
            for i in range(len(y))
        ]
    }


def generate_insights(metric: str, trend: dict, comparisons: List[dict], data: dict) -> List[str]:
    """Generate natural language insights"""
    
    insights = []
    
    # Trend insight
    if trend['direction'] == 'improving':
        insights.append(f"📈 {metric.replace('_', ' ').title()} has improved by {abs(trend['change_percent']):.1f}% over the analysis period.")
    elif trend['direction'] == 'declining':
        insights.append(f"📉 {metric.replace('_', ' ').title()} has declined by {abs(trend['change_percent']):.1f}% over the analysis period.")
    else:
        insights.append(f"📊 {metric.replace('_', ' ').title()} has remained stable over the analysis period.")
    
    # Comparison insights
    for i, comp in enumerate(comparisons):
        if comp.get('change') is not None:
            direction = 'increased' if comp['change'] > 0 else 'decreased'
            insights.append(f"• {comp['label']}: {direction} by {abs(comp['change']):.1f}% compared to previous period.")
    
    # Anomaly detection
    if data.get('values'):
        mean = sum(data['values']) / len(data['values'])
        std = np.std(data['values'])
        outliers = [v for v in data['values'] if abs(v - mean) > 2 * std]
        if outliers:
            insights.append(f"⚠️ Detected {len(outliers)} outlier(s) in the data that may warrant investigation.")
    
    return insights
```

#### 3.1.3 Tool: `compare_dimensions`

**Purpose:** Compare metrics across different dimensions

**OpenAPI Schema:**
```yaml
paths:
  /compare-dimensions:
    post:
      operationId: compareDimensions
      summary: Compare patching metrics across dimensions
      description: |
        Compares patching metrics across accounts, regions, OS types, or waves
        to identify high and low performers.
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              properties:
                dimension:
                  type: string
                  enum: [account, region, os, wave, business_unit]
                  description: Dimension to compare
                metrics:
                  type: array
                  items:
                    type: string
                  description: Metrics to compare
                timeRange:
                  type: string
                  enum: [7d, 30d, 90d]
                  default: 30d
                sortBy:
                  type: string
                  description: Metric to sort results by
                sortOrder:
                  type: string
                  enum: [asc, desc]
                  default: desc
                limit:
                  type: integer
                  default: 10
              required:
                - dimension
                - metrics
      responses:
        '200':
          description: Dimensional comparison
          content:
            application/json:
              schema:
                type: object
                properties:
                  dimension:
                    type: string
                  items:
                    type: array
                    items:
                      type: object
                      properties:
                        dimensionValue:
                          type: string
                        displayName:
                          type: string
                        metrics:
                          type: object
                        rank:
                          type: integer
                        vsAverage:
                          type: number
                          description: Percentage above/below average
                  average:
                    type: object
                    description: Average metrics across all dimensions
                  topPerformers:
                    type: array
                    items:
                      type: string
                  bottomPerformers:
                    type: array
                    items:
                      type: string
```

### 3.2 Action Group: `report-generation`

#### 3.2.1 Tool: `generate_executive_report`

**Purpose:** Generate executive-level summary reports

**OpenAPI Schema:**
```yaml
paths:
  /executive-report:
    post:
      operationId: generateExecutiveReport
      summary: Generate an executive summary report
      description: |
        Generates a high-level executive report suitable for leadership review.
        Includes key metrics, trends, and actionable insights.
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              properties:
                reportPeriod:
                  type: string
                  enum: [weekly, monthly, quarterly, yearly]
                  default: monthly
                customDateRange:
                  type: object
                  properties:
                    start:
                      type: string
                      format: date
                    end:
                      type: string
                      format: date
                includeCharts:
                  type: boolean
                  default: true
                  description: Whether to include chart visualizations
                includeTrends:
                  type: boolean
                  default: true
                includeRecommendations:
                  type: boolean
                  default: true
                accountScope:
                  type: array
                  items:
                    type: string
                  description: Limit to specific accounts (empty = all)
                recipientRole:
                  type: string
                  enum: [cto, ciso, engineering_manager, ops_lead]
                  default: cto
                  description: Customize content for recipient role
                outputFormat:
                  type: string
                  enum: [markdown, html, pdf]
                  default: markdown
              required:
                - reportPeriod
      responses:
        '200':
          description: Generated executive report
          content:
            application/json:
              schema:
                type: object
                properties:
                  reportContent:
                    type: string
                  s3Url:
                    type: string
                    description: URL if PDF generated
                  generatedAt:
                    type: string
                  highlights:
                    type: array
                    items:
                      type: object
                      properties:
                        type:
                          type: string
                          enum: [positive, negative, neutral]
                        message:
                          type: string
```

**Lambda Handler:**
```python
"""
Executive Report Generator
Creates leadership-ready patch status reports
"""

import json
import boto3
from datetime import datetime, timedelta
from typing import Dict, Any, List
import matplotlib.pyplot as plt
import io
import base64

s3_client = boto3.client('s3')

REPORT_TEMPLATES = {
    'cto': {
        'title': 'EC2 Patching - Technology Leadership Report',
        'sections': ['executive_summary', 'key_metrics', 'trends', 'recommendations', 'next_steps'],
        'detail_level': 'high'
    },
    'ciso': {
        'title': 'EC2 Patching - Security Posture Report',
        'sections': ['security_summary', 'compliance_status', 'vulnerability_coverage', 'risk_assessment'],
        'detail_level': 'high'
    },
    'engineering_manager': {
        'title': 'EC2 Patching - Engineering Report',
        'sections': ['execution_summary', 'performance_metrics', 'failure_analysis', 'capacity_planning'],
        'detail_level': 'medium'
    },
    'ops_lead': {
        'title': 'EC2 Patching - Operations Report',
        'sections': ['operations_summary', 'detailed_metrics', 'issues', 'action_items'],
        'detail_level': 'detailed'
    }
}


def handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """Generate executive report"""
    
    params = event.get('requestBody', {}).get('content', {}).get('application/json', {})
    
    report_period = params.get('reportPeriod', 'monthly')
    recipient_role = params.get('recipientRole', 'cto')
    include_charts = params.get('includeCharts', True)
    include_trends = params.get('includeTrends', True)
    output_format = params.get('outputFormat', 'markdown')
    
    # Get template
    template = REPORT_TEMPLATES[recipient_role]
    
    # Calculate date range
    end_date = datetime.utcnow()
    start_date = calculate_period_start(report_period, end_date)
    
    # Gather data
    metrics_data = gather_metrics(start_date, end_date)
    trends_data = gather_trends(start_date, end_date) if include_trends else None
    comparison_data = gather_period_comparison(start_date, end_date, report_period)
    
    # Generate charts if requested
    charts = {}
    if include_charts:
        charts['success_rate'] = generate_success_rate_chart(metrics_data)
        charts['execution_trend'] = generate_execution_trend_chart(metrics_data)
        charts['account_comparison'] = generate_account_comparison_chart(metrics_data)
    
    # Generate report content
    report = generate_report_content(
        template=template,
        metrics=metrics_data,
        trends=trends_data,
        comparison=comparison_data,
        charts=charts,
        period=report_period,
        start_date=start_date,
        end_date=end_date
    )
    
    # Format output
    if output_format == 'markdown':
        formatted = format_as_markdown(report)
    elif output_format == 'html':
        formatted = format_as_html(report)
    else:  # PDF
        formatted = generate_pdf(report)
    
    # Extract highlights
    highlights = extract_highlights(metrics_data, trends_data, comparison_data)
    
    # Save to S3 if PDF
    s3_url = None
    if output_format == 'pdf':
        s3_url = upload_to_s3(formatted, report_period, end_date)
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'reportContent': formatted if output_format != 'pdf' else None,
            's3Url': s3_url,
            'generatedAt': datetime.utcnow().isoformat(),
            'highlights': highlights
        })
    }


def generate_report_content(template: dict, metrics: dict, trends: dict, 
                           comparison: dict, charts: dict, period: str,
                           start_date: datetime, end_date: datetime) -> dict:
    """Generate structured report content"""
    
    report = {
        'title': template['title'],
        'period': f"{start_date.strftime('%B %d, %Y')} - {end_date.strftime('%B %d, %Y')}",
        'generated_at': datetime.utcnow().isoformat(),
        'sections': []
    }
    
    for section in template['sections']:
        if section == 'executive_summary':
            report['sections'].append({
                'title': 'Executive Summary',
                'content': generate_executive_summary(metrics, trends, comparison)
            })
        elif section == 'key_metrics':
            report['sections'].append({
                'title': 'Key Performance Indicators',
                'content': generate_kpi_section(metrics),
                'chart': charts.get('success_rate')
            })
        elif section == 'trends':
            report['sections'].append({
                'title': 'Trend Analysis',
                'content': generate_trends_section(trends),
                'chart': charts.get('execution_trend')
            })
        elif section == 'recommendations':
            report['sections'].append({
                'title': 'Recommendations',
                'content': generate_recommendations(metrics, trends)
            })
    
    return report


def generate_executive_summary(metrics: dict, trends: dict, comparison: dict) -> str:
    """Generate executive summary text"""
    
    success_rate = metrics.get('success_rate', 0)
    total_instances = metrics.get('total_instances', 0)
    total_patches = metrics.get('total_patches', 0)
    
    trend_direction = trends.get('direction', 'stable') if trends else 'stable'
    trend_change = trends.get('change_percent', 0) if trends else 0
    
    summary = f"""
During this reporting period, the EC2 Patching Platform maintained a **{success_rate:.1f}% success rate** 
across **{total_instances:,} instances**, deploying **{total_patches:,} patches** across the enterprise.

**Key Highlights:**
- Overall patch compliance is {"above" if success_rate > 95 else "below"} the 95% target
- Trend is {trend_direction} with a {abs(trend_change):.1f}% {"improvement" if trend_change > 0 else "decline"} from the previous period
- {comparison.get('summary', 'N/A')}

**Risk Status:** {"🟢 Low" if success_rate > 95 else "🟡 Medium" if success_rate > 85 else "🔴 High"}
"""
    
    return summary.strip()


def format_as_markdown(report: dict) -> str:
    """Format report as Markdown"""
    
    md = f"""# {report['title']}

**Report Period:** {report['period']}  
**Generated:** {report['generated_at']}

---

"""
    
    for section in report['sections']:
        md += f"\n## {section['title']}\n\n"
        md += section['content'] + "\n"
        
        if section.get('chart'):
            md += f"\n![{section['title']}](data:image/png;base64,{section['chart']})\n"
    
    return md


def extract_highlights(metrics: dict, trends: dict, comparison: dict) -> List[dict]:
    """Extract key highlights for quick view"""
    
    highlights = []
    
    # Success rate highlight
    success_rate = metrics.get('success_rate', 0)
    if success_rate >= 98:
        highlights.append({'type': 'positive', 'message': f'Excellent success rate of {success_rate:.1f}%'})
    elif success_rate < 90:
        highlights.append({'type': 'negative', 'message': f'Success rate of {success_rate:.1f}% needs improvement'})
    
    # Trend highlight
    if trends:
        if trends.get('direction') == 'improving':
            highlights.append({'type': 'positive', 'message': f'Improving trend: +{trends.get("change_percent", 0):.1f}%'})
        elif trends.get('direction') == 'declining':
            highlights.append({'type': 'negative', 'message': f'Declining trend: {trends.get("change_percent", 0):.1f}%'})
    
    # Volume highlight
    total_instances = metrics.get('total_instances', 0)
    highlights.append({'type': 'neutral', 'message': f'{total_instances:,} instances patched this period'})
    
    return highlights
```

#### 3.2.2 Tool: `schedule_report`

**Purpose:** Schedule automated recurring reports

**OpenAPI Schema:**
```yaml
paths:
  /schedule-report:
    post:
      operationId: scheduleReport
      summary: Schedule automated recurring reports
      description: |
        Creates a schedule for automated report generation and delivery.
        Reports can be delivered via email, Slack, or stored in S3.
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              properties:
                reportType:
                  type: string
                  enum: [executive, compliance, operations, custom]
                schedule:
                  type: string
                  description: Cron expression for schedule
                  example: "0 9 * * MON"  # Every Monday at 9 AM
                timezone:
                  type: string
                  default: UTC
                delivery:
                  type: object
                  properties:
                    email:
                      type: array
                      items:
                        type: string
                        format: email
                    slack:
                      type: object
                      properties:
                        channel:
                          type: string
                        webhookUrl:
                          type: string
                    s3:
                      type: object
                      properties:
                        bucket:
                          type: string
                        prefix:
                          type: string
                reportConfig:
                  type: object
                  description: Configuration specific to report type
                enabled:
                  type: boolean
                  default: true
              required:
                - reportType
                - schedule
                - delivery
      responses:
        '200':
          description: Schedule created
          content:
            application/json:
              schema:
                type: object
                properties:
                  scheduleId:
                    type: string
                  status:
                    type: string
                  nextRun:
                    type: string
                    format: date-time
```

---

## 4. System Prompt

```text
You are an expert Data Analytics and Reporting Agent for the EC2 Patching Platform.
Your role is to help users understand patching performance, generate reports, and
gain insights from patching data through natural language queries.

## Your Capabilities

You can analyze and report on:
1. **Patching Metrics** - Success rates, failure rates, execution counts, durations
2. **Trend Analysis** - Performance trends over time, period comparisons
3. **Dimensional Analysis** - Compare accounts, regions, OS types, waves
4. **Executive Reports** - Leadership-ready summaries and presentations
5. **Scheduled Reports** - Automated recurring report generation

## Data Sources

- Patch execution records (DynamoDB)
- CloudWatch metrics (real-time and historical)
- Pre-aggregated statistics (daily, weekly, monthly)
- Organizational mappings (accounts to business units)

## Guidelines

### Report Generation
1. Always confirm the time range and scope before generating reports
2. Include relevant visualizations when possible
3. Highlight key findings and actionable insights
4. Tailor content to the audience (executive vs. operations)

### Data Presentation
1. Use tables for structured comparisons
2. Include percentages and absolute numbers where relevant
3. Highlight significant changes (>5% variance)
4. Compare to benchmarks or targets when available

### Insights
1. Identify patterns and anomalies
2. Suggest root causes for performance issues
3. Recommend improvements based on data
4. Note any data quality issues or limitations

## Report Types

### Executive Summary
- High-level KPIs (success rate, coverage, SLA adherence)
- Period-over-period comparison
- Top 3 highlights and concerns
- Strategic recommendations

### Operations Report
- Detailed execution metrics
- Failure breakdown by category
- Capacity utilization
- Pending actions

### Compliance Report
- Control status by framework
- SLA adherence metrics
- Gap analysis
- Evidence summary

### Trend Report
- Time-series analysis
- Moving averages
- Regression trends
- Forecasts

## Example Queries

- "What's our patch success rate this month?"
- "Compare patch performance across regions"
- "Generate a weekly report for the ops team"
- "Show me the trend in failure rates over the last quarter"
- "Which accounts have the longest patch durations?"

## Formatting

Use Markdown formatting:
- **Bold** for key metrics and findings
- Tables for comparisons
- Lists for recommendations
- Emojis for status indicators (✅ ⚠️ ❌ 📈 📉)
```

---

## 5. Data Aggregation Layer

### 5.1 Pre-Aggregated Statistics Table

To support fast analytics queries, we maintain pre-aggregated statistics in DynamoDB:

**Table: `${NamePrefix}-${Environment}-stats`**

```yaml
Schema:
  pk: "stats#{granularity}"  # stats#daily, stats#weekly, stats#monthly
  sk: "{granularity}#{date}"  # daily#2026-01-14, weekly#2026-W02
  
  Attributes:
    date: string
    execution_count: number
    success_count: number
    failure_count: number
    partial_count: number
    instance_count: number
    patches_installed: number
    avg_duration_seconds: number
    p95_duration_seconds: number
    success_rate: number
    sla_adherence_rate: number
    
    # Breakdowns
    by_account: map  # {account_id: {success: N, failure: N, ...}}
    by_region: map   # {region: {success: N, failure: N, ...}}
    by_os: map       # {linux: {...}, windows: {...}}
```

### 5.2 Statistics Aggregator Lambda

Triggered by DynamoDB Streams to update aggregated statistics:

```python
"""
Statistics Aggregator
Updates pre-aggregated statistics when new execution records are added
"""

import json
import boto3
from datetime import datetime
from decimal import Decimal
from boto3.dynamodb.types import TypeDeserializer

dynamodb = boto3.resource('dynamodb')
stats_table = dynamodb.Table(os.environ['STATS_TABLE'])
deserializer = TypeDeserializer()


def handler(event, context):
    """Process DynamoDB stream and update aggregated stats"""
    
    for record in event.get('Records', []):
        if record['eventName'] not in ['INSERT', 'MODIFY']:
            continue
        
        new_image = deserialize(record['dynamodb']['NewImage'])
        
        # Only process wave-level records for aggregation
        if new_image.get('scope') != 'wave':
            continue
        
        # Extract date from execution
        exec_date = datetime.fromisoformat(new_image.get('start_time', datetime.utcnow().isoformat()))
        
        # Update daily stats
        update_stats('daily', exec_date.strftime('%Y-%m-%d'), new_image)
        
        # Update weekly stats
        update_stats('weekly', exec_date.strftime('%Y-W%V'), new_image)
        
        # Update monthly stats
        update_stats('monthly', exec_date.strftime('%Y-%m'), new_image)


def update_stats(granularity: str, date_key: str, execution: dict):
    """Update aggregated stats for given granularity"""
    
    metadata = execution.get('metadata', {})
    status = execution.get('status', 'unknown')
    
    update_expr = """
        SET execution_count = if_not_exists(execution_count, :zero) + :one,
            instance_count = if_not_exists(instance_count, :zero) + :instances,
            patches_installed = if_not_exists(patches_installed, :zero) + :patches,
            #date = :date_val
    """
    
    expr_values = {
        ':zero': 0,
        ':one': 1,
        ':instances': metadata.get('instance_count', 0),
        ':patches': metadata.get('patches_installed', 0),
        ':date_val': date_key
    }
    
    # Status-specific counters
    if status == 'success':
        update_expr += ", success_count = if_not_exists(success_count, :zero) + :one"
    elif status == 'failed':
        update_expr += ", failure_count = if_not_exists(failure_count, :zero) + :one"
    elif status == 'partial':
        update_expr += ", partial_count = if_not_exists(partial_count, :zero) + :one"
    
    stats_table.update_item(
        Key={
            'pk': f'stats#{granularity}',
            'sk': f'{granularity}#{date_key}'
        },
        UpdateExpression=update_expr,
        ExpressionAttributeValues=expr_values,
        ExpressionAttributeNames={'#date': 'date'}
    )
```

---

## 6. Visualization Engine

### 6.1 Chart Generation

The agent can generate charts for visual reports:

```python
"""
Chart Generator
Creates visualizations for reports
"""

import matplotlib.pyplot as plt
import matplotlib.dates as mdates
import io
import base64
from typing import List, Dict
import numpy as np

plt.style.use('seaborn-v0_8-whitegrid')


def generate_success_rate_chart(data: Dict) -> str:
    """Generate success rate gauge chart"""
    
    fig, ax = plt.subplots(figsize=(6, 4))
    
    success_rate = data.get('success_rate', 0)
    
    # Create gauge
    colors = ['#ff4444', '#ffaa00', '#44aa44']
    thresholds = [0, 85, 95, 100]
    
    for i in range(3):
        ax.barh(0, thresholds[i+1] - thresholds[i], left=thresholds[i],
                height=0.5, color=colors[i], alpha=0.3)
    
    # Current value marker
    ax.axvline(x=success_rate, color='black', linewidth=3)
    ax.scatter([success_rate], [0], s=200, color='black', zorder=5)
    
    ax.set_xlim(0, 100)
    ax.set_ylim(-0.5, 0.5)
    ax.set_xlabel('Success Rate (%)')
    ax.set_title(f'Patch Success Rate: {success_rate:.1f}%')
    ax.set_yticks([])
    
    return fig_to_base64(fig)


def generate_trend_chart(dates: List[str], values: List[float], 
                        metric_name: str) -> str:
    """Generate time series trend chart"""
    
    fig, ax = plt.subplots(figsize=(10, 5))
    
    x = range(len(dates))
    
    # Plot actual values
    ax.plot(x, values, 'b-', linewidth=2, label='Actual')
    ax.fill_between(x, values, alpha=0.3)
    
    # Add trend line
    z = np.polyfit(x, values, 1)
    p = np.poly1d(z)
    ax.plot(x, p(x), 'r--', linewidth=1, label='Trend')
    
    # Formatting
    ax.set_xlabel('Date')
    ax.set_ylabel(metric_name)
    ax.set_title(f'{metric_name} Trend')
    ax.set_xticks(x[::max(1, len(x)//10)])  # Show ~10 labels
    ax.set_xticklabels([dates[i] for i in x[::max(1, len(x)//10)]], rotation=45)
    ax.legend()
    
    plt.tight_layout()
    return fig_to_base64(fig)


def generate_comparison_bar_chart(labels: List[str], values: List[float],
                                  metric_name: str, highlight_threshold: float = None) -> str:
    """Generate horizontal bar chart for comparisons"""
    
    fig, ax = plt.subplots(figsize=(10, max(5, len(labels) * 0.4)))
    
    # Sort by value
    sorted_pairs = sorted(zip(labels, values), key=lambda x: x[1], reverse=True)
    labels, values = zip(*sorted_pairs)
    
    # Color based on performance
    colors = []
    for v in values:
        if highlight_threshold:
            colors.append('#44aa44' if v >= highlight_threshold else '#ff4444')
        else:
            colors.append('#4488cc')
    
    y_pos = range(len(labels))
    ax.barh(y_pos, values, color=colors)
    ax.set_yticks(y_pos)
    ax.set_yticklabels(labels)
    ax.set_xlabel(metric_name)
    ax.set_title(f'{metric_name} by Dimension')
    
    # Add value labels
    for i, v in enumerate(values):
        ax.text(v + 0.5, i, f'{v:.1f}%', va='center')
    
    plt.tight_layout()
    return fig_to_base64(fig)


def fig_to_base64(fig) -> str:
    """Convert matplotlib figure to base64 string"""
    buf = io.BytesIO()
    fig.savefig(buf, format='png', dpi=100, bbox_inches='tight')
    buf.seek(0)
    plt.close(fig)
    return base64.b64encode(buf.read()).decode('utf-8')
```

---

## 7. Sample Report Output

### 7.1 Weekly Executive Summary

```markdown
# EC2 Patching - Weekly Executive Summary

**Report Period:** January 8-14, 2026  
**Generated:** January 14, 2026 09:00 UTC

---

## Executive Summary

This week, the EC2 Patching Platform maintained a **96.8% success rate** 
across **1,247 instances**, deploying **4,892 patches** across 52 AWS accounts.

**Key Highlights:**
- ✅ Overall patch compliance exceeds 95% target
- 📈 Success rate improved 1.2% from last week
- ⚠️ 2 accounts require attention due to elevated failure rates

**Risk Status:** 🟢 Low

---

## Key Performance Indicators

| Metric | This Week | Last Week | Change |
|--------|-----------|-----------|--------|
| Success Rate | 96.8% | 95.6% | +1.2% ✅ |
| Instances Patched | 1,247 | 1,189 | +58 |
| Patches Installed | 4,892 | 4,567 | +325 |
| Avg Duration | 38 min | 42 min | -9.5% ✅ |
| SLA Adherence | 99.2% | 98.8% | +0.4% |

---

## Account Performance

| Account | Success Rate | Instances | Status |
|---------|--------------|-----------|--------|
| 111111111111 (Prod-1) | 100% | 234 | ✅ |
| 222222222222 (Prod-2) | 98.5% | 189 | ✅ |
| 333333333333 (Stage) | 97.2% | 156 | ✅ |
| 444444444444 (Dev) | 89.3% | 78 | ⚠️ |
| 555555555555 (Test) | 84.7% | 45 | ⚠️ |

---

## Recommendations

1. **Account 444444444444 (Dev):** Investigate SSM agent connectivity issues in us-west-2
2. **Account 555555555555 (Test):** Review instances with outdated AMIs causing patch failures
3. **General:** Consider implementing pre-patch validation checks to catch issues earlier

---

## Next Week Outlook

- Scheduled maintenance windows: 3
- Expected instances: ~1,300
- Known risks: None identified
```

---

## 8. IAM Permissions

```yaml
ReportingAgentRole:
  Type: AWS::IAM::Role
  Properties:
    RoleName: !Sub '${NamePrefix}-${Environment}-reporting-agent-role'
    AssumeRolePolicyDocument:
      Version: '2012-10-17'
      Statement:
        - Effect: Allow
          Principal:
            Service: bedrock.amazonaws.com
          Action: sts:AssumeRole
    Policies:
      - PolicyName: ReportingAgentPolicy
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
                - !Sub 'arn:aws:dynamodb:${AWS::Region}:${AWS::AccountId}:table/${StatsTable}'
                - !Sub 'arn:aws:dynamodb:${AWS::Region}:${AWS::AccountId}:table/${StatsTable}/index/*'
            
            # CloudWatch Read Access
            - Effect: Allow
              Action:
                - cloudwatch:GetMetricData
                - cloudwatch:GetMetricStatistics
                - cloudwatch:ListMetrics
                - cloudwatch:GetDashboard
              Resource: '*'
            
            # S3 Read/Write for Reports
            - Effect: Allow
              Action:
                - s3:GetObject
                - s3:PutObject
                - s3:ListBucket
              Resource:
                - !Sub 'arn:aws:s3:::${SnapshotsBucket}'
                - !Sub 'arn:aws:s3:::${SnapshotsBucket}/reports/*'
            
            # EventBridge for Scheduled Reports
            - Effect: Allow
              Action:
                - events:PutRule
                - events:PutTargets
                - events:DeleteRule
                - events:RemoveTargets
                - events:DescribeRule
              Resource:
                - !Sub 'arn:aws:events:${AWS::Region}:${AWS::AccountId}:rule/${NamePrefix}-report-*'
            
            # SNS for Report Delivery
            - Effect: Allow
              Action:
                - sns:Publish
              Resource:
                - !Sub 'arn:aws:sns:${AWS::Region}:${AWS::AccountId}:${NamePrefix}-*'
```

---

*Next: Agent 3 - Anomaly Detection & Root Cause Analysis Agent Technical Design*
