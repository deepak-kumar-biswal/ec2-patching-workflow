import os
import json
import boto3
import uuid
import time
import logging
import urllib.parse
import hashlib
from typing import Dict, Any, Optional
from botocore.exceptions import ClientError, BotoCoreError
from functools import wraps
from datetime import datetime, timedelta

# Configure structured logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - [%(correlation_id)s] - %(message)s'
)
logger = logging.getLogger(__name__)

class ApprovalCallbackError(Exception):
    """Custom exception for approval callback operations"""
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
                    
                    if error_code in ['ValidationException', 'InvalidParameterValue', 'TaskDoesNotExist']:
                        logger.error(f"Non-retryable error: {error_code}")
                        raise
                    
                    delay = base_delay * (2 ** attempt)
                    logger.warning(f"Retry {attempt + 1}/{max_retries} for {func.__name__} after {delay}s: {error_code}")
                    time.sleep(delay)
            return None
        return wrapper
    return decorator

def validate_request(event: Dict[str, Any]) -> Dict[str, Any]:
    """Validate incoming approval callback request"""
    
    # Extract query string parameters
    query_params = event.get('queryStringParameters') or {}
    
    if not query_params:
        raise ApprovalCallbackError("Missing query string parameters")
    
    # Validate required parameters
    action = query_params.get('action')
    if not action or action not in ('approve', 'reject'):
        raise ApprovalCallbackError(f"Invalid or missing action parameter. Expected 'approve' or 'reject', got: {action}")
    
    token = query_params.get('token')
    if not token:
        raise ApprovalCallbackError("Missing task token parameter")
    
    # URL decode the token
    try:
        decoded_token = urllib.parse.unquote(token)
    except Exception as e:
        raise ApprovalCallbackError(f"Failed to decode task token: {str(e)}")
    
    # Extract optional parameters
    execution_id = query_params.get('executionId', 'unknown')
    timestamp = query_params.get('timestamp')
    
    # Validate timestamp if provided
    if timestamp:
        try:
            timestamp_int = int(timestamp)
            request_time = datetime.fromtimestamp(timestamp_int)
            
            # Check if request is not too old (default 1 hour expiry)
            expiry_minutes = int(os.environ.get('APPROVAL_EXPIRY_MINUTES', '60'))
            if datetime.now() - request_time > timedelta(minutes=expiry_minutes):
                raise ApprovalCallbackError(f"Approval request expired. Request was made {datetime.now() - request_time} ago")
                
        except ValueError:
            logger.warning(f"Invalid timestamp format: {timestamp}")
    
    # Get request metadata
    source_ip = event.get('requestContext', {}).get('identity', {}).get('sourceIp', 'unknown')
    user_agent = event.get('headers', {}).get('User-Agent', 'unknown')
    
    return {
        'action': action,
        'task_token': decoded_token,
        'execution_id': execution_id,
        'timestamp': timestamp,
        'source_ip': source_ip,
        'user_agent': user_agent
    }

def log_approval_decision(
    action: str,
    execution_id: str,
    source_ip: str,
    user_agent: str,
    task_token_hash: str
) -> None:
    """Log approval decision for audit trail"""
    
    audit_data = {
        'event_type': 'approval_decision',
        'action': action,
        'execution_id': execution_id,
        'task_token_hash': task_token_hash,
        'source_ip': source_ip,
        'user_agent': user_agent,
        'timestamp': datetime.utcnow().isoformat(),
        'requestor': 'manual_approval_system'
    }
    
    logger.info(f"Approval decision recorded: {json.dumps(audit_data)}")
    
    # Optional: Store in DynamoDB for audit trail
    audit_table = os.environ.get('AUDIT_TABLE')
    if audit_table:
        try:
            dynamodb = boto3.resource('dynamodb')
            table = dynamodb.Table(audit_table)
            
            table.put_item(
                Item={
                    'audit_id': str(uuid.uuid4()),
                    'timestamp': int(time.time()),
                    'ttl': int(time.time()) + (365 * 24 * 3600),  # 1 year retention
                    **audit_data
                }
            )
            
            logger.info(f"Audit record stored: {audit_data['action']} for execution {execution_id}")
            
        except Exception as e:
            logger.warning(f"Failed to store audit record: {str(e)}")

