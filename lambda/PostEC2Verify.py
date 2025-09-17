import os
import json
import boto3
import uuid
import time
import logging
from datetime import datetime, timedelta
from typing import Dict, Any, Optional, List, Tuple
from botocore.exceptions import ClientError, BotoCoreError
from functools import wraps

# Configure structured logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - [%(correlation_id)s] - %(message)s'
)
logger = logging.getLogger(__name__)

# Constants for CloudWatch custom metrics
METRICS_NAMESPACE = os.environ.get("METRICS_NAMESPACE", "EC2Patching/Orchestrator")
NAME_PREFIX = os.environ.get("NAME_PREFIX", "ec2-patch")
ENVIRONMENT = os.environ.get("ENVIRONMENT", "dev")

class PostVerificationError(Exception):
    """Custom exception for post-patching verification operations"""
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
                    
                    if error_code in ['ValidationException', 'AccessDenied', 'InvalidInstanceId']:
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
    
    # Get accounts from event
    accounts = event.get('accounts', [])
    if not accounts or not isinstance(accounts, list):
        raise PostVerificationError("Missing or invalid accounts list")
    
    # Validate account IDs format
    for account in accounts:
        if not isinstance(account, str) or not account.isdigit() or len(account) != 12:
            raise PostVerificationError(f"Invalid account ID format: {account}")
    
    # Get regions with fallback
    regions = event.get('regions', [os.environ.get('AWS_REGION', 'us-east-1')])
    if not isinstance(regions, list):
        regions = [regions]
    
    # Validate required environment variables
    bucket_name = os.environ.get('S3_BUCKET')
    if not bucket_name:
        raise PostVerificationError("S3_BUCKET environment variable not set")
    
    ddb_table = os.environ.get('DDB_TABLE')
    if not ddb_table:
        raise PostVerificationError("DDB_TABLE environment variable not set")
    
    execution_id = event.get('executionId', f'exec-{int(time.time())}')
    
    return {
        'accounts': accounts,
        'regions': regions,
        'bucket_name': bucket_name,
        'ddb_table': ddb_table,
        'execution_id': execution_id
    }

def assume_cross_account_role(account_id: str, role_name: str = 'PatchExecRole') -> Dict[str, str]:
    """Assume cross-account role with comprehensive error handling"""
    
    role_arn = f"arn:aws:iam::{account_id}:role/{role_name}"
    session_name = f'PostEC2Verify-{int(time.time())}'
    
    try:
        sts_client = boto3.client('sts')
        
        logger.info(f"Assuming role {role_arn}")
        
        response = sts_client.assume_role(
            RoleArn=role_arn,
            RoleSessionName=session_name,
            DurationSeconds=3600  # 1 hour
        )
        
        credentials = response['Credentials']
        
        logger.info(f"Successfully assumed role for account {account_id}")
        
        return {
            'AccessKeyId': credentials['AccessKeyId'],
            'SecretAccessKey': credentials['SecretAccessKey'],
            'SessionToken': credentials['SessionToken'],
            'Expiration': credentials['Expiration'].isoformat()
        }
        
    except ClientError as e:
        error_code = e.response.get('Error', {}).get('Code', 'Unknown')
        error_message = e.response.get('Error', {}).get('Message', str(e))
        
        logger.error(f"Failed to assume role {role_arn}: {error_code} - {error_message}")
        
        if error_code == 'AccessDenied':
            raise PostVerificationError(f"Access denied assuming role in account {account_id}: {error_message}")
        elif error_code == 'InvalidUserType':
            raise PostVerificationError(f"Invalid user type for role assumption: {error_message}")
        else:
            raise PostVerificationError(f"Role assumption failed [{error_code}]: {error_message}")

