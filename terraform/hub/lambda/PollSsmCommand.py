import os
import json
import boto3
import uuid
import time
import logging
from typing import Dict, Any, List, Optional
from botocore.exceptions import ClientError, BotoCoreError
from functools import wraps
from datetime import datetime, timedelta

# Configure structured logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - [%(correlation_id)s] - %(message)s'
)
logger = logging.getLogger(__name__)

class SSMPollingError(Exception):
    """Custom exception for SSM polling operations"""
    pass

def with_correlation_id(func):
    """Decorator to add correlation ID to all log messages"""
    @wraps(func)
    def wrapper(*args, **kwargs):
        correlation_id = str(uuid.uuid4())[:8]
        
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
                    
                    if error_code in ['ValidationException', 'AccessDeniedException']:
                        logger.error(f"Non-retryable error: {error_code}")
                        raise
                    
                    delay = base_delay * (2 ** attempt)
                    logger.warning(f"Retry {attempt + 1}/{max_retries} for {func.__name__} after {delay}s: {error_code}")
                    time.sleep(delay)
            return None
        return wrapper
    return decorator

def validate_input(event: Dict[str, Any]) -> Dict[str, Any]:
    """Validate and extract required parameters from event"""
    required_fields = ['roleArn', 'region', 'cmd']
    missing_fields = [field for field in required_fields if field not in event]
    
    if missing_fields:
        raise SSMPollingError(f"Missing required fields: {', '.join(missing_fields)}")
    
    # Validate role ARN format
    role_arn = event['roleArn']
    if not role_arn.startswith('arn:aws:iam::') or ':role/' not in role_arn:
        raise SSMPollingError(f"Invalid role ARN format: {role_arn}")
    
    # Validate region format
    region = event['region']
    if not region or len(region) < 8:  # Minimum valid region length
        raise SSMPollingError(f"Invalid region: {region}")
    
    # Extract command information
    cmd_info = event['cmd']
    if isinstance(cmd_info, dict) and 'Command' in cmd_info:
        command_id = cmd_info['Command'].get('CommandId')
    elif isinstance(cmd_info, dict) and 'CommandId' in cmd_info:
        command_id = cmd_info['CommandId']
    else:
        raise SSMPollingError("Invalid command structure - missing CommandId")
    
    if not command_id:
        raise SSMPollingError("Command ID not found in event")
    
    return {
        'role_arn': role_arn,
        'region': region,
        'command_id': command_id,
        'account_id': event.get('accountId', 'unknown'),
        'execution_id': event.get('executionId', 'unknown')
    }

@retry_with_backoff(max_retries=3)
def assume_cross_account_role(role_arn: str, account_id: str) -> Dict[str, str]:
    """Assume cross-account role with enhanced error handling"""
    try:
        sts_client = boto3.client('sts')
        session_name = f"ssm-polling-{account_id}-{int(time.time())}"
        
        logger.info(f"Assuming role: {role_arn}")
        
        response = sts_client.assume_role(
            RoleArn=role_arn,
            RoleSessionName=session_name,
            DurationSeconds=3600  # 1 hour
        )
        
        credentials = response['Credentials']
        logger.info(f"Successfully assumed role for account {account_id}")
        
        return credentials
        
    except ClientError as e:
        error_code = e.response.get('Error', {}).get('Code', 'Unknown')
        error_message = e.response.get('Error', {}).get('Message', str(e))
        
        logger.error(f"Failed to assume role {role_arn}: {error_code} - {error_message}")
        
        if error_code == 'AccessDenied':
            raise SSMPollingError(f"Access denied assuming role in account {account_id}. Check cross-account trust relationship.")
        elif error_code == 'InvalidUserID.NotFound':
            raise SSMPollingError(f"Role not found in account {account_id}: {role_arn}")
        else:
            raise SSMPollingError(f"Role assumption failed [{error_code}]: {error_message}")