@retry_with_backoff(max_retries=3, base_delay=1.0)
def send_task_success(task_token: str, execution_id: str) -> Dict[str, Any]:
    """Send task success to Step Functions with comprehensive error handling"""
    
    try:
        sf_client = boto3.client('stepfunctions')
        
        output_data = {
            'approved': True,
            'approval_timestamp': datetime.utcnow().isoformat(),
            'execution_id': execution_id,
            'decision': 'approved'
        }
        
        logger.info(f"Sending task success for execution {execution_id}")
        
        response = sf_client.send_task_success(
            taskToken=task_token,
            output=json.dumps(output_data)
        )
        
        logger.info(f"Task success sent successfully for execution {execution_id}")
        
        return {
            'success': True,
            'response': response,
            'output_data': output_data
        }
        
    except ClientError as e:
        error_code = e.response.get('Error', {}).get('Code', 'Unknown')
        error_message = e.response.get('Error', {}).get('Message', str(e))
        
        logger.error(f"Failed to send task success: {error_code} - {error_message}")
        
        if error_code == 'TaskDoesNotExist':
            raise ApprovalCallbackError("Task token is invalid or has expired")
        elif error_code == 'InvalidToken':
            raise ApprovalCallbackError("Task token format is invalid")
        elif error_code == 'TaskTimedOut':
            raise ApprovalCallbackError("Task has already timed out")
        else:
            raise ApprovalCallbackError(f"Step Functions task success failed [{error_code}]: {error_message}")

@retry_with_backoff(max_retries=3, base_delay=1.0)
def send_task_failure(task_token: str, execution_id: str, reason: str = "Manual rejection") -> Dict[str, Any]:
    """Send task failure to Step Functions with comprehensive error handling"""
    
    try:
        sf_client = boto3.client('stepfunctions')
        
        error_details = {
            'rejected': True,
            'rejection_timestamp': datetime.utcnow().isoformat(),
            'execution_id': execution_id,
            'decision': 'rejected',
            'reason': reason
        }
        
        logger.info(f"Sending task failure for execution {execution_id}")
        
        response = sf_client.send_task_failure(
            taskToken=task_token,
            error='ManualRejection',
            cause=json.dumps(error_details)
        )
        
        logger.info(f"Task failure sent successfully for execution {execution_id}")
        
        return {
            'success': True,
            'response': response,
            'error_details': error_details
        }
        
    except ClientError as e:
        error_code = e.response.get('Error', {}).get('Code', 'Unknown')
        error_message = e.response.get('Error', {}).get('Message', str(e))
        
        logger.error(f"Failed to send task failure: {error_code} - {error_message}")
        
        if error_code == 'TaskDoesNotExist':
            raise ApprovalCallbackError("Task token is invalid or has expired")
        elif error_code == 'InvalidToken':
            raise ApprovalCallbackError("Task token format is invalid")
        elif error_code == 'TaskTimedOut':
            raise ApprovalCallbackError("Task has already timed out")
        else:
            raise ApprovalCallbackError(f"Step Functions task failure failed [{error_code}]: {error_message}")

def send_notification(action: str, execution_id: str, success: bool) -> bool:
    """Send notification about approval decision"""
    
    topic_arn = os.environ.get('NOTIFICATION_TOPIC_ARN')
    if not topic_arn:
        return False
    
    try:
        sns_client = boto3.client('sns')
        
        status = "✅ Approved" if action == 'approve' else "❌ Rejected"
        result_status = "successfully" if success else "with errors"
        
        subject = f"EC2 Patching {status} - {execution_id}"
        message = f"""
Approval Decision Processed {result_status}

Execution ID: {execution_id}
Action: {action.upper()}
Status: {status}
Timestamp: {datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S UTC')}
Result: {'Success' if success else 'Error occurred'}

The EC2 patching workflow has been {'approved and will continue' if action == 'approve' and success else 'rejected or encountered an error'}.
"""
        
        response = sns_client.publish(
            TopicArn=topic_arn,
            Subject=subject,
            Message=message.strip(),
            MessageAttributes={
                'NotificationType': {
                    'DataType': 'String',
                    'StringValue': 'ApprovalDecision'
                },
                'Action': {
                    'DataType': 'String',
                    'StringValue': action
                },
                'ExecutionId': {
                    'DataType': 'String',
                    'StringValue': execution_id
                }
            }
        )
        
        logger.info(f"Notification sent: {response.get('MessageId', 'unknown')}")
        return True
        
    except Exception as e:
        logger.warning(f"Failed to send notification: {str(e)}")
        return False

