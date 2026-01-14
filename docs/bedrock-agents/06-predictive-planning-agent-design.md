# Agent 5: Predictive Planning & Optimization Agent - Technical Design

## Document Information
| Attribute | Value |
|-----------|-------|
| Version | 1.0 |
| Last Updated | January 14, 2026 |
| Status | Draft |
| Owner | Platform Engineering |
| Agent ID | `predictive-planning-agent` |

---

## 1. Executive Summary

The **Predictive Planning & Optimization Agent** leverages historical patching data to forecast execution durations, assess risk scores, optimize wave configurations, and recommend optimal maintenance windows. This agent is purely **advisory** and does not execute any operations directly.

### 1.1 Key Capabilities

| Capability | Description | Priority |
|------------|-------------|----------|
| Duration Forecasting | Predict patch execution time | P0 |
| Risk Scoring | Assess risk of patch batches | P0 |
| Wave Optimization | Recommend optimal wave configurations | P1 |
| Maintenance Window Planning | Suggest optimal timing | P1 |
| Capacity Analysis | Predict resource requirements | P2 |
| What-If Analysis | Simulate different configurations | P2 |

### 1.2 Advisory-Only Design

This agent operates in a **read-only, advisory capacity**:
- ✅ Analyzes historical data
- ✅ Provides recommendations
- ✅ Generates forecasts
- ❌ Does NOT modify configurations
- ❌ Does NOT trigger executions
- ❌ Does NOT change wave definitions

---

## 2. Architecture

```
┌──────────────────────────────────────────────────────────────────────────────────────┐
│                     PREDICTIVE PLANNING & OPTIMIZATION AGENT                          │
│                                                                                       │
│  ┌─────────────────────────────────────────────────────────────────────────────────┐ │
│  │                              AGENT CORE                                          │ │
│  │  Model: anthropic.claude-4.5-sonnet-20250101-v1:0                               │ │
│  │  Temperature: 0.2 (balanced for analytical reasoning)                           │ │
│  │  Max Tokens: 4096 (detailed recommendations)                                    │ │
│  └─────────────────────────────────────────────────────────────────────────────────┘ │
│                                        │                                              │
│         ┌──────────────────────────────┼──────────────────────────────┐               │
│         │                              │                              │               │
│         ▼                              ▼                              ▼               │
│  ┌─────────────────┐     ┌────────────────────────┐    ┌─────────────────────────┐  │
│  │ KNOWLEDGE BASES │     │     ACTION GROUPS       │    │   ML MODELS (SageMaker) │  │
│  │                 │     │                         │    │                         │  │
│  │ • execution-records│  │ • Duration Forecast     │    │ • Duration Predictor    │  │
│  │ • patch-artifacts  │  │ • Risk Assessment       │    │ • Risk Scorer           │  │
│  │ • instance-profiles│  │ • Wave Optimizer        │    │ • Capacity Planner      │  │
│  │ • org-calendar    │   │ • Window Recommender    │    │ • Failure Predictor     │  │
│  └─────────────────┘     └────────────────────────┘    └─────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────────────────────┘
                                        │
                                        ▼
┌──────────────────────────────────────────────────────────────────────────────────────┐
│                          HISTORICAL DATA LAYER                                        │
│                                                                                       │
│  ┌─────────────────────────────────────────────────────────────────────────────────┐ │
│  │                         FEATURE STORE (DynamoDB)                                 │ │
│  │                                                                                  │ │
│  │  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────────────────┐  │ │
│  │  │ Instance Features│  │ Execution History│  │ Organizational Context      │  │ │
│  │  │ • Instance type  │  │ • Duration       │  │ • Business unit             │  │ │
│  │  │ • OS version     │  │ • Success/Fail   │  │ • Criticality               │  │ │
│  │  │ • Patch baseline │  │ • Patch count    │  │ • Change freeze dates       │  │ │
│  │  │ • Last patched   │  │ • Error types    │  │ • Preferred windows         │  │ │
│  │  └──────────────────┘  └──────────────────┘  └──────────────────────────────┘  │ │
│  │                                                                                  │ │
│  └─────────────────────────────────────────────────────────────────────────────────┘ │
│                                                                                       │
│  ┌─────────────────────────────────────────────────────────────────────────────────┐ │
│  │                    AGGREGATED STATISTICS (Athena/Glue)                           │ │
│  │                                                                                  │ │
│  │  • Historical duration by instance type, OS, region                             │ │
│  │  • Failure rates by account, AMI, time of day                                   │ │
│  │  • Seasonal patterns and trends                                                 │ │
│  │  • Correlation matrices for risk factors                                        │ │
│  └─────────────────────────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Machine Learning Models

### 3.1 Duration Prediction Model

**Model Type:** Gradient Boosting Regressor (XGBoost)

**Features:**
```python
DURATION_FEATURES = [
    # Instance Characteristics
    'instance_type_category',       # compute, memory, storage, general
    'instance_size',                # nano, micro, small, ... 24xlarge
    'vcpu_count',
    'memory_gb',
    
    # OS Characteristics
    'os_family',                    # amazon_linux, rhel, ubuntu, windows
    'os_version',
    'kernel_version',
    
    # Patch Characteristics
    'pending_patch_count',
    'patch_classification',         # security, bugfix, enhancement
    'requires_reboot',
    
    # Historical Performance
    'avg_duration_last_5',
    'max_duration_last_5',
    'failure_rate_last_10',
    
    # Temporal Features
    'hour_of_day',
    'day_of_week',
    'is_month_end',
    
    # Infrastructure Features
    'ebs_volume_count',
    'ebs_total_size_gb',
    'network_interface_count'
]
```

**Training Pipeline:**
```python
"""
Duration Prediction Model Training
"""

