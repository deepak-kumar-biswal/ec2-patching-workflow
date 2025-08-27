import os
import json
import boto3
import uuid
import time
import logging
from typing import Dict, Any, Optional, List
from botocore.exceptions import ClientError, BotoCoreError
from functools import wraps
import hashlib
import re

# Configure structured logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - [%(correlation_id)s] - %(message)s'
)
logger = logging.getLogger(__name__)

class BedrockAnalysisError(Exception):
    """Custom exception for Bedrock analysis operations"""
    pass

def with_correlation_id(func):
    """Decorator to add correlation ID to all log messages"""
    @wraps(func)
    def wrapper(*args, **kwargs):
        correlation_id = str(uuid.uuid4())[:8]
        
        # Add correlation ID to logger
        old_factory = logging.getLogRecordFactory()
        def record_factory(*args, **kwargs):
            record = old_factory(*args, **kwargs)
            record.correlation_id = correlation_id
            return record
        
        logging.setLogRecordFactory(record_factory)
        
        try:
            return func(*args, **kwargs)
        finally:
            logging.setLogRecordFactory(old_factory)
    
    return wrapper

def retry_with_backoff(max_retries: int = 3, base_delay: float = 1.0):
    """Decorator for retry logic with exponential backoff"""
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            for attempt in range(max_retries):
                try:
                    return func(*args, **kwargs)
                except (ClientError, BotoCoreError) as e:
                    error_code = e.response.get('Error', {}).get('Code', 'Unknown') if hasattr(e, 'response') else 'Unknown'
                    
                    if attempt == max_retries - 1:
                        logger.error(f"Final retry failed for {func.__name__}: {error_code} - {str(e)}")
                        raise
                    
                    # Don't retry certain errors
                    if error_code in ['ValidationException', 'AccessDeniedException', 'ResourceNotFoundException']:
                        logger.error(f"Non-retryable error for {func.__name__}: {error_code}")
                        raise
                    
                    delay = base_delay * (2 ** attempt)
                    logger.warning(f"Retry {attempt + 1}/{max_retries} for {func.__name__} after {delay}s: {error_code}")
                    time.sleep(delay)
            return None
        return wrapper
    return decorator

def validate_input(event: Dict[str, Any]) -> Dict[str, Any]:
    """Validate and sanitize input data"""
    if not isinstance(event, dict):
        raise BedrockAnalysisError("Event must be a dictionary")
    
    # Extract configuration
    cfg = event.get('bedrock', {})
    if not isinstance(cfg, dict):
        cfg = {}
    
    # Validate agent configuration
    agent_id = cfg.get('agentId') or os.environ.get('BEDROCK_AGENT_ID')
    alias_id = cfg.get('agentAliasId') or os.environ.get('BEDROCK_AGENT_ALIAS_ID')
    
    if not agent_id:
        raise BedrockAnalysisError("Bedrock Agent ID is required")
    if not alias_id:
        raise BedrockAnalysisError("Bedrock Agent Alias ID is required")
    
    # Validate agent ID format
    if not re.match(r'^[A-Z0-9]{10}$', agent_id):
        raise BedrockAnalysisError("Invalid Bedrock Agent ID format")
    if not re.match(r'^[A-Z0-9]{10}$', alias_id):
        raise BedrockAnalysisError("Invalid Bedrock Agent Alias ID format")
    
    return {
        'agent_id': agent_id,
        'alias_id': alias_id,
        'event': event
    }