def create_ssm_client(credentials: Dict[str, str], region: str) -> boto3.client:
    """Create SSM client with assumed role credentials"""
    try:
        return boto3.client(
            'ssm',
            region_name=region,
            aws_access_key_id=credentials['AccessKeyId'],
            aws_secret_access_key=credentials['SecretAccessKey'],
            aws_session_token=credentials['SessionToken']
        )
    except Exception as e:
        logger.error(f"Failed to create SSM client: {str(e)}")
        raise SSMPollingError(f"SSM client creation failed: {str(e)}")

@retry_with_backoff(max_retries=3)
def get_command_invocations(ssm_client, command_id: str) -> List[Dict[str, Any]]:
    """Get command invocations with pagination and detailed status"""
    try:
        logger.info(f"Retrieving command invocations for: {command_id}")
        
        invocations = []
        paginator = ssm_client.get_paginator('list_command_invocations')
        
        for page in paginator.paginate(CommandId=command_id, Details=True):
            page_invocations = page.get('CommandInvocations', [])
            invocations.extend(page_invocations)
        
        logger.info(f"Found {len(invocations)} command invocations")
        return invocations
        
    except ClientError as e:
        error_code = e.response.get('Error', {}).get('Code', 'Unknown')
        error_message = e.response.get('Error', {}).get('Message', str(e))
        
        logger.error(f"Failed to get command invocations: {error_code} - {error_message}")
        
        if error_code == 'InvalidCommandId':
            raise SSMPollingError(f"Command not found: {command_id}")
        elif error_code == 'AccessDeniedException':
            raise SSMPollingError(f"Access denied retrieving command invocations: {command_id}")
        else:
            raise SSMPollingError(f"Failed to retrieve command invocations [{error_code}]: {error_message}")

def analyze_command_status(invocations: List[Dict[str, Any]], command_id: str) -> Dict[str, Any]:
    """Comprehensive analysis of command execution status"""
    
    if not invocations:
        return {
            'all_done': False,
            'status': 'NO_INVOCATIONS',
            'summary': 'No command invocations found',
            'total_instances': 0,
            'completed_instances': 0,
            'should_continue_polling': True,
            'reason': 'No invocations detected yet - command may still be starting'
        }
    
    total_instances = len(invocations)
    status_counts = {}
    completed_statuses = {'Success', 'Cancelled', 'Failed', 'TimedOut'}
    running_statuses = {'InProgress', 'Pending', 'Delayed'}
    
    completed_instances = 0
    in_progress_instances = 0
    failed_instances = 0
    successful_instances = 0
    
    detailed_results = []
    
    for inv in invocations:
        status = inv.get('Status', 'Unknown')
        instance_id = inv.get('InstanceId', 'unknown')
        
        status_counts[status] = status_counts.get(status, 0) + 1
        
        if status in completed_statuses:
            completed_instances += 1
            
        if status in running_statuses:
            in_progress_instances += 1
            
        if status == 'Success':
            successful_instances += 1
        elif status in ['Failed', 'TimedOut', 'Cancelled']:
            failed_instances += 1
        
        # Collect detailed information
        detailed_results.append({
            'instance_id': instance_id,
            'status': status,
            'status_details': inv.get('StatusDetails', ''),
            'standard_output_url': inv.get('StandardOutputUrl', ''),
            'standard_error_url': inv.get('StandardErrorUrl', ''),
            'start_time': inv.get('RequestedDateTime', ''),
            'end_time': inv.get('ResponseFinishDateTime', '')
        })
    
    # Determine if all instances are done
    all_done = (completed_instances == total_instances) and total_instances > 0
    
    # Calculate success rate
    success_rate = (successful_instances / total_instances * 100) if total_instances > 0 else 0
    failure_rate = (failed_instances / total_instances * 100) if total_instances > 0 else 0
    
    # Determine overall status
    if all_done:
        if failure_rate > 50:
            overall_status = 'MAJORITY_FAILED'
        elif failure_rate > 20:
            overall_status = 'HIGH_FAILURE_RATE'
        elif failure_rate > 0:
            overall_status = 'COMPLETED_WITH_FAILURES'
        else:
            overall_status = 'ALL_SUCCESS'
    else:
        if in_progress_instances > 0:
            overall_status = 'IN_PROGRESS'
        else:
            overall_status = 'UNKNOWN'
    
    result = {
        'all_done': all_done,
        'status': overall_status,
        'total_instances': total_instances,
        'completed_instances': completed_instances,
        'in_progress_instances': in_progress_instances,
        'successful_instances': successful_instances,
        'failed_instances': failed_instances,
        'success_rate': round(success_rate, 1),
        'failure_rate': round(failure_rate, 1),
        'status_counts': status_counts,
        'should_continue_polling': not all_done,
        'detailed_results': detailed_results[:10],  # Limit to first 10 for payload size
        'command_id': command_id
    }
    
    # Add summary message
    if all_done:
        if overall_status == 'ALL_SUCCESS':
            result['summary'] = f"All {total_instances} instances completed successfully"
        else:
            result['summary'] = f"Completed: {successful_instances} successful, {failed_instances} failed out of {total_instances} instances"
        result['reason'] = 'All instances have completed execution'
    else:
        result['summary'] = f"In progress: {completed_instances}/{total_instances} instances completed"
        result['reason'] = f"{in_progress_instances} instances still running"
    
    return result