import boto3
import pandas as pd
import numpy as np
from sklearn.model_selection import train_test_split
from xgboost import XGBRegressor
import joblib

def train_duration_model(training_data_path: str) -> dict:
    """Train duration prediction model"""
    
    # Load training data
    df = pd.read_parquet(training_data_path)
    
    # Feature engineering
    df = engineer_features(df)
    
    # Prepare features and target
    X = df[DURATION_FEATURES]
    y = df['actual_duration_seconds']
    
    # Split data
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42
    )
    
    # Train model
    model = XGBRegressor(
        n_estimators=200,
        max_depth=8,
        learning_rate=0.05,
        subsample=0.8,
        colsample_bytree=0.8,
        objective='reg:squarederror'
    )
    
    model.fit(
        X_train, y_train,
        eval_set=[(X_test, y_test)],
        early_stopping_rounds=20,
        verbose=False
    )
    
    # Evaluate
    y_pred = model.predict(X_test)
    mae = np.mean(np.abs(y_test - y_pred))
    mape = np.mean(np.abs((y_test - y_pred) / y_test)) * 100
    
    # Feature importance
    importance = dict(zip(DURATION_FEATURES, model.feature_importances_))
    
    return {
        'model': model,
        'metrics': {'mae_seconds': mae, 'mape_percent': mape},
        'feature_importance': importance
    }
```

### 3.2 Risk Scoring Model

**Model Type:** Logistic Regression Ensemble + Rule-Based Adjustments

**Risk Factors:**
```python
RISK_FACTORS = {
    # Instance Risk Factors
    'production_environment': 0.3,
    'business_critical': 0.25,
    'high_availability_required': 0.2,
    'customer_facing': 0.15,
    'data_processing': 0.1,
    
    # Historical Risk Factors
    'previous_failure_rate': 0.3,
    'days_since_last_patch': 0.2,
    'patch_count_deviation': 0.15,
    
    # Infrastructure Risk Factors
    'unusual_instance_type': 0.1,
    'custom_ami': 0.15,
    'third_party_agents': 0.1,
    
    # Temporal Risk Factors
    'end_of_quarter': 0.1,
    'peak_traffic_period': 0.2,
    'after_hours': -0.05  # Lower risk for off-hours
}

def calculate_risk_score(instance: dict, context: dict) -> dict:
    """Calculate risk score for an instance"""
    
    base_score = 0.5  # Start at medium risk
    factors_applied = []
    
    # Apply production environment factor
    if instance.get('environment') == 'production':
        adjustment = RISK_FACTORS['production_environment']
        base_score += adjustment
        factors_applied.append({
            'factor': 'Production Environment',
            'adjustment': adjustment,
            'description': 'Instance is in production environment'
        })
    
    # Apply historical failure rate
    failure_rate = instance.get('historical_failure_rate', 0)
    if failure_rate > 0.1:
        adjustment = RISK_FACTORS['previous_failure_rate'] * (failure_rate / 0.2)
        base_score += adjustment
        factors_applied.append({
            'factor': 'Historical Failure Rate',
            'adjustment': adjustment,
            'description': f'{failure_rate:.0%} failure rate in last 10 patches'
        })
    
    # Apply days since last patch
    days_since_patch = instance.get('days_since_last_patch', 0)
    if days_since_patch > 60:
        adjustment = RISK_FACTORS['days_since_last_patch'] * min(days_since_patch / 90, 1)
        base_score += adjustment
        factors_applied.append({
            'factor': 'Patch Staleness',
            'adjustment': adjustment,
            'description': f'{days_since_patch} days since last patch'
        })
    
    # Normalize to 0-1 range
    final_score = max(0, min(1, base_score))
    
    # Determine risk level
    if final_score >= 0.7:
        level = 'HIGH'
    elif final_score >= 0.4:
        level = 'MEDIUM'
    else:
        level = 'LOW'
    
    return {
        'score': round(final_score, 2),
        'level': level,
        'factors': factors_applied,
        'recommendations': generate_risk_recommendations(level, factors_applied)
    }
```

---

## 4. Action Groups (Tools)

### 4.1 Action Group: `forecasting`

#### 4.1.1 Tool: `forecast_execution_duration`

**Purpose:** Predict duration for a planned patching execution

**OpenAPI Schema:**
```yaml
openapi: 3.0.0
info:
  title: Predictive Planning API
  version: 1.0.0