@retry_with_backoff(max_retries=3, base_delay=2.0)
def get_patch_states(credentials: Dict[str, str], region: str) -> List[Dict[str, Any]]:
    """Get patch states for all instances in region with comprehensive error handling"""
    
    try:
        ssm_client = boto3.client(
            'ssm',
            region_name=region,
            aws_access_key_id=credentials['AccessKeyId'],
            aws_secret_access_key=credentials['SecretAccessKey'],
            aws_session_token=credentials['SessionToken']
        )
        
        logger.info(f"Retrieving patch states for region {region}")
        
        paginator = ssm_client.get_paginator('describe_instance_patch_states')
        all_states = []
        
        # Get all patch states
        page_count = 0
        for page in paginator.paginate():
            page_count += 1
            states = page.get('InstancePatchStates', [])
            all_states.extend(states)
            
            logger.debug(f"Retrieved page {page_count} with {len(states)} patch states")
        
        logger.info(f"Retrieved {len(all_states)} patch states from region {region}")
        
        return all_states
        
    except ClientError as e:
        error_code = e.response.get('Error', {}).get('Code', 'Unknown')
        error_message = e.response.get('Error', {}).get('Message', str(e))
        
        logger.error(f"Failed to get patch states: {error_code} - {error_message}")
        
        if error_code == 'AccessDenied':
            raise PostVerificationError(f"Access denied to SSM in region {region}: {error_message}")
        elif error_code in ['InvalidFilterValue', 'InvalidNextToken']:
            raise PostVerificationError(f"Invalid request parameters: {error_message}")
        else:
            raise PostVerificationError(f"SSM describe_instance_patch_states failed [{error_code}]: {error_message}")

def analyze_patch_states(patch_states: List[Dict[str, Any]]) -> Dict[str, Any]:
    """Analyze patch states to identify issues and generate comprehensive stats"""
    
    if not patch_states:
        return {
            'total_instances': 0,
            'healthy_instances': 0,
            'problematic_instances': 0,
            'issues_found': [],
            'success_rate': 0.0,
            'analysis': 'No instances found'
        }
    
    total_instances = len(patch_states)
    issues_found = []
    
    # Analyze each instance
    for state in patch_states:
        instance_id = state.get('InstanceId', 'unknown')
        missing_count = state.get('MissingCount', 0)
        failed_count = state.get('FailedCount', 0)
        not_applicable_count = state.get('NotApplicableCount', 0)
        installed_count = state.get('InstalledCount', 0)
        installed_other_count = state.get('InstalledOtherCount', 0)
        installed_pending_reboot_count = state.get('InstalledPendingRebootCount', 0)
        operation = state.get('Operation', 'Unknown')
        operation_start_time = state.get('OperationStartTime', 'Unknown')
        operation_end_time = state.get('OperationEndTime', 'Unknown')
        
        # Check for issues
        has_issues = missing_count > 0 or failed_count > 0
        
        if has_issues:
            issue_detail = {
                'instance_id': instance_id,
                'missing_count': missing_count,
                'failed_count': failed_count,
                'installed_count': installed_count,
                'installed_pending_reboot': installed_pending_reboot_count,
                'operation': operation,
                'operation_start': operation_start_time,
                'operation_end': operation_end_time,
                'severity': 'high' if failed_count > 0 else 'medium'
            }
            issues_found.append(issue_detail)
    
    healthy_instances = total_instances - len(issues_found)
    problematic_instances = len(issues_found)
    success_rate = (healthy_instances / total_instances) * 100 if total_instances > 0 else 0.0
    
    # Generate summary analysis
    if problematic_instances == 0:
        analysis = f"All {total_instances} instances patched successfully"
    else:
        high_severity = sum(1 for issue in issues_found if issue['severity'] == 'high')
        medium_severity = problematic_instances - high_severity
        
        analysis_parts = [f"{problematic_instances}/{total_instances} instances have issues"]
        if high_severity > 0:
            analysis_parts.append(f"{high_severity} with failed patches")
        if medium_severity > 0:
            analysis_parts.append(f"{medium_severity} with missing patches")
        
        analysis = "; ".join(analysis_parts)
    
    return {
        'total_instances': total_instances,
        'healthy_instances': healthy_instances,
        'problematic_instances': problematic_instances,
        'issues_found': issues_found,
        'success_rate': round(success_rate, 2),
        'analysis': analysis
    }

