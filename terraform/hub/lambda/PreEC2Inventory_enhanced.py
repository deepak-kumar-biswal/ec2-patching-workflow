import os
import json
import boto3
import datetime
import logging
from typing import Dict, List, Any
from botocore.exceptions import ClientError, BotoCoreError
import time
from functools import wraps

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize clients
s3 = boto3.client('s3')
ddb = boto3.resource('dynamodb')
TABLE = ddb.Table(os.environ['DDB_TABLE'])
BUCKET = os.environ['S3_BUCKET']

def retry_with_backoff(max_retries: int = 3, base_delay: float = 1.0):
    """Decorator for retry logic with exponential backoff"""
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            for attempt in range(max_retries):
                try:
                    return func(*args, **kwargs)
                except (ClientError, BotoCoreError) as e:
                    if attempt == max_retries - 1:
                        logger.error(f"Final retry failed for {func.__name__}: {str(e)}")
                        raise
                    delay = base_delay * (2 ** attempt)
                    logger.warning(f"Retry {attempt + 1}/{max_retries} for {func.__name__} after {delay}s: {str(e)}")
                    time.sleep(delay)
            return None
        return wrapper
    return decorator

class PatchingError(Exception):
    """Custom exception for patching operations"""
    pass

@retry_with_backoff(max_retries=3)
def assume_role(role_arn: str) -> Dict[str, str]:
    """Assume cross-account role with retry logic"""
    try:
        sts = boto3.client('sts')
        response = sts.assume_role(
            RoleArn=role_arn, 
            RoleSessionName=f'preinv-{int(time.time())}',
            DurationSeconds=3600  # 1 hour
        )
        return response['Credentials']
    except ClientError as e:
        error_code = e.response.get('Error', {}).get('Code', 'Unknown')
        logger.error(f"Failed to assume role {role_arn}: {error_code} - {str(e)}")
        raise PatchingError(f"Role assumption failed: {error_code}")

@retry_with_backoff(max_retries=3)
def get_ssm_client(creds: Dict[str, str], region: str):
    """Create SSM client with credentials"""
    try:
        return boto3.client(
            'ssm',
            region_name=region,
            aws_access_key_id=creds['AccessKeyId'],
            aws_secret_access_key=creds['SecretAccessKey'],
            aws_session_token=creds['SessionToken']
        )
    except Exception as e:
        logger.error(f"Failed to create SSM client for region {region}: {str(e)}")
        raise PatchingError(f"SSM client creation failed: {str(e)}")

@retry_with_backoff(max_retries=3)
def get_instance_information(ssm_client, account: str, region: str) -> List[Dict]:
    """Get instance information with pagination and error handling"""
    try:
        instances = []
        paginator = ssm_client.get_paginator('describe_instance_information')
        
        for page in paginator.paginate():
            instances.extend(page.get('InstanceInformationList', []))
            
        logger.info(f"Retrieved {len(instances)} instances for {account}:{region}")
        return instances
    except ClientError as e:
        error_code = e.response.get('Error', {}).get('Code', 'Unknown')
        logger.error(f"Failed to get instance info for {account}:{region}: {error_code}")
        raise PatchingError(f"Instance information retrieval failed: {error_code}")

@retry_with_backoff(max_retries=3)
def store_inventory_data(inventory: Dict, key: str, account: str, region: str, today: str, count: int):
    """Store inventory data to S3 and DynamoDB with error handling"""
    try:
        # Store in S3
        s3.put_object(
            Bucket=BUCKET,
            Key=key,
            Body=json.dumps(inventory, indent=2, default=str).encode('utf-8'),
            ContentType='application/json',
            Metadata={
                'account': account,
                'region': region,
                'date': today,
                'instance_count': str(count)
            }
        )
        
        # Store metadata in DynamoDB
        TABLE.put_item(
            Item={
                'scope': 'EC2#PRE',
                'id': f'{account}:{region}:{today}',
                's3key': key,
                'count': count,
                'timestamp': datetime.datetime.utcnow().isoformat(),
                'status': 'completed'
            }
        )
        
        logger.info(f"Stored inventory data: {key} ({count} instances)")
        
    except ClientError as e:
        error_code = e.response.get('Error', {}).get('Code', 'Unknown')
        logger.error(f"Failed to store inventory data: {error_code}")
        raise PatchingError(f"Data storage failed: {error_code}")

def handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """Enhanced main handler with comprehensive error handling"""
    try:
        logger.info(f"Starting pre-inventory with event: {json.dumps(event, default=str)}")
        
        today = datetime.datetime.utcnow().strftime('%Y/%m/%d')
        accounts = event.get('accounts', [])
        regions = event.get('regions', [os.environ.get('AWS_REGION', 'us-east-1')])
        
        if not accounts:
            raise PatchingError("No accounts specified in event")
        
        results = {
            'success': [],
            'failures': [],
            'summary': {
                'total_accounts': len(accounts),
                'total_regions': len(regions),
                'processed': 0,
                'failed': 0
            }
        }
        
        for account in accounts:
            for region in regions:
                try:
                    logger.info(f"Processing {account}:{region}")
                    
                    # Assume role
                    role_arn = f"arn:aws:iam::{account}:role/PatchExecRole"
                    creds = assume_role(role_arn)
                    
                    # Get SSM client
                    ssm_client = get_ssm_client(creds, region)
                    
                    # Get instance information
                    instances = get_instance_information(ssm_client, account, region)
                    
                    # Create inventory structure
                    inventory = {
                        instance['InstanceId']: {'Instance': instance}
                        for instance in instances
                    }
                    
                    # Store data
                    key = f"{today}/{account}/{region}/pre_ec2.json"
                    store_inventory_data(inventory, key, account, region, today, len(instances))
                    
                    results['success'].append({
                        'account': account,
                        'region': region,
                        'instance_count': len(instances),
                        's3_key': key
                    })
                    results['summary']['processed'] += 1
                    
                except PatchingError as e:
                    error_info = {
                        'account': account,
                        'region': region,
                        'error': str(e),
                        'timestamp': datetime.datetime.utcnow().isoformat()
                    }
                    results['failures'].append(error_info)
                    results['summary']['failed'] += 1
                    logger.error(f"Failed to process {account}:{region}: {str(e)}")
                
                except Exception as e:
                    error_info = {
                        'account': account,
                        'region': region,
                        'error': f"Unexpected error: {str(e)}",
                        'timestamp': datetime.datetime.utcnow().isoformat()
                    }
                    results['failures'].append(error_info)
                    results['summary']['failed'] += 1
                    logger.error(f"Unexpected error for {account}:{region}: {str(e)}")
        
        # Determine overall success
        success = results['summary']['failed'] == 0
        
        logger.info(f"Pre-inventory completed: {results['summary']}")
        
        return {
            'statusCode': 200 if success else 206,  # 206 = Partial Content
            'success': success,
            'results': results,
            'timestamp': datetime.datetime.utcnow().isoformat()
        }
        
    except Exception as e:
        logger.error(f"Handler failed with unexpected error: {str(e)}")
        return {
            'statusCode': 500,
            'success': False,
            'error': str(e),
            'timestamp': datetime.datetime.utcnow().isoformat()
        }