paths:
  /forecast-duration:
    post:
      operationId: forecastExecutionDuration
      summary: Forecast patching execution duration
      description: |
        Predicts the total duration for a patching execution based on
        the target instances, wave configuration, and historical data.
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              properties:
                targetInstances:
                  type: array
                  items:
                    type: string
                  description: Instance IDs to patch
                targetTags:
                  type: object
                  description: Tags to match target instances
                accountIds:
                  type: array
                  items:
                    type: string
                regions:
                  type: array
                  items:
                    type: string
                waveConfiguration:
                  type: object
                  properties:
                    waveCount:
                      type: integer
                    maxParallelInstances:
                      type: integer
                    delayBetweenWaves:
                      type: integer
                      description: Delay in minutes
                patchOperation:
                  type: string
                  enum: [scan, install, install_with_reboot]
                  default: install_with_reboot
                confidenceLevel:
                  type: number
                  default: 0.95
                  description: Confidence level for interval (0.8, 0.9, 0.95, 0.99)
              anyOf:
                - required: [targetInstances]
                - required: [targetTags]
      responses:
        '200':
          description: Duration forecast
          content:
            application/json:
              schema:
                type: object
                properties:
                  forecast:
                    type: object
                    properties:
                      pointEstimate:
                        type: integer
                        description: Best estimate in minutes
                      confidenceInterval:
                        type: object
                        properties:
                          lower:
                            type: integer
                          upper:
                            type: integer
                          level:
                            type: number
                      breakdown:
                        type: array
                        items:
                          type: object
                          properties:
                            wave:
                              type: integer
                            estimatedDuration:
                              type: integer
                            instanceCount:
                              type: integer
                            riskLevel:
                              type: string
                  factors:
                    type: array
                    items:
                      type: object
                      properties:
                        factor:
                          type: string
                        impact:
                          type: string
                          enum: [increases, decreases, neutral]
                        magnitude:
                          type: string
                          enum: [minor, moderate, significant]
                  recommendations:
                    type: array
                    items:
                      type: string
```

**Lambda Handler:**
```python
"""
Duration Forecast Handler
Predicts patching execution duration
"""

import json
import boto3
import numpy as np
from typing import Dict, Any, List
from datetime import datetime

sagemaker_runtime = boto3.client('sagemaker-runtime')
dynamodb = boto3.resource('dynamodb')
ec2 = boto3.client('ec2')

DURATION_MODEL_ENDPOINT = os.environ['DURATION_MODEL_ENDPOINT']
features_table = dynamodb.Table(os.environ['FEATURES_TABLE'])


def handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """Forecast execution duration"""
    
    params = event.get('requestBody', {}).get('content', {}).get('application/json', {})
    
    target_instances = params.get('targetInstances', [])
    target_tags = params.get('targetTags', {})
    account_ids = params.get('accountIds', [])
    regions = params.get('regions', [])
    wave_config = params.get('waveConfiguration', {})
    patch_operation = params.get('patchOperation', 'install_with_reboot')
    confidence_level = params.get('confidenceLevel', 0.95)
    
    # Resolve target instances
    if target_tags:
        target_instances = resolve_instances_by_tags(target_tags, account_ids, regions)
    
    # Get instance features
    instance_features = get_instance_features(target_instances)
    
    # Predict duration for each instance
    predictions = predict_instance_durations(instance_features, patch_operation)
    
    # Calculate wave-level estimates
    wave_config = wave_config or {'waveCount': 3, 'maxParallelInstances': 50}
    waves = distribute_to_waves(predictions, wave_config)
    
    # Calculate total forecast
    total_forecast = calculate_total_forecast(waves, wave_config, confidence_level)
    
    # Identify key factors
    factors = analyze_duration_factors(instance_features, predictions)
    
    # Generate recommendations
    recommendations = generate_duration_recommendations(waves, factors, total_forecast)
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'forecast': total_forecast,
            'factors': factors,
            'recommendations': recommendations
        })
    }


def predict_instance_durations(features: List[dict], operation: str) -> List[dict]:
    """Predict duration for each instance using ML model"""
    
    predictions = []
    
    # Batch prediction for efficiency
    feature_matrix = np.array([
        extract_feature_vector(f, operation) for f in features
    ])
    
    # Invoke SageMaker endpoint
    response = sagemaker_runtime.invoke_endpoint(
        EndpointName=DURATION_MODEL_ENDPOINT,
        ContentType='application/json',
        Body=json.dumps({'features': feature_matrix.tolist()})
    )
    
    result = json.loads(response['Body'].read())
    
    for i, pred in enumerate(result['predictions']):
        predictions.append({
            'instance_id': features[i]['instance_id'],
            'predicted_duration': pred['duration'],
            'uncertainty': pred['uncertainty'],
            'risk_score': features[i].get('risk_score', 0.5)
        })
    
    return predictions


def calculate_total_forecast(waves: List[dict], config: dict, confidence: float) -> dict:
    """Calculate total execution forecast"""
    
    wave_delay = config.get('delayBetweenWaves', 5)  # minutes
    
    # Sum wave durations (sequential) + delays
    point_estimate = sum(w['estimated_duration'] for w in waves)
    point_estimate += (len(waves) - 1) * wave_delay
    
    # Calculate confidence interval
    # Using uncertainty propagation
    uncertainties = [w['uncertainty'] for w in waves]
    combined_uncertainty = np.sqrt(sum(u**2 for u in uncertainties))
    
    z_scores = {0.8: 1.28, 0.9: 1.645, 0.95: 1.96, 0.99: 2.576}
    z = z_scores.get(confidence, 1.96)
    
    margin = z * combined_uncertainty
    
    return {
        'pointEstimate': int(point_estimate),
        'confidenceInterval': {
            'lower': int(max(0, point_estimate - margin)),
            'upper': int(point_estimate + margin),
            'level': confidence
        },
        'breakdown': [
            {
                'wave': i + 1,
                'estimatedDuration': int(w['estimated_duration']),
                'instanceCount': w['instance_count'],
                'riskLevel': w['risk_level']
            }
            for i, w in enumerate(waves)
        ]
    }