@retry_with_backoff(max_retries=3, base_delay=1.0)
def store_results_s3(bucket_name: str, s3_key: str, data: Dict[str, Any]) -> str:
    """Store verification results in S3 with comprehensive error handling"""
    
    try:
        s3_client = boto3.client('s3')
        
        # Convert data to JSON string with proper formatting
        json_data = json.dumps(data, indent=2, default=str, sort_keys=True)
        
        logger.info(f"Storing results to S3: s3://{bucket_name}/{s3_key}")
        
        s3_client.put_object(
            Bucket=bucket_name,
            Key=s3_key,
            Body=json_data.encode('utf-8'),
            ContentType='application/json',
            ServerSideEncryption='AES256',
            Metadata={
                'verification-type': 'post-patching',
                'timestamp': str(int(time.time())),
                'instance-count': str(len(data.get('patch_states', [])))
            }
        )
        
        s3_url = f"s3://{bucket_name}/{s3_key}"
        logger.info(f"Successfully stored results: {s3_url}")
        
        return s3_url
        
    except ClientError as e:
        error_code = e.response.get('Error', {}).get('Code', 'Unknown')
        error_message = e.response.get('Error', {}).get('Message', str(e))
        
        logger.error(f"Failed to store results to S3: {error_code} - {error_message}")
        
        if error_code == 'NoSuchBucket':
            raise PostVerificationError(f"S3 bucket does not exist: {bucket_name}")
        elif error_code == 'AccessDenied':
            raise PostVerificationError(f"Access denied to S3 bucket: {bucket_name}")
        else:
            raise PostVerificationError(f"S3 storage failed [{error_code}]: {error_message}")

@retry_with_backoff(max_retries=3, base_delay=1.0)
def store_results_dynamodb(ddb_table: str, record: Dict[str, Any]) -> None:
    """Store verification summary in DynamoDB with comprehensive error handling"""
    
    try:
        dynamodb = boto3.resource('dynamodb')
        table = dynamodb.Table(ddb_table)
        
        logger.info(f"Storing summary to DynamoDB: {record['id']}")
        
        # Add timestamps
        record['created_at'] = int(time.time())
        record['ttl'] = int(time.time()) + (90 * 24 * 3600)  # 90 days TTL
        
        table.put_item(Item=record)
        
        logger.info(f"Successfully stored DynamoDB record: {record['id']}")
        
    except ClientError as e:
        error_code = e.response.get('Error', {}).get('Code', 'Unknown')
        error_message = e.response.get('Error', {}).get('Message', str(e))
        
        logger.error(f"Failed to store to DynamoDB: {error_code} - {error_message}")
        
        if error_code == 'ResourceNotFoundException':
            raise PostVerificationError(f"DynamoDB table not found: {ddb_table}")
        elif error_code == 'ValidationException':
            raise PostVerificationError(f"Invalid DynamoDB record format: {error_message}")
        else:
            raise PostVerificationError(f"DynamoDB storage failed [{error_code}]: {error_message}")

def process_account_region(
    account: str,
    region: str,
    bucket_name: str,
    ddb_table: str,
    execution_id: str
) -> Dict[str, Any]:
    """Process verification for a single account-region combination"""
    
    logger.info(f"Processing verification for account {account} in region {region}")
    
    try:
        # Assume role in target account
        credentials = assume_cross_account_role(account)
        
        # Get patch states
        patch_states = get_patch_states(credentials, region)
        
        # Analyze results
        analysis = analyze_patch_states(patch_states)
        
        # Generate S3 key
        today = datetime.utcnow().strftime('%Y/%m/%d')
        s3_key = f"{today}/{account}/{region}/post_ec2_patchstates.json"
        
        # Prepare data for storage
        storage_data = {
            'execution_id': execution_id,
            'account_id': account,
            'region': region,
            'timestamp': datetime.utcnow().isoformat(),
            'patch_states': patch_states,
            'analysis': analysis
        }
        
        # Store results in S3
        s3_url = store_results_s3(bucket_name, s3_key, storage_data)
        
        # Prepare DynamoDB record
        ddb_record = {
            'scope': 'EC2#POST',
            'id': f'{account}:{region}:{today}',
            'execution_id': execution_id,
            's3key': s3_key,
            's3_url': s3_url,
            'total_instances': analysis['total_instances'],
            'problematic_instances': analysis['problematic_instances'],
            'success_rate': analysis['success_rate'],
            'analysis': analysis['analysis']
        }
        
        # Store summary in DynamoDB
        store_results_dynamodb(ddb_table, ddb_record)
        
        # Emit per-region custom metrics
        try:
            cw = boto3.client("cloudwatch")
            dims = [
                {"Name": "NamePrefix", "Value": NAME_PREFIX},
                {"Name": "Environment", "Value": ENVIRONMENT},
                {"Name": "AccountId", "Value": account},
                {"Name": "Region", "Value": region},
            ]
            metrics = [
                {
                    "MetricName": "SuccessRate",
                    "Dimensions": dims,
                    "Unit": "Percent",
                    "Value": float(analysis['success_rate'])
                },
                {
                    "MetricName": "InstancesTotal",
                    "Dimensions": dims,
                    "Unit": "Count",
                    "Value": float(analysis['total_instances'])
                },
                {
                    "MetricName": "InstancesWithIssues",
                    "Dimensions": dims,
                    "Unit": "Count",
                    "Value": float(analysis['problematic_instances'])
                }
            ]
            cw.put_metric_data(Namespace=METRICS_NAMESPACE, MetricData=metrics)
        except Exception as me:
            logger.warning(f"Failed to publish metrics to CloudWatch for {account}:{region}: {me}")

        result = {
            'account': account,
            'region': region,
            'success': True,
            'analysis': analysis,
            's3_key': s3_key,
            's3_url': s3_url
        }
        
        # Add issue details if problems found
        if analysis['problematic_instances'] > 0:
            result['issues'] = {
                'count': analysis['problematic_instances'],
                'details': analysis['issues_found'][:10]  # Limit details for response size
            }
        
        logger.info(f"Completed verification for {account}:{region} - {analysis['analysis']}")
        
        return result
        
    except Exception as e:
        logger.error(f"Failed to process {account}:{region}: {str(e)}")
        
        return {
            'account': account,
            'region': region,
            'success': False,
            'error': str(e),
            'error_type': type(e).__name__
        }

