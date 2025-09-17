import os
import time
import json
import hmac
import hashlib
import logging
import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

_cached_secret_value = None

def _get_signing_secret() -> bytes:
    global _cached_secret_value
    if _cached_secret_value:
        return _cached_secret_value
    secret_arn = os.environ.get("APPROVAL_SIGNING_SECRET_ARN")
    if not secret_arn:
        raise RuntimeError("APPROVAL_SIGNING_SECRET_ARN not set")
    sm = boto3.client("secretsmanager")
    resp = sm.get_secret_value(SecretId=secret_arn)
    val = resp.get("SecretString")
    if not val and "SecretBinary" in resp:
        val = resp["SecretBinary"].decode("utf-8")
    try:
        parsed = json.loads(val)
        val = parsed.get("secret") or parsed.get("value") or val
    except Exception:
        pass
    _cached_secret_value = val.encode("utf-8")
    return _cached_secret_value

def _const_eq(a: str, b: str) -> bool:
    return hmac.compare_digest(a, b)

def _build_canonical_string(token: str, timestamp: str, action: str, execution_id: str) -> str:
    return f"{token}:{timestamp}:{action}:{execution_id}"

def handler(event, context):
    try:
        query = event.get("queryStringParameters") or {}
        sig = (query.get("sig") or "").strip()
        token = (query.get("token") or "").strip()
        ts = (query.get("timestamp") or "").strip()
        action = (query.get("action") or "").strip()
        execution_id = (query.get("executionId") or "").strip()
        if not all([sig, token, ts, action]):
            return {"isAuthorized": False}
        max_age_minutes = int(os.environ.get("APPROVAL_EXPIRY_MINUTES", "60"))
        try:
            ts_int = int(ts)
        except ValueError:
            return {"isAuthorized": False}
        if abs(int(time.time()) - ts_int) > max_age_minutes * 60:
            return {"isAuthorized": False}
        secret = _get_signing_secret()
        canonical = _build_canonical_string(token, ts, action, execution_id)
        expected = hmac.new(secret, canonical.encode("utf-8"), hashlib.sha256).hexdigest()
        if not _const_eq(expected, sig):
            return {"isAuthorized": False}
        return {"isAuthorized": True, "context": {"action": action, "executionId": execution_id or "unknown"}}
    except Exception as e:
        logger.error(f"Authorizer error: {e}")
        return {"isAuthorized": False}