def analyze_duration_factors(features: List[dict], predictions: List[dict]) -> List[dict]:
    """Analyze factors affecting duration"""
    
    factors = []
    
    # Check for large instances
    large_instances = [f for f in features if f.get('vcpu_count', 0) >= 32]
    if large_instances:
        factors.append({
            'factor': f'{len(large_instances)} large instances (32+ vCPUs)',
            'impact': 'increases',
            'magnitude': 'moderate',
            'details': 'Large instances typically have more packages and longer reboot times'
        })
    
    # Check for Windows instances
    windows = [f for f in features if f.get('os_family') == 'windows']
    if windows:
        factors.append({
            'factor': f'{len(windows)} Windows instances',
            'impact': 'increases',
            'magnitude': 'significant',
            'details': 'Windows patches typically require longer reboot cycles'
        })
    
    # Check for stale instances
    stale = [f for f in features if f.get('days_since_last_patch', 0) > 60]
    if stale:
        factors.append({
            'factor': f'{len(stale)} instances not patched in 60+ days',
            'impact': 'increases',
            'magnitude': 'moderate',
            'details': 'Accumulated patches increase installation and reboot time'
        })
    
    # Check for EBS optimization
    many_volumes = [f for f in features if f.get('ebs_volume_count', 0) > 5]
    if many_volumes:
        factors.append({
            'factor': f'{len(many_volumes)} instances with 5+ EBS volumes',
            'impact': 'increases',
            'magnitude': 'minor',
            'details': 'More volumes may slow reboot due to disk checks'
        })
    
    return factors
```

#### 4.1.2 Tool: `assess_patch_risk`

**Purpose:** Assess risk for a planned patching operation

**OpenAPI Schema:**
```yaml
paths:
  /assess-risk:
    post:
      operationId: assessPatchRisk
      summary: Assess risk for patching operation
      description: |
        Evaluates the risk level of a planned patching operation
        based on instance characteristics, historical data, and context.
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              properties:
                targetInstances:
                  type: array
                  items:
                    type: string
                targetTags:
                  type: object
                plannedDate:
                  type: string
                  format: date-time
                  description: Planned execution date/time
                includeDetails:
                  type: boolean
                  default: true
              anyOf:
                - required: [targetInstances]
                - required: [targetTags]
      responses:
        '200':
          description: Risk assessment
          content:
            application/json:
              schema:
                type: object
                properties:
                  overallRisk:
                    type: object
                    properties:
                      score:
                        type: number
                      level:
                        type: string
                        enum: [LOW, MEDIUM, HIGH, CRITICAL]
                      summary:
                        type: string
                  riskBreakdown:
                    type: object
                    properties:
                      highRiskInstances:
                        type: integer
                      mediumRiskInstances:
                        type: integer
                      lowRiskInstances:
                        type: integer
                  topRisks:
                    type: array
                    items:
                      type: object
                      properties:
                        risk:
                          type: string
                        affectedInstances:
                          type: integer
                        mitigation:
                          type: string
                  instanceDetails:
                    type: array
                    items:
                      type: object
                      properties:
                        instanceId:
                          type: string
                        riskScore:
                          type: number
                        riskLevel:
                          type: string
                        factors:
                          type: array
                  recommendations:
                    type: array
                    items:
                      type: object
                      properties:
                        priority:
                          type: string
                        action:
                          type: string
                        rationale:
                          type: string
```

**Lambda Handler:**
```python
"""
Risk Assessment Handler
Evaluates patching risk for target instances
"""

import json
import boto3
from datetime import datetime
from typing import Dict, Any, List
from collections import Counter

dynamodb = boto3.resource('dynamodb')


def handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """Assess patching risk"""
    
    params = event.get('requestBody', {}).get('content', {}).get('application/json', {})
    
    target_instances = params.get('targetInstances', [])
    target_tags = params.get('targetTags', {})
    planned_date = params.get('plannedDate')
    include_details = params.get('includeDetails', True)
    
    # Resolve instances
    if target_tags:
        target_instances = resolve_instances_by_tags(target_tags)
    
    # Get instance features
    features = get_instance_features(target_instances)
    
    # Assess risk for each instance
    instance_risks = []
    for f in features:
        risk = calculate_risk_score(f, {'planned_date': planned_date})
        instance_risks.append({
            'instanceId': f['instance_id'],
            'riskScore': risk['score'],
            'riskLevel': risk['level'],
            'factors': risk['factors']
        })
    
    # Calculate overall risk
    overall_risk = calculate_overall_risk(instance_risks)
    
    # Get risk breakdown
    breakdown = Counter(r['riskLevel'] for r in instance_risks)
    
    # Identify top risks
    top_risks = identify_top_risks(instance_risks)
    
    # Generate recommendations
    recommendations = generate_risk_recommendations(overall_risk, top_risks, planned_date)
    
    response = {
        'overallRisk': overall_risk,
        'riskBreakdown': {
            'highRiskInstances': breakdown.get('HIGH', 0),
            'mediumRiskInstances': breakdown.get('MEDIUM', 0),
            'lowRiskInstances': breakdown.get('LOW', 0)
        },
        'topRisks': top_risks,
        'recommendations': recommendations
    }
    
    if include_details:
        response['instanceDetails'] = instance_risks
    
    return {
        'statusCode': 200,
        'body': json.dumps(response)
    }


