"""
EC2 Pre-Inventory Lambda Function - Production Grade
Enhanced pre-patching inventory collection for EC2 instances across multiple accounts and regions.
Includes comprehensive error handling, retry logic, structured logging, and monitoring capabilities.
"""

import os
import json
import boto3
import datetime
import logging
import time
import uuid
from typing import Dict, List, Any
from functools import wraps
from botocore.exceptions import ClientError, BotoCoreError

# Configure structured logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(funcName)s:%(lineno)d - %(message)s'
)
logger = logging.getLogger(__name__)

# Global clients with retry configuration
s3_client = boto3.client(
    's3',
    config=boto3.session.Config(
        retries={'max_attempts': 3, 'mode': 'adaptive'},
        read_timeout=60
    )
)
dynamodb = boto3.resource(
    'dynamodb',
    config=boto3.session.Config(
        retries={'max_attempts': 3, 'mode': 'adaptive'}
    )
)

class PatchingError(Exception):
    """Custom exception for EC2 patching operations"""
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
                    
                    if error_code in ['ValidationException', 'AccessDenied', 'ResourceNotFound']:
                        logger.error(f"Non-retryable error: {error_code}")
                        raise
                    
                    delay = base_delay * (2 ** attempt)
                    logger.warning(f"Retry {attempt + 1}/{max_retries} for {func.__name__} after {delay}s: {error_code}")
                    time.sleep(delay)
            return None
        return wrapper
    return decorator

def validate_input(event: Dict[str, Any]) -> Dict[str, Any]:
    """Validate and normalize input event with comprehensive checks"""
    try:
        if not isinstance(event, dict):
            raise PatchingError("Event must be a dictionary")
        
        # Extract and validate accounts
        accounts = event.get('accounts', [])
        if not accounts:
            raise PatchingError("No accounts specified in event")
        
        if not isinstance(accounts, list):
            accounts = [accounts]
        
        # Validate account format (12-digit AWS account IDs)
        for account in accounts:
            if not isinstance(account, str) or not account.isdigit() or len(account) != 12:
                raise PatchingError(f"Invalid account ID format: {account}")
        
        # Extract and validate regions
        regions = event.get('regions', [os.environ.get('AWS_REGION', 'us-east-1')])
        if not isinstance(regions, list):
            regions = [regions]
        
        # Validate region format
        for region in regions:
            if not isinstance(region, str) or len(region) < 8:
                raise PatchingError(f"Invalid region format: {region}")
        
        return {
            'accounts': accounts,
            'regions': regions,
            'today': datetime.datetime.utcnow().strftime('%Y/%m/%d'),
            'correlation_id': str(uuid.uuid4())[:8]
        }
        
    except Exception as e:
        logger.error(f"Input validation failed: {str(e)}")
        raise PatchingError(f"Input validation failed: {str(e)}")

@retry_with_backoff(max_retries=3, base_delay=2.0)
def assume_role(role_arn: str) -> Dict[str, str]:
    """Assume role with enhanced error handling and validation"""
    try:
        logger.info(f"Assuming role {role_arn}")
        
        sts_client = boto3.client('sts')
        
        response = sts_client.assume_role(
            RoleArn=role_arn,
            RoleSessionName='PreEC2Inventory',
            DurationSeconds=3600
        )
        
        credentials = response['Credentials']
        
        # Validate credentials
        if not all(key in credentials for key in ['AccessKeyId', 'SecretAccessKey', 'SessionToken']):
            raise PatchingError(f"Invalid credentials received for role {role_arn}")
        
        logger.info(f"Successfully assumed role {role_arn}")
        
        return {
            'aws_access_key_id': credentials['AccessKeyId'],
            'aws_secret_access_key': credentials['SecretAccessKey'],
            'aws_session_token': credentials['SessionToken']
        }
        
    except ClientError as e:
        error_code = e.response.get('Error', {}).get('Code', 'Unknown')
        error_message = e.response.get('Error', {}).get('Message', str(e))
        logger.error(f"Failed to assume role {role_arn}: {error_code} - {error_message}")
        raise