def extract_issues(event: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """Extract issues from various event structures"""
    issues = None
    
    # Try different event structures
    if 'post' in event and 'Payload' in event['post']:
        issues = event['post']['Payload'].get('issues')
    elif 'postEc2' in event and 'Payload' in event['postEc2']:
        issues = event['postEc2']['Payload'].get('issues')
    elif 'postWave' in event and len(event['postWave']) > 0:
        if 'Payload' in event['postWave'][0]:
            issues = event['postWave'][0]['Payload'].get('issues')
    elif 'issues' in event:
        issues = event['issues']
    
    return issues

def create_analysis_prompt(issues: Dict[str, Any], context: str = "standard") -> str:
    """Create a comprehensive analysis prompt for Bedrock"""
    
    base_prompt = """You are an expert Site Reliability Engineer (SRE) specializing in EC2 patch management and infrastructure automation. 

Your role is to analyze patching discrepancies and provide actionable recommendations for enterprise-scale environments.

ANALYSIS CONTEXT: {context}

PATCH EXECUTION ISSUES:
{issues_json}

Please provide a comprehensive analysis including:

1. **SEVERITY ASSESSMENT**: 
   - Critical: Requires immediate action, affects production stability
   - High: Should be addressed within 24 hours
   - Medium: Address within next maintenance window
   - Low: Monitor and address as resources allow

2. **ROOT CAUSE ANALYSIS**:
   - Primary causes of the identified issues
   - Contributing factors and dependencies
   - Historical patterns (if applicable)

3. **IMPACT ANALYSIS**:
   - Security implications
   - Performance impact
   - Business continuity risks
   - Compliance considerations

4. **IMMEDIATE ACTIONS**:
   - Emergency steps to mitigate risks
   - Rollback procedures (if needed)
   - Communication requirements

5. **REMEDIATION PLAN**:
   - Step-by-step resolution approach
   - Required resources and permissions
   - Estimated timeline and effort
   - Risk mitigation strategies

6. **PREVENTION STRATEGIES**:
   - Process improvements
   - Automation enhancements
   - Monitoring and alerting improvements
   - Best practices recommendations

7. **RECOMMENDATION**:
   - ABORT_EXECUTION: Critical issues requiring immediate halt
   - CONTINUE_WITH_CAUTION: Proceed with enhanced monitoring
   - CONTINUE_NORMAL: Issues are manageable, proceed as planned

Format your response as structured JSON with clear sections and actionable items.
"""
    
    return base_prompt.format(
        context=context.upper(),
        issues_json=json.dumps(issues, indent=2, default=str)
    )

@retry_with_backoff(max_retries=3, base_delay=2.0)
def invoke_bedrock_agent(agent_id: str, alias_id: str, prompt: str, session_id: str) -> str:
    """Invoke Bedrock agent with comprehensive error handling"""
    try:
        bedrock_client = boto3.client('bedrock-agent-runtime')
        
        logger.info(f"Invoking Bedrock agent {agent_id} with session {session_id}")
        start_time = time.time()
        
        response = bedrock_client.invoke_agent(
            agentId=agent_id,
            agentAliasId=alias_id,
            sessionId=session_id,
            inputText=prompt
        )
        
        execution_time = time.time() - start_time
        logger.info(f"Bedrock agent invocation completed in {execution_time:.2f}s")
        
        # Process response chunks
        chunks = []
        completion = response.get('completion', [])
        
        for chunk in completion:
            if 'chunk' in chunk:
                chunk_data = chunk['chunk']
                if 'bytes' in chunk_data:
                    # Decode bytes content
                    content = chunk_data['bytes'].decode('utf-8')
                    chunks.append(content)
                elif 'content' in chunk_data:
                    chunks.append(chunk_data['content'])
            elif 'content' in chunk:
                chunks.append(chunk['content'])
        
        result = "".join(chunks).strip()
        
        if not result:
            logger.warning("Bedrock agent returned empty response")
            return "Analysis completed but no specific recommendations generated. Please review the execution logs and consider manual investigation."
        
        logger.info(f"Bedrock analysis completed, response length: {len(result)} characters")
        return result
        
    except ClientError as e:
        error_code = e.response.get('Error', {}).get('Code', 'Unknown')
        error_message = e.response.get('Error', {}).get('Message', str(e))
        
        logger.error(f"Bedrock client error: {error_code} - {error_message}")
        
        if error_code == 'ThrottlingException':
            raise BedrockAnalysisError(f"Bedrock API rate limit exceeded: {error_message}")
        elif error_code == 'ValidationException':
            raise BedrockAnalysisError(f"Invalid request to Bedrock: {error_message}")
        elif error_code == 'AccessDeniedException':
            raise BedrockAnalysisError(f"Access denied to Bedrock agent: {error_message}")
        elif error_code == 'ResourceNotFoundException':
            raise BedrockAnalysisError(f"Bedrock agent not found: {error_message}")
        else:
            raise BedrockAnalysisError(f"Bedrock API error [{error_code}]: {error_message}")
    
    except Exception as e:
        logger.error(f"Unexpected error invoking Bedrock: {str(e)}")
        raise BedrockAnalysisError(f"Unexpected Bedrock error: {str(e)}")

def parse_analysis_response(response: str) -> Dict[str, Any]:
    """Parse and validate Bedrock analysis response"""
    try:
        # Try to parse as JSON first
        if response.strip().startswith('{'):
            return json.loads(response)
        
        # If not JSON, create structured response
        return {
            "analysis": response,
            "recommendation": "MANUAL_REVIEW_REQUIRED",
            "severity": "MEDIUM",
            "summary": "Analysis completed successfully but requires manual review of recommendations."
        }
    
    except json.JSONDecodeError as e:
        logger.warning(f"Failed to parse Bedrock response as JSON: {str(e)}")
        return {
            "analysis": response,
            "recommendation": "MANUAL_REVIEW_REQUIRED",
            "severity": "MEDIUM",
            "parse_error": str(e),
            "summary": "Analysis completed but response format requires manual interpretation."
        }

@with_correlation_id
def handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """
    Enhanced Bedrock analysis handler with comprehensive error handling and logging
    """
    start_time = time.time()
    
    try:
        logger.info(f"Starting Bedrock analysis with event keys: {list(event.keys())}")
        
        # Validate input
        validated_data = validate_input(event)
        agent_id = validated_data['agent_id']
        alias_id = validated_data['alias_id']
        
        # Extract issues
        issues = extract_issues(event)
        
        if not issues:
            logger.warning("No issues found in event data")
            return {
                'statusCode': 200,
                'success': True,
                'message': 'No issues detected - analysis not required',
                'recommendation': 'CONTINUE_NORMAL',
                'severity': 'LOW',
                'timestamp': time.time(),
                'execution_time_ms': (time.time() - start_time) * 1000
            }
        
        # Determine analysis context
        context_type = event.get('context', 'standard')
        if 'abortOnIssues' in event and event['abortOnIssues']:
            context_type = 'critical-failure-analysis'
        
        # Create analysis prompt
        prompt = create_analysis_prompt(issues, context_type)
        prompt_hash = hashlib.md5(prompt.encode()).hexdigest()[:8]
        
        # Generate unique session ID
        session_id = f"patch-analysis-{int(time.time())}-{prompt_hash}"
        
        logger.info(f"Created analysis session: {session_id}")
        logger.info(f"Analyzing {len(issues) if isinstance(issues, list) else 'N/A'} issues with context: {context_type}")
        
        # Invoke Bedrock agent
        analysis_response = invoke_bedrock_agent(agent_id, alias_id, prompt, session_id)
        
        # Parse response
        parsed_analysis = parse_analysis_response(analysis_response)
        
        # Add metadata
        execution_time = time.time() - start_time
        result = {
            'statusCode': 200,
            'success': True,
            'analysis': parsed_analysis,
            'recommendation': parsed_analysis.get('recommendation', 'MANUAL_REVIEW_REQUIRED'),
            'severity': parsed_analysis.get('severity', 'MEDIUM'),
            'session_id': session_id,
            'issues_analyzed': len(issues) if isinstance(issues, list) else 1,
            'execution_time_ms': execution_time * 1000,
            'timestamp': time.time(),
            'context': context_type
        }
        
        logger.info(f"Bedrock analysis completed successfully in {execution_time:.2f}s")
        logger.info(f"Recommendation: {result['recommendation']}, Severity: {result['severity']}")
        
        return result
        
    except BedrockAnalysisError as e:
        logger.error(f"Bedrock analysis error: {str(e)}")
        execution_time = time.time() - start_time
        
        return {
            'statusCode': 400,
            'success': False,
            'error': str(e),
            'error_type': 'BedrockAnalysisError',
            'recommendation': 'MANUAL_REVIEW_REQUIRED',
            'severity': 'HIGH',
            'execution_time_ms': execution_time * 1000,
            'timestamp': time.time()
        }
    
    except Exception as e:
        logger.error(f"Unexpected error in Bedrock analysis handler: {str(e)}")
        execution_time = time.time() - start_time
        
        return {
            'statusCode': 500,
            'success': False,
            'error': f"Unexpected error: {str(e)}",
            'error_type': 'UnexpectedError',
            'recommendation': 'ABORT_EXECUTION',
            'severity': 'CRITICAL',
            'execution_time_ms': execution_time * 1000,
            'timestamp': time.time()
        }