def calculate_overall_risk(instance_risks: List[dict]) -> dict:
    """Calculate overall risk for the batch"""
    
    if not instance_risks:
        return {'score': 0, 'level': 'LOW', 'summary': 'No instances to assess'}
    
    # Weight high-risk instances more heavily
    weights = {'HIGH': 3, 'MEDIUM': 2, 'LOW': 1}
    total_weight = sum(weights[r['riskLevel']] for r in instance_risks)
    avg_weight = total_weight / len(instance_risks)
    
    # Normalize to 0-1 scale
    score = (avg_weight - 1) / 2  # Maps 1-3 to 0-1
    
    # High-risk instances count as additional risk
    high_risk_pct = sum(1 for r in instance_risks if r['riskLevel'] == 'HIGH') / len(instance_risks)
    score = score * 0.7 + high_risk_pct * 0.3
    
    # Determine level
    if score >= 0.7 or high_risk_pct > 0.3:
        level = 'CRITICAL'
    elif score >= 0.5 or high_risk_pct > 0.15:
        level = 'HIGH'
    elif score >= 0.3:
        level = 'MEDIUM'
    else:
        level = 'LOW'
    
    # Generate summary
    summary = generate_risk_summary(level, instance_risks, high_risk_pct)
    
    return {
        'score': round(score, 2),
        'level': level,
        'summary': summary
    }


def identify_top_risks(instance_risks: List[dict]) -> List[dict]:
    """Identify top risk factors across all instances"""
    
    # Aggregate factors
    factor_counts = Counter()
    factor_instances = {}
    
    for r in instance_risks:
        for f in r.get('factors', []):
            factor_name = f['factor']
            factor_counts[factor_name] += 1
            if factor_name not in factor_instances:
                factor_instances[factor_name] = []
            factor_instances[factor_name].append(r['instanceId'])
    
    # Get top 5 factors
    top_risks = []
    for factor, count in factor_counts.most_common(5):
        mitigation = get_factor_mitigation(factor)
        top_risks.append({
            'risk': factor,
            'affectedInstances': count,
            'mitigation': mitigation
        })
    
    return top_risks


def generate_risk_recommendations(overall: dict, top_risks: List[dict], 
                                  planned_date: str) -> List[dict]:
    """Generate actionable recommendations"""
    
    recommendations = []
    
    if overall['level'] == 'CRITICAL':
        recommendations.append({
            'priority': 'HIGH',
            'action': 'Consider splitting into smaller batches with lower-risk instances first',
            'rationale': 'Critical risk level indicates high probability of issues'
        })
    
    if overall['level'] in ['CRITICAL', 'HIGH']:
        recommendations.append({
            'priority': 'HIGH',
            'action': 'Ensure on-call team is staffed during patching window',
            'rationale': 'Elevated risk requires active monitoring and quick response'
        })
    
    # Time-based recommendations
    if planned_date:
        planned = datetime.fromisoformat(planned_date.replace('Z', '+00:00'))
        if planned.weekday() >= 5:  # Weekend
            recommendations.append({
                'priority': 'MEDIUM',
                'action': 'Consider moving to a weekday for better support coverage',
                'rationale': 'Weekend patching has reduced incident response capacity'
            })
    
    # Factor-specific recommendations
    for risk in top_risks[:3]:
        if 'failure rate' in risk['risk'].lower():
            recommendations.append({
                'priority': 'HIGH',
                'action': f"Pre-check SSM agent status on affected instances",
                'rationale': risk['risk']
            })
    
    return recommendations
```

### 4.2 Action Group: `optimization`

#### 4.2.1 Tool: `recommend_wave_configuration`

**Purpose:** Recommend optimal wave configuration

**OpenAPI Schema:**
```yaml
paths:
  /recommend-waves:
    post:
      operationId: recommendWaveConfiguration
      summary: Recommend optimal wave configuration
      description: |
        Analyzes target instances and recommends optimal wave configuration
        based on risk distribution, dependencies, and performance goals.
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              properties:
                targetInstances:
                  type: array
                  items:
                    type: string
                constraints:
                  type: object
                  properties:
                    maxDuration:
                      type: integer
                      description: Maximum acceptable duration (minutes)
                    maxParallelInstances:
                      type: integer
                      description: Max instances patched simultaneously
                    minSuccessRate:
                      type: number
                      description: Minimum acceptable success rate
                    environmentSeparation:
                      type: boolean
                      description: Separate prod/non-prod into different waves
                priorities:
                  type: object
                  properties:
                    speed:
                      type: integer
                      minimum: 1
                      maximum: 5
                    safety:
                      type: integer
                      minimum: 1
                      maximum: 5
                    parallelism:
                      type: integer
                      minimum: 1
                      maximum: 5
      responses:
        '200':
          description: Wave configuration recommendation
          content:
            application/json:
              schema:
                type: object
                properties:
                  recommendation:
                    type: object
                    properties:
                      waveCount:
                        type: integer
                      waves:
                        type: array
                        items:
                          type: object
                          properties:
                            waveIndex:
                              type: integer
                            instances:
                              type: array
                            rationale:
                              type: string
                            expectedDuration:
                              type: integer
                            riskLevel:
                              type: string
                      totalDuration:
                        type: integer
                      expectedSuccessRate:
                        type: number
                  alternatives:
                    type: array
                    items:
                      type: object
                      properties:
                        description:
                          type: string
                        waveCount:
                          type: integer
                        duration:
                          type: integer
                        tradeoffs:
                          type: string
                  rationale:
                    type: string