@with_correlation_id
def handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """
    Enhanced SSM command polling handler with comprehensive status tracking
    """
    start_time = time.time()
    
    try:
        logger.info(f"Starting SSM command polling with event: {json.dumps({k: v for k, v in event.items() if k not in ['cmd']}, default=str)}")
        
        # Validate input
        validated_data = validate_input(event)
        role_arn = validated_data['role_arn']
        region = validated_data['region']
        command_id = validated_data['command_id']
        account_id = validated_data['account_id']
        execution_id = validated_data['execution_id']
        
        logger.info(f"Polling command {command_id} in account {account_id}, region {region}")
        
        # Assume cross-account role
        credentials = assume_cross_account_role(role_arn, account_id)
        
        # Create SSM client
        ssm_client = create_ssm_client(credentials, region)
        
        # Get command invocations
        invocations = get_command_invocations(ssm_client, command_id)
        
        # Analyze status
        status_analysis = analyze_command_status(invocations, command_id)
        
        execution_time = time.time() - start_time
        
        result = {
            'statusCode': 200,
            'success': True,
            **status_analysis,
            'execution_time_ms': execution_time * 1000,
            'timestamp': time.time(),
            'account_id': account_id,
            'region': region,
            'execution_id': execution_id
        }
        
        logger.info(f"SSM polling completed in {execution_time:.2f}s")
        logger.info(f"Status: {status_analysis['status']}, All done: {status_analysis['all_done']}")
        logger.info(f"Progress: {status_analysis['completed_instances']}/{status_analysis['total_instances']} instances")
        
        # Log warnings for high failure rates
        if status_analysis['failure_rate'] > 20:
            logger.warning(f"High failure rate detected: {status_analysis['failure_rate']}%")
        
        return result
        
    except SSMPollingError as e:
        logger.error(f"SSM polling error: {str(e)}")
        execution_time = time.time() - start_time
        
        return {
            'statusCode': 400,
            'success': False,
            'error': str(e),
            'error_type': 'SSMPollingError',
            'all_done': False,
            'should_continue_polling': False,
            'execution_time_ms': execution_time * 1000,
            'timestamp': time.time()
        }
    
    except Exception as e:
        logger.error(f"Unexpected error in SSM polling handler: {str(e)}")
        execution_time = time.time() - start_time
        
        return {
            'statusCode': 500,
            'success': False,
            'error': f"Unexpected error: {str(e)}",
            'error_type': 'UnexpectedError',
            'all_done': False,
            'should_continue_polling': False,
            'execution_time_ms': execution_time * 1000,
            'timestamp': time.time()
        }
