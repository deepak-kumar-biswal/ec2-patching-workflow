# Copied and updated with HMAC signing; Slack sends via urllib
import os
import json
import boto3
import uuid
import time
import logging
import urllib.parse
import hmac
import hashlib
from typing import Dict, Any, Optional, List
from botocore.exceptions import ClientError, BotoCoreError
from functools import wraps
from datetime import datetime, timedelta
import urllib.request

# Configure structured logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - [%(correlation_id)s] - %(message)s'
)
logger = logging.getLogger(__name__)

class ApprovalRequestError(Exception):
    pass

def with_correlation_id(func):
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
                    if error_code in ['ValidationException', 'SubscriptionRequiredException']:
                        logger.error(f"Non-retryable error: {error_code}")
                        raise
                    delay = base_delay * (2 ** attempt)
                    logger.warning(f"Retry {attempt + 1}/{max_retries} for {func.__name__} after {delay}s: {error_code}")
                    time.sleep(delay)
            return None
        return wrapper
    return decorator

def validate_input(event: Dict[str, Any]) -> Dict[str, Any]:
    if 'taskToken' not in event:
        raise ApprovalRequestError("Missing required field: taskToken")
    task_token = event['taskToken']
    if not task_token or not isinstance(task_token, str):
        raise ApprovalRequestError("Invalid task token")
    topic_arn = os.environ.get('TOPIC_ARN')
    if not topic_arn:
        raise ApprovalRequestError("TOPIC_ARN environment variable not set")
    apigw_base = os.environ.get('APIGW_BASE')
    if not apigw_base:
        raise ApprovalRequestError("APIGW_BASE environment variable not set")
    subject = event.get('subject', 'EC2 Patching Approval Required')
    details = event.get('details', {})
    execution_id = event.get('executionId', 'unknown')
    estimated_duration = event.get('estimatedDuration', 'unknown')
    return {
        'task_token': task_token,
        'subject': subject,
        'details': details,
        'topic_arn': topic_arn,
        'apigw_base': apigw_base,
        'execution_id': execution_id,
        'estimated_duration': estimated_duration
    }

def _get_signing_secret() -> Optional[str]:
    secret_arn = os.environ.get('APPROVAL_SIGNING_SECRET_ARN')
    if not secret_arn:
        return None
    try:
        sm = boto3.client('secretsmanager')
        resp = sm.get_secret_value(SecretId=secret_arn)
        val = resp.get('SecretString')
        if not val and 'SecretBinary' in resp:
            val = resp['SecretBinary'].decode('utf-8')
        try:
            parsed = json.loads(val)
            val = parsed.get('secret') or parsed.get('value') or val
        except Exception:
            pass
        return val
    except Exception as e:
        logger.warning(f"Failed to retrieve signing secret: {str(e)}")
        return None

def _build_canonical_string(token: str, timestamp: int, action: str, execution_id: str) -> str:
    return f"{token}:{timestamp}:{action}:{execution_id}"

def _sign(canonical: str, secret: str) -> str:
    return hmac.new(secret.encode('utf-8'), canonical.encode('utf-8'), hashlib.sha256).hexdigest()

def create_approval_links(apigw_base: str, task_token: str, execution_id: str) -> Dict[str, str]:
    encoded_token = urllib.parse.quote(task_token, safe='')
    timestamp = int(time.time())
    secret = _get_signing_secret()
    base = f"{apigw_base}/callback"
    def build(action: str) -> str:
        if secret:
            canonical = _build_canonical_string(task_token, timestamp, action, execution_id)
            sig = _sign(canonical, secret)
            return (
                f"{base}?action={action}&token={encoded_token}&executionId={execution_id}"
                f"&timestamp={timestamp}&sig={sig}"
            )
        else:
            return f"{base}?action={action}&token={encoded_token}&executionId={execution_id}&timestamp={timestamp}"
    return {'approve_url': build('approve'), 'reject_url': build('reject')}

def format_details_for_notification(details: Dict[str, Any]) -> str:
    if not details:
        return "No additional details provided."
    formatted_parts = []
    if 'accountWaves' in details:
        account_waves = details['accountWaves']
        if isinstance(account_waves, list) and len(account_waves) > 0:
            total_accounts = sum(len(wave.get('accounts', [])) for wave in account_waves)
            total_regions = len(set(region for wave in account_waves for region in wave.get('regions', [])))
            formatted_parts.append(f"Execution Scope:")
            formatted_parts.append(f"   • Accounts: {total_accounts}")
            formatted_parts.append(f"   • Regions: {total_regions}")
            formatted_parts.append(f"   • Waves: {len(account_waves)}")
            for i, wave in enumerate(account_waves, 1):
                accounts = wave.get('accounts', [])
                regions = wave.get('regions', [])
                formatted_parts.append(f"   • Wave {i}: {len(accounts)} accounts across {regions}")
    if 'ec2' in details:
        ec2_config = details['ec2']
        if isinstance(ec2_config, dict):
            tag_key = ec2_config.get('tagKey', 'Unknown')
            tag_value = ec2_config.get('tagValue', 'Unknown')
            formatted_parts.append(f"Target Filter: {tag_key}={tag_value}")
    if 'abortOnIssues' in details:
        abort_setting = "Yes" if details['abortOnIssues'] else "No"
        formatted_parts.append(f"Abort on Issues: {abort_setting}")
    if 'wavePauseSeconds' in details:
        pause_minutes = details['wavePauseSeconds'] // 60
        formatted_parts.append(f"Wave Pause: {pause_minutes} minutes")
    return "\n".join(formatted_parts) if formatted_parts else json.dumps(details, indent=2, default=str)