@retry_with_backoff(max_retries=2, base_delay=1.0)
def get_ssm_client(credentials: Dict[str, str], region: str):
    """Create SSM client with assumed role credentials"""
    try:
        return boto3.client(
            'ssm',
            region_name=region,
            aws_access_key_id=credentials['aws_access_key_id'],
            aws_secret_access_key=credentials['aws_secret_access_key'],
            aws_session_token=credentials['aws_session_token'],
            config=boto3.session.Config(
                retries={'max_attempts': 3, 'mode': 'adaptive'},
                read_timeout=120
            )
        )
    except Exception as e:
        logger.error(f"Failed to create SSM client for region {region}: {str(e)}")
        raise PatchingError(f"Failed to create SSM client for region {region}")

@retry_with_backoff(max_retries=2, base_delay=1.0)
def get_instance_information(ssm_client, account: str, region: str) -> List[Dict]:
    """Get EC2 instance information from Systems Manager with comprehensive error handling"""
    try:
        logger.info(f"Retrieving instance information for {account}:{region}")
        
        instances = []
        paginator = ssm_client.get_paginator('describe_instance_information')
        
        # Configure pagination with filters for better performance
        page_iterator = paginator.paginate(
            Filters=[
                {
                    'Key': 'PingStatus',
                    'Values': ['Online', 'ConnectionLost']
                }
            ],
            PaginationConfig={
                'PageSize': 50,
                'MaxItems': 10000
            }
        )
        
        page_count = 0
        for page in page_iterator:
            page_count += 1
            instance_list = page.get('InstanceInformationList', [])
            
            # Enrich instances with additional metadata
            for instance in instance_list:
                instance['discovered_at'] = datetime.datetime.utcnow().isoformat()
                instance['account_id'] = account
                instance['region'] = region
                
            instances.extend(instance_list)
            logger.debug(f"Page {page_count}: Found {len(instance_list)} instances")
            
            # Rate limiting to avoid throttling
            if page_count % 10 == 0:
                time.sleep(0.5)
        
        logger.info(f"Retrieved {len(instances)} instances from {account}:{region}")
        
        # Additional validation
        if len(instances) > 10000:
            logger.warning(f"Large number of instances ({len(instances)}) in {account}:{region} - may need optimization")
        
        return instances
        
    except ClientError as e:
        error_code = e.response.get('Error', {}).get('Code', 'Unknown')
        error_message = e.response.get('Error', {}).get('Message', str(e))
        
        if error_code == 'AccessDenied':
            logger.error(f"Access denied for SSM in {account}:{region} - check IAM permissions")
        elif error_code == 'RequestLimitExceeded':
            logger.warning(f"Request limit exceeded for {account}:{region} - implementing backoff")
            time.sleep(5)
            raise  # Retry will handle this
        else:
            logger.error(f"Failed to get instances for {account}:{region}: {error_code} - {error_message}")
        
        raise

@retry_with_backoff(max_retries=3, base_delay=1.0)
def store_inventory_data(inventory: Dict, s3_key: str, account: str, region: str, date: str, instance_count: int, correlation_id: str):
    """Store inventory data to S3 with comprehensive metadata and error handling"""
    try:
        bucket_name = os.environ['S3_BUCKET']
        logger.info(f"Storing {instance_count} instances to s3://{bucket_name}/{s3_key}")
        
        # Create enriched inventory with comprehensive metadata
        enriched_inventory = {
            'metadata': {
                'account': account,
                'region': region,
                'date': date,
                'instance_count': instance_count,
                'generated_at': datetime.datetime.utcnow().isoformat(),
                'version': '2.0',
                'correlation_id': correlation_id,
                'lambda_function': 'PreEC2Inventory',
                'data_classification': 'operational'
            },
            'summary': {
                'total_instances': instance_count,
                'platform_distribution': {},
                'ping_status_distribution': {}
            },
            'instances': inventory
        }
        
        # Calculate summary statistics
        platform_count = {}
        ping_status_count = {}
        
        for instance_id, instance_data in inventory.items():
            instance_info = instance_data.get('Instance', {})
            platform = instance_info.get('PlatformType', 'Unknown')
            ping_status = instance_info.get('PingStatus', 'Unknown')
            
            platform_count[platform] = platform_count.get(platform, 0) + 1
            ping_status_count[ping_status] = ping_status_count.get(ping_status, 0) + 1
        
        enriched_inventory['summary']['platform_distribution'] = platform_count
        enriched_inventory['summary']['ping_status_distribution'] = ping_status_count
        
        # Store to S3 with comprehensive metadata
        s3_client.put_object(
            Bucket=bucket_name,
            Key=s3_key,
            Body=json.dumps(enriched_inventory, indent=2, default=str),
            ContentType='application/json',
            ServerSideEncryption='AES256',
            Metadata={
                'account': account,
                'region': region,
                'instance-count': str(instance_count),
                'correlation-id': correlation_id,
                'generated-at': datetime.datetime.utcnow().isoformat()
            }
        )
        
        logger.info(f"Successfully stored inventory: s3://{bucket_name}/{s3_key}")
        
        return f"s3://{bucket_name}/{s3_key}"
        
    except ClientError as e:
        error_code = e.response.get('Error', {}).get('Code', 'Unknown')
        error_message = e.response.get('Error', {}).get('Message', str(e))
        
        if error_code == 'NoSuchBucket':
            logger.error(f"S3 bucket {bucket_name} does not exist")
        elif error_code == 'AccessDenied':
            logger.error(f"Access denied to S3 bucket {bucket_name}")
        else:
            logger.error(f"Failed to store inventory to S3: {error_code} - {error_message}")
        
        raise