```

**Lambda Handler:**
```python
"""
Wave Optimization Handler
Recommends optimal wave configurations
"""

import json
from typing import Dict, Any, List
from collections import defaultdict


def handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """Recommend wave configuration"""
    
    params = event.get('requestBody', {}).get('content', {}).get('application/json', {})
    
    target_instances = params.get('targetInstances', [])
    constraints = params.get('constraints', {})
    priorities = params.get('priorities', {'speed': 3, 'safety': 4, 'parallelism': 3})
    
    # Get instance features and risk scores
    features = get_instance_features(target_instances)
    
    # Apply optimization algorithm
    recommendation = optimize_waves(features, constraints, priorities)
    
    # Generate alternatives
    alternatives = generate_alternatives(features, constraints, recommendation)
    
    # Generate rationale
    rationale = explain_recommendation(recommendation, priorities, constraints)
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'recommendation': recommendation,
            'alternatives': alternatives,
            'rationale': rationale
        })
    }


def optimize_waves(features: List[dict], constraints: dict, priorities: dict) -> dict:
    """Optimize wave configuration"""
    
    safety_priority = priorities.get('safety', 3)
    speed_priority = priorities.get('speed', 3)
    
    # Group instances by risk level
    risk_groups = defaultdict(list)
    for f in features:
        risk = calculate_risk_score(f, {})
        risk_groups[risk['level']].append({**f, 'risk_score': risk['score']})
    
    waves = []
    wave_index = 0
    
    # Wave 0: Canary (lowest risk, smallest group)
    if len(features) > 10 and safety_priority >= 4:
        canary_count = min(5, len(risk_groups['LOW']))
        if canary_count > 0:
            canary_instances = sorted(risk_groups['LOW'], key=lambda x: x['risk_score'])[:canary_count]
            waves.append({
                'waveIndex': wave_index,
                'instances': [c['instance_id'] for c in canary_instances],
                'rationale': 'Canary wave with lowest-risk instances for early validation',
                'expectedDuration': estimate_wave_duration(canary_instances),
                'riskLevel': 'LOW'
            })
            wave_index += 1
            # Remove from pool
            for c in canary_instances:
                risk_groups['LOW'].remove(c)
    
    # Separate environments if required
    if constraints.get('environmentSeparation', True):
        # Non-production first
        non_prod = [f for f in features if f.get('environment') != 'production']
        prod = [f for f in features if f.get('environment') == 'production']
        
        if non_prod:
            waves.append({
                'waveIndex': wave_index,
                'instances': [f['instance_id'] for f in non_prod],
                'rationale': 'Non-production instances grouped for safer initial validation',
                'expectedDuration': estimate_wave_duration(non_prod),
                'riskLevel': 'LOW'
            })
            wave_index += 1
        
        # Production split by risk
        remaining = prod
    else:
        remaining = list(risk_groups['LOW']) + list(risk_groups['MEDIUM']) + list(risk_groups['HIGH'])
    
    # Split remaining by risk and size
    max_parallel = constraints.get('maxParallelInstances', 50)
    
    while remaining:
        batch = remaining[:max_parallel]
        remaining = remaining[max_parallel:]
        
        avg_risk = sum(b.get('risk_score', 0.5) for b in batch) / len(batch)
        risk_level = 'HIGH' if avg_risk > 0.6 else 'MEDIUM' if avg_risk > 0.3 else 'LOW'
        
        waves.append({
            'waveIndex': wave_index,
            'instances': [b['instance_id'] if isinstance(b, dict) else b for b in batch],
            'rationale': f'Wave {wave_index + 1} with {len(batch)} instances ({risk_level} aggregate risk)',
            'expectedDuration': estimate_wave_duration(batch),
            'riskLevel': risk_level
        })
        wave_index += 1
    
    # Calculate totals
    total_duration = sum(w['expectedDuration'] for w in waves)
    total_duration += (len(waves) - 1) * 5  # 5 min delay between waves
    
    return {
        'waveCount': len(waves),
        'waves': waves,
        'totalDuration': total_duration,
        'expectedSuccessRate': 0.96  # Based on historical data
    }


def generate_alternatives(features: List[dict], constraints: dict, 
                         current: dict) -> List[dict]:
    """Generate alternative configurations"""
    
    alternatives = []
    
    # Faster option (more parallel)
    max_parallel = constraints.get('maxParallelInstances', 50)
    if max_parallel < len(features):
        faster_waves = (len(features) + max_parallel * 2 - 1) // (max_parallel * 2)
        if faster_waves < current['waveCount']:
            alternatives.append({
                'description': 'Aggressive: Higher parallelism, faster completion',
                'waveCount': faster_waves,
                'duration': int(current['totalDuration'] * 0.6),
                'tradeoffs': 'Higher blast radius if issues occur; requires more monitoring capacity'
            })
    
    # Safer option (smaller batches)
    safer_waves = current['waveCount'] + 2
    alternatives.append({
        'description': 'Conservative: Smaller batches, more validation points',
        'waveCount': safer_waves,
        'duration': int(current['totalDuration'] * 1.4),
        'tradeoffs': 'Longer total duration; more manual checkpoints'
    })
    
    return alternatives