@with_correlation_id
def handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """
    Enhanced post-patching verification handler with comprehensive analysis
    """
    start_time = time.time()
    
    try:
        logger.info(f"Starting post-patching verification with event keys: {list(event.keys())}")
        
        # Validate input
        validated_data = validate_input(event)
        
        accounts = validated_data['accounts']
        regions = validated_data['regions']
        bucket_name = validated_data['bucket_name']
        ddb_table = validated_data['ddb_table']
        execution_id = validated_data['execution_id']
        
        logger.info(f"Processing {len(accounts)} accounts across {len(regions)} regions")
        
        results = []
        overall_issues = []
        total_instances = 0
        total_problematic = 0
        
        # Process each account-region combination
        for account in accounts:
            for region in regions:
                result = process_account_region(
                    account, region, bucket_name, ddb_table, execution_id
                )
                
                results.append(result)
                
                if result['success']:
                    analysis = result['analysis']
                    total_instances += analysis['total_instances']
                    total_problematic += analysis['problematic_instances']
                    
                    # Collect issues for overall summary
                    if analysis['problematic_instances'] > 0:
                        overall_issues.append({
                            'account': account,
                            'region': region,
                            'count': analysis['problematic_instances'],
                            's3_key': result['s3_key']
                        })
        
        # Calculate overall statistics
        successful_processes = sum(1 for r in results if r['success'])
        failed_processes = len(results) - successful_processes
        overall_success_rate = (total_instances - total_problematic) / total_instances * 100 if total_instances > 0 else 100.0
        
        execution_time = time.time() - start_time
        
        final_result = {
            'statusCode': 200,
            'hasIssues': len(overall_issues) > 0,
            'issues': overall_issues,
            'summary': {
                'total_processes': len(results),
                'successful_processes': successful_processes,
                'failed_processes': failed_processes,
                'total_instances': total_instances,
                'problematic_instances': total_problematic,
                'overall_success_rate': round(overall_success_rate, 2)
            },
            'results': results,
            'execution_id': execution_id,
            'execution_time_ms': round(execution_time * 1000, 2),
            'timestamp': time.time()
        }
        
        logger.info(f"Post-verification completed in {execution_time:.2f}s")
        logger.info(f"Overall: {total_instances} instances, {total_problematic} with issues ({overall_success_rate:.1f}% success)")
        
        return final_result
        
    except PostVerificationError as e:
        logger.error(f"Post-verification error: {str(e)}")
        execution_time = time.time() - start_time
        
        return {
            'statusCode': 400,
            'hasIssues': True,
            'error': str(e),
            'error_type': 'PostVerificationError',
            'execution_time_ms': round(execution_time * 1000, 2),
            'timestamp': time.time()
        }
    
    except Exception as e:
        logger.error(f"Unexpected error in post-verification handler: {str(e)}")
        execution_time = time.time() - start_time
        
        return {
            'statusCode': 500,
            'hasIssues': True,
            'error': f"Unexpected error: {str(e)}",
            'error_type': 'UnexpectedError',
            'execution_time_ms': round(execution_time * 1000, 2),
            'timestamp': time.time()
        }