@retry_with_backoff(max_retries=2, base_delay=0.5)
def update_dynamodb_state(table_name: str, account: str, region: str, status: str, instance_count: int, s3_key: str, correlation_id: str):
    """Update DynamoDB with execution state and comprehensive tracking"""
    try:
        table = dynamodb.Table(table_name)
        
        current_time = datetime.datetime.utcnow()
        
        item = {
            'PK': f"{account}#{region}",
            'SK': f"pre_inventory#{current_time.strftime('%Y-%m-%d')}",
            'GSI1PK': 'pre_inventory',
            'GSI1SK': current_time.isoformat(),
            'account': account,
            'region': region,
            'status': status,
            'instance_count': instance_count,
            's3_location': s3_key,
            'correlation_id': correlation_id,
            'function_name': 'PreEC2Inventory',
            'timestamp': current_time.isoformat(),
            'date': current_time.strftime('%Y-%m-%d'),
            'ttl': int(time.time()) + (90 * 24 * 60 * 60)  # 90 days TTL
        }
        
        table.put_item(Item=item)
        logger.debug(f"Updated DynamoDB state for {account}:{region}")
        
    except ClientError as e:
        error_code = e.response.get('Error', {}).get('Code', 'Unknown')
        error_message = e.response.get('Error', {}).get('Message', str(e))
        logger.warning(f"Failed to update DynamoDB state: {error_code} - {error_message}")
        # Don't raise - this is not critical for the main workflow