def generate_response_html(action: str, success: bool, error_message: str = None) -> str:
    """Generate user-friendly HTML response"""
    
    if success:
        if action == 'approve':
            status_icon = "✅"
            status_text = "Approved Successfully"
            message = "The EC2 patching operation has been approved and will now continue."
            color = "#28a745"
        else:
            status_icon = "❌"
            status_text = "Rejected Successfully"
            message = "The EC2 patching operation has been rejected and will not proceed."
            color = "#dc3545"
    else:
        status_icon = "⚠️"
        status_text = "Error Processing Request"
        message = f"An error occurred while processing your {action} request: {error_message}"
        color = "#ffc107"
    
    html = f"""
    <!DOCTYPE html>
    <html>
    <head>
        <title>Approval Result</title>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
            body {{ 
                font-family: Arial, sans-serif; 
                max-width: 600px; 
                margin: 50px auto; 
                padding: 20px; 
                text-align: center;
                background-color: #f8f9fa;
            }}
            .result-box {{ 
                background: white; 
                border-radius: 10px; 
                padding: 30px; 
                box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            }}
            .status-icon {{ font-size: 48px; margin-bottom: 20px; }}
            .status-text {{ 
                color: {color}; 
                font-size: 24px; 
                font-weight: bold; 
                margin-bottom: 15px; 
            }}
            .message {{ 
                font-size: 16px; 
                color: #666; 
                margin-bottom: 20px; 
                line-height: 1.5;
            }}
            .timestamp {{ 
                font-size: 12px; 
                color: #999; 
                margin-top: 20px; 
            }}
        </style>
    </head>
    <body>
        <div class="result-box">
            <div class="status-icon">{status_icon}</div>
            <div class="status-text">{status_text}</div>
            <div class="message">{message}</div>
            <div class="timestamp">
                Processed at: {datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S UTC')}
            </div>
        </div>
    </body>
    </html>
    """
    
    return html.strip()

@with_correlation_id
def handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """
    Enhanced approval callback handler with comprehensive error handling and audit logging
    """
    start_time = time.time()
    
    try:
        logger.info(f"Processing approval callback with event keys: {list(event.keys())}")
        
        # Validate request
        request_data = validate_request(event)
        
        action = request_data['action']
        task_token = request_data['task_token']
        execution_id = request_data['execution_id']
        source_ip = request_data['source_ip']
        user_agent = request_data['user_agent']
        
        # Create task token hash for logging (don't log full token)
        task_token_hash = hashlib.md5(task_token.encode()).hexdigest()[:8]
        
        logger.info(f"Processing {action} request for execution {execution_id} from IP {source_ip}")
        
        # Log approval decision for audit trail
        log_approval_decision(action, execution_id, source_ip, user_agent, task_token_hash)
        
        # Process the approval decision
        if action == 'approve':
            result = send_task_success(task_token, execution_id)
            response_body = "Approved. The EC2 patching workflow will continue."
        else:
            result = send_task_failure(task_token, execution_id, "Operator manually rejected the operation")
            response_body = "Rejected. The EC2 patching workflow has been terminated."
        
        success = result.get('success', False)
        
        # Send notification
        notification_sent = send_notification(action, execution_id, success)
        
        execution_time = time.time() - start_time
        
        # Generate response
        if success:
            html_response = generate_response_html(action, True)
            
            logger.info(f"Approval callback completed successfully in {execution_time:.2f}s")
            logger.info(f"Action: {action}, Execution: {execution_id}, Notification sent: {notification_sent}")
            
            return {
                'statusCode': 200,
                'headers': {
                    'Content-Type': 'text/html',
                    'Cache-Control': 'no-cache'
                },
                'body': html_response
            }
        else:
            return {
                'statusCode': 500,
                'headers': {
                    'Content-Type': 'text/plain'
                },
                'body': f"Error processing {action} request"
            }
        
    except ApprovalCallbackError as e:
        logger.error(f"Approval callback error: {str(e)}")
        execution_time = time.time() - start_time
        
        html_response = generate_response_html('unknown', False, str(e))
        
        return {
            'statusCode': 400,
            'headers': {
                'Content-Type': 'text/html',
                'Cache-Control': 'no-cache'
            },
            'body': html_response
        }
    
    except Exception as e:
        logger.error(f"Unexpected error in approval callback handler: {str(e)}")
        execution_time = time.time() - start_time
        
        html_response = generate_response_html('unknown', False, "An unexpected error occurred")
        
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'text/html',
                'Cache-Control': 'no-cache'
            },
            'body': html_response
        }