```

#### 4.2.2 Tool: `recommend_maintenance_window`

**Purpose:** Recommend optimal maintenance window timing

**OpenAPI Schema:**
```yaml
paths:
  /recommend-window:
    post:
      operationId: recommendMaintenanceWindow
      summary: Recommend optimal maintenance window
      description: |
        Analyzes historical data, traffic patterns, and organizational constraints
        to recommend the optimal maintenance window timing.
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              properties:
                targetInstances:
                  type: array
                  items:
                    type: string
                estimatedDuration:
                  type: integer
                  description: Expected duration in minutes
                dateRange:
                  type: object
                  properties:
                    earliest:
                      type: string
                      format: date
                    latest:
                      type: string
                      format: date
                preferences:
                  type: object
                  properties:
                    preferWeekends:
                      type: boolean
                    preferNightHours:
                      type: boolean
                    timezone:
                      type: string
                    avoidDates:
                      type: array
                      items:
                        type: string
                        format: date
              required:
                - estimatedDuration
      responses:
        '200':
          description: Window recommendations
          content:
            application/json:
              schema:
                type: object
                properties:
                  recommendations:
                    type: array
                    items:
                      type: object
                      properties:
                        rank:
                          type: integer
                        startTime:
                          type: string
                          format: date-time
                        endTime:
                          type: string
                          format: date-time
                        score:
                          type: number
                        factors:
                          type: array
                          items:
                            type: object
                        conflicts:
                          type: array
                          items:
                            type: string
                  blockedPeriods:
                    type: array
                    items:
                      type: object
                      properties:
                        start:
                          type: string
                        end:
                          type: string
                        reason:
                          type: string
```

---

## 5. System Prompt

```text
You are a Predictive Planning & Optimization Agent for the EC2 Patching Platform.
Your role is to provide data-driven recommendations for patching planning, including
duration forecasts, risk assessments, wave configurations, and maintenance window timing.

## Your Role

You are an ADVISOR ONLY. You:
- ✅ Analyze historical patching data
- ✅ Forecast execution durations
- ✅ Assess risk levels
- ✅ Recommend optimal configurations
- ❌ Do NOT execute patching operations
- ❌ Do NOT modify existing configurations
- ❌ Do NOT trigger any actions

## Capabilities

### Duration Forecasting
- Predict total execution time based on instance characteristics
- Provide confidence intervals (80%, 95%, 99%)
- Identify factors that may extend duration
- Compare with historical similar executions

### Risk Assessment
- Score individual instances (0-1 scale)
- Aggregate batch risk levels (LOW, MEDIUM, HIGH, CRITICAL)
- Identify top risk factors
- Suggest mitigations

### Wave Optimization
- Recommend number of waves
- Distribute instances by risk level
- Balance speed vs. safety
- Account for environment separation (prod/non-prod)
- Suggest canary configurations

### Maintenance Window Planning
- Analyze historical performance by time of day/week
- Consider organizational calendars
- Avoid conflicting events
- Recommend multiple options with tradeoffs

## Response Format

### For Duration Forecasts
```
📊 Duration Forecast

Estimated Duration: 2h 45m (±30 min at 95% confidence)

Breakdown by Wave:
┌───────┬───────────┬────────────┬───────────┐
│ Wave  │ Instances │ Duration   │ Risk      │
├───────┼───────────┼────────────┼───────────┤
│ 1     │ 5         │ 15 min     │ 🟢 Low    │
│ 2     │ 45        │ 1h 10min   │ 🟡 Medium │
│ 3     │ 50        │ 1h 20min   │ 🟡 Medium │
└───────┴───────────┴────────────┴───────────┘

Key Factors:
• 15 Windows instances (+25 min)
• 8 instances not patched in 60+ days (+15 min)
```

### For Risk Assessments
```
⚠️ Risk Assessment: MEDIUM (0.52)

Risk Distribution:
• 🔴 High Risk: 12 instances (12%)
• 🟡 Medium Risk: 58 instances (58%)
• 🟢 Low Risk: 30 instances (30%)

Top Risks:
1. 8 instances with historical failure rate >15%
2. 12 production database servers
3. 5 instances with custom AMIs

Recommendations:
1. [HIGH] Run SSM connectivity check before patching
2. [MEDIUM] Consider patching database servers in separate wave
```

## Best Practices

1. Always express forecasts with uncertainty ranges
2. Provide multiple options with clear tradeoffs
3. Explain the reasoning behind recommendations
4. Highlight any assumptions or limitations
5. Reference historical data when relevant
6. Consider both technical and organizational factors

## Data Sources