@with_correlation_id
def handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """
    Production-grade main handler for EC2 pre-inventory collection.
    
    Args:
        event: Lambda event containing accounts and regions to process
        context: Lambda context object
        
    Returns:
        Dictionary with execution results and comprehensive status information
    """
    start_time = time.time()
    
    # Log function start with context
    logger.info(f"Starting PreEC2Inventory function", extra={
        'function_name': context.function_name,
        'function_version': context.function_version,
        'aws_request_id': context.aws_request_id,
        'memory_limit': context.memory_limit_in_mb,
        'remaining_time': context.get_remaining_time_in_millis()
    })
    
    try:
        # Validate input
        validated_input = validate_input(event)
        accounts = validated_input['accounts']
        regions = validated_input['regions']
        today = validated_input['today']
        correlation_id = validated_input['correlation_id']
        
        logger.info(f"Processing {len(accounts)} accounts across {len(regions)} regions")
        
        results = {
            'success': [],
            'failures': [],
            'summary': {
                'total_accounts': len(accounts),
                'total_regions': len(regions),
                'total_combinations': len(accounts) * len(regions),
                'processed': 0,
                'failed': 0,
                'total_instances': 0,
                'execution_start': datetime.datetime.utcnow().isoformat(),
                'correlation_id': correlation_id
            },
            'metadata': {
                'function_name': context.function_name,
                'aws_request_id': context.aws_request_id,
                'version': '2.0'
            }
        }
        
        # Process each account and region combination
        for account in accounts:
            for region in regions:
                region_start_time = time.time()
                
                try:
                    logger.info(f"Processing {account}:{region}")
                    
                    # Assume role
                    role_arn = f"arn:aws:iam::{account}:role/PatchExecRole"
                    credentials = assume_role(role_arn)
                    
                    # Get SSM client
                    ssm_client = get_ssm_client(credentials, region)
                    
                    # Get instance information
                    instances = get_instance_information(ssm_client, account, region)
                    
                    # Create inventory structure
                    inventory = {
                        instance['InstanceId']: {'Instance': instance}
                        for instance in instances
                    }
                    
                    # Store data to S3
                    s3_key = f"{today}/{account}/{region}/pre_ec2.json"
                    s3_url = store_inventory_data(inventory, s3_key, account, region, today, len(instances), correlation_id)
                    
                    # Update DynamoDB state
                    table_name = os.environ.get('DDB_TABLE')
                    if table_name:
                        update_dynamodb_state(table_name, account, region, 'completed', len(instances), s3_key, correlation_id)
                    
                    # Calculate processing time
                    processing_time = time.time() - region_start_time
                    
                    # Track success
                    success_record = {
                        'account': account,
                        'region': region,
                        'instance_count': len(instances),
                        's3_key': s3_key,
                        's3_url': s3_url,
                        'status': 'completed',
                        'processing_time_seconds': round(processing_time, 2),
                        'timestamp': datetime.datetime.utcnow().isoformat()
                    }
                    
                    results['success'].append(success_record)
                    results['summary']['processed'] += 1
                    results['summary']['total_instances'] += len(instances)
                    
                    logger.info(f"Successfully processed {account}:{region} - {len(instances)} instances in {processing_time:.2f}s")
                    
                except PatchingError as e:
                    processing_time = time.time() - region_start_time
                    error_info = {
                        'account': account,
                        'region': region,
                        'error': str(e),
                        'error_type': 'PatchingError',
                        'timestamp': datetime.datetime.utcnow().isoformat(),
                        'processing_time_seconds': round(processing_time, 2),
                        'correlation_id': correlation_id
                    }
                    results['failures'].append(error_info)
                    results['summary']['failed'] += 1
                    logger.error(f"Patching error for {account}:{region}: {str(e)}")
                
                except Exception as e:
                    processing_time = time.time() - region_start_time
                    error_info = {
                        'account': account,
                        'region': region,
                        'error': f"Unexpected error: {str(e)}",
                        'error_type': 'UnexpectedError',
                        'timestamp': datetime.datetime.utcnow().isoformat(),
                        'processing_time_seconds': round(processing_time, 2),
                        'correlation_id': correlation_id
                    }
                    results['failures'].append(error_info)
                    results['summary']['failed'] += 1
                    logger.error(f"Unexpected error for {account}:{region}: {str(e)}", exc_info=True)
        
        # Calculate final execution metrics
        execution_time = time.time() - start_time
        results['execution_time_seconds'] = round(execution_time, 2)
        results['timestamp'] = datetime.datetime.utcnow().isoformat()
        results['summary']['execution_end'] = datetime.datetime.utcnow().isoformat()
        
        # Determine overall status and create response
        if results['summary']['failed'] == 0:
            status_code = 200
            results['success'] = True
            logger.info(f"PreEC2Inventory completed successfully in {execution_time:.2f}s")
            logger.info(f"Processed {results['summary']['processed']} account-region combinations")
            logger.info(f"Total instances discovered: {results['summary']['total_instances']}")
        elif results['summary']['processed'] > 0:
            status_code = 206  # Partial content
            results['success'] = False
            logger.warning(f"PreEC2Inventory partially completed in {execution_time:.2f}s")
            logger.warning(f"Successes: {results['summary']['processed']}, Failures: {results['summary']['failed']}")
        else:
            status_code = 500
            results['success'] = False
            logger.error(f"PreEC2Inventory failed completely in {execution_time:.2f}s")
        
        return {
            'statusCode': status_code,
            'results': results,
            'success': results['success']
        }
        
    except Exception as e:
        execution_time = time.time() - start_time
        error_msg = f"PreEC2Inventory handler failed: {str(e)}"
        logger.error(error_msg, exc_info=True)
        
        return {
            'statusCode': 500,
            'results': {
                'success': [],
                'failures': [{
                    'error': error_msg,
                    'error_type': 'HandlerError',
                    'timestamp': datetime.datetime.utcnow().isoformat(),
                    'execution_time_seconds': round(execution_time, 2),
                    'aws_request_id': context.aws_request_id if context else 'unknown'
                }],
                'summary': {
                    'total_accounts': 0,
                    'total_regions': 0,
                    'total_combinations': 0,
                    'processed': 0,
                    'failed': 1,
                    'total_instances': 0
                },
                'metadata': {
                    'function_name': context.function_name if context else 'unknown',
                    'aws_request_id': context.aws_request_id if context else 'unknown',
                    'version': '2.0'
                }
            },
            'success': False,
            'error': error_msg
        }