def create_notification_message(subject: str, details: Dict[str, Any], approve_url: str, reject_url: str, execution_id: str, estimated_duration: Any, task_token_hash: str) -> Dict[str, str]:
    current_time = datetime.now().strftime("%Y-%m-%d %H:%M:%S UTC")
    duration_text = f"{estimated_duration} minutes" if isinstance(estimated_duration, (int, float)) else str(estimated_duration)
    message_body = f"""
APPROVAL REQUIRED: EC2 Patching Operation

Execution Information:
• Execution ID: {execution_id}
• Request Time: {current_time}
• Estimated Duration: {duration_text}
• Request ID: {task_token_hash}

Operation Details:
{format_details_for_notification(details)}

ACTIONS REQUIRED:
APPROVE: {approve_url}
REJECT:  {reject_url}

Notes:
• Approval will expire after 1 hour
• All operations are logged and audited
"""
    return {'subject': subject, 'body': message_body.strip()}

@retry_with_backoff(max_retries=3, base_delay=1.0)
def send_sns_notification(topic_arn: str, subject: str, message: str, execution_id: str) -> str:
    sns_client = boto3.client('sns')
    logger.info(f"Sending SNS notification for execution {execution_id}")
    message_attributes = {
        'NotificationType': {'DataType': 'String', 'StringValue': 'ApprovalRequest'},
        'ExecutionId': {'DataType': 'String', 'StringValue': execution_id},
        'Priority': {'DataType': 'String', 'StringValue': 'High'},
        'Timestamp': {'DataType': 'Number', 'StringValue': str(int(time.time()))}
    }
    response = sns_client.publish(TopicArn=topic_arn, Subject=subject, Message=message, MessageAttributes=message_attributes)
    message_id = response.get('MessageId', 'unknown')
    logger.info(f"SNS notification sent successfully: {message_id}")
    return message_id

def send_slack_notification(webhook_url: str, message_data: Dict[str, str], execution_id: str) -> bool:
    if not webhook_url:
        return False
    try:
        payload = {
            "text": "EC2 Patching Approval Required",
            "attachments": [
                {
                    "color": "warning",
                    "title": message_data['subject'],
                    "text": message_data['body'][:1000] + "..." if len(message_data['body']) > 1000 else message_data['body'],
                    "footer": f"Execution ID: {execution_id}",
                }
            ]
        }
        data = json.dumps(payload).encode('utf-8')
        req = urllib.request.Request(webhook_url, data=data, headers={'Content-Type': 'application/json'})
        with urllib.request.urlopen(req, timeout=10) as resp:  # nosec B310
            if 200 <= resp.getcode() < 300:
                logger.info(f"Slack notification sent for execution {execution_id}")
                return True
            logger.warning(f"Slack webhook returned status: {resp.getcode()}")
            return False
    except Exception as e:
        logger.warning(f"Failed to send Slack notification: {str(e)}")
        return False

@with_correlation_id
def handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    start_time = time.time()
    try:
        logger.info(f"Processing approval request with event keys: {list(event.keys())}")
        v = validate_input(event)
        task_token = v['task_token']
        subject = v['subject']
        details = v['details']
        topic_arn = v['topic_arn']
        apigw_base = v['apigw_base']
        execution_id = v['execution_id']
        estimated_duration = v['estimated_duration']
        task_token_hash = hashlib.md5(task_token.encode()).hexdigest()[:8]
        links = create_approval_links(apigw_base, task_token, execution_id)
        notification = create_notification_message(subject, details, links['approve_url'], links['reject_url'], execution_id, estimated_duration, task_token_hash)
        message_id = send_sns_notification(topic_arn, notification['subject'], notification['body'], execution_id)
        slack_webhook = os.environ.get('SLACK_WEBHOOK_URL', '')
        slack_sent = send_slack_notification(slack_webhook, notification, execution_id) if slack_webhook else False
        execution_time = time.time() - start_time
        return {
            'statusCode': 200,
            'success': True,
            'notified': True,
            'message_id': message_id,
            'execution_id': execution_id,
            'task_token_hash': task_token_hash,
            'notification_channels': {'sns': True, 'slack': slack_sent},
            'approval_links': {'approve_url_length': len(links['approve_url']), 'reject_url_length': len(links['reject_url'])},
            'execution_time_ms': execution_time * 1000,
            'timestamp': time.time()
        }
    except ApprovalRequestError as e:
        logger.error(f"Approval request error: {str(e)}")
        return {'statusCode': 400, 'success': False, 'notified': False, 'error': str(e), 'error_type': 'ApprovalRequestError'}
    except Exception as e:
        logger.error(f"Unexpected error in approval request handler: {str(e)}")
        return {'statusCode': 500, 'success': False, 'notified': False, 'error': f"Unexpected error: {str(e)}", 'error_type': 'UnexpectedError'}