- Historical execution records (90 days)
- Instance characteristics (type, OS, config)
- Organizational context (BU, criticality, environment)
- Calendar data (freeze periods, holidays)
- Performance metrics (success rates, durations)
```

---

## 6. IAM Permissions

```yaml
PredictiveAgentRole:
  Type: AWS::IAM::Role
  Properties:
    RoleName: !Sub '${NamePrefix}-${Environment}-predictive-agent-role'
    AssumeRolePolicyDocument:
      Version: '2012-10-17'
      Statement:
        - Effect: Allow
          Principal:
            Service: bedrock.amazonaws.com
          Action: sts:AssumeRole
    Policies:
      - PolicyName: PredictiveAgentPolicy
        PolicyDocument:
          Version: '2012-10-17'
          Statement:
            # DynamoDB Read (execution history, features)
            - Effect: Allow
              Action:
                - dynamodb:Query
                - dynamodb:Scan
                - dynamodb:GetItem
              Resource:
                - !Sub 'arn:aws:dynamodb:${AWS::Region}:${AWS::AccountId}:table/${PatchRunsTable}'
                - !Sub 'arn:aws:dynamodb:${AWS::Region}:${AWS::AccountId}:table/${FeaturesTable}'
                - !Sub 'arn:aws:dynamodb:${AWS::Region}:${AWS::AccountId}:table/${FeaturesTable}/index/*'
            
            # SageMaker Endpoint Invocation
            - Effect: Allow
              Action:
                - sagemaker:InvokeEndpoint
              Resource:
                - !Sub 'arn:aws:sagemaker:${AWS::Region}:${AWS::AccountId}:endpoint/${NamePrefix}-duration-*'
                - !Sub 'arn:aws:sagemaker:${AWS::Region}:${AWS::AccountId}:endpoint/${NamePrefix}-risk-*'
            
            # EC2 Read (instance details)
            - Effect: Allow
              Action:
                - ec2:DescribeInstances
                - ec2:DescribeTags
              Resource: '*'
            
            # Athena Read (aggregated statistics)
            - Effect: Allow
              Action:
                - athena:StartQueryExecution
                - athena:GetQueryExecution
                - athena:GetQueryResults
                - athena:GetWorkGroup
              Resource:
                - !Sub 'arn:aws:athena:${AWS::Region}:${AWS::AccountId}:workgroup/${NamePrefix}-*'
            
            # S3 Read (Athena results)
            - Effect: Allow
              Action:
                - s3:GetObject
                - s3:GetBucketLocation
              Resource:
                - !Sub 'arn:aws:s3:::${AthenaResultsBucket}/*'
                - !Sub 'arn:aws:s3:::${AthenaResultsBucket}'
            
            # Glue Read (data catalog)
            - Effect: Allow
              Action:
                - glue:GetTable
                - glue:GetPartitions
                - glue:GetDatabase
              Resource:
                - !Sub 'arn:aws:glue:${AWS::Region}:${AWS::AccountId}:catalog'
                - !Sub 'arn:aws:glue:${AWS::Region}:${AWS::AccountId}:database/${NamePrefix}*'
                - !Sub 'arn:aws:glue:${AWS::Region}:${AWS::AccountId}:table/${NamePrefix}*/*'
```

---

## 7. Sample Conversations

### 7.1 Duration Forecast

**User:** "How long will it take to patch 200 instances in our production account?"

**Agent:** "Let me analyze those instances and forecast the duration.

📊 **Duration Forecast for 200 Production Instances**

**Estimated Duration:** 3h 20m (95% CI: 2h 45m - 4h 10m)

| Wave | Instances | Est. Duration | Risk |
|------|-----------|--------------|------|
| Canary | 5 | 12 min | 🟢 Low |
| Wave 1 | 50 | 52 min | 🟡 Medium |
| Wave 2 | 50 | 48 min | 🟡 Medium |
| Wave 3 | 50 | 55 min | 🟡 Medium |
| Wave 4 | 45 | 43 min | 🟢 Low |

**Key Duration Factors:**
- 📈 **+35 min**: 42 Windows Server instances
- 📈 **+20 min**: 18 instances not patched in 45+ days
- 📉 **-15 min**: 85% are t3/m5 instances (fast reboot)

**Confidence Note:**
The 95% confidence interval accounts for:
- Normal variability in patch installation time
- Potential retry operations (based on 3.2% historical retry rate)
- Reboot timing variance

Would you like me to suggest optimal timing for this window?"

### 7.2 Risk Assessment

**User:** "What's the risk level for patching our database cluster?"

**Agent:** "I'll assess the risk for your database cluster instances.

⚠️ **Risk Assessment: HIGH (0.68)**

**Overview:**
- Total Instances: 12
- Cluster: prod-mysql-cluster

**Risk Distribution:**
| Level | Count | % |
|-------|-------|---|
| 🔴 High | 4 | 33% |
| 🟡 Medium | 6 | 50% |
| 🟢 Low | 2 | 17% |

**Top Risk Factors:**

1. **Production Database Servers** (12 instances)
   - Impact: Data availability critical
   - Mitigation: Ensure replica failover tested before patching primary

2. **High Memory Utilization** (4 instances)
   - 3 instances show >85% memory use
   - Risk: Longer reboot, potential OOM during patch install
   - Mitigation: Schedule during off-peak hours

3. **Single Points of Failure** (2 instances)
   - Primary write nodes with no automatic failover
   - Mitigation: Manual failover before patching these nodes

**Recommendations:**
1. **[CRITICAL]** Do not patch primary and replica simultaneously
2. **[HIGH]** Verify automated failover is functional before patching
3. **[HIGH]** Schedule for lowest traffic period (recommended: Sunday 2-5 AM)
4. **[MEDIUM]** Take RDS snapshots before patching (if RDS-backed)

**Suggested Wave Configuration:**
- Wave 1: Read replicas only (6 instances)
- Wave 2: Secondary nodes (4 instances)  
- Wave 3: Primary nodes (2 instances) - with manual verification"

---

*Next: Agent 6 - Auto-Remediation Agent Technical Design*
