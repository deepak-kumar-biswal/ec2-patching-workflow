import os
import json
import time
import logging
from typing import Any, Dict, Optional

import boto3
from botocore.config import Config
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

_session = boto3.session.Session()
_sts = _session.client("sts")

# Simple retry wrapper for throttling and transient faults
def _retry(max_attempts=3, base=1.0, factor=2.0):
    def deco(fn):
        def wrapper(*args, **kwargs):
            attempt = 0
            delay = base
            while True:
                try:
                    return fn(*args, **kwargs)
                except ClientError as e:
                    code = e.response.get("Error", {}).get("Code", "")
                    if code in {"ThrottlingException", "Throttling", "RequestLimitExceeded", "TooManyRequestsException", "InternalError", "ServiceUnavailable"} and attempt < max_attempts - 1:
                        logger.warning("%s on attempt %s, retrying in %.1fs", code, attempt + 1, delay)
                        time.sleep(delay)
                        attempt += 1
                        delay *= factor
                        continue
                    raise
        return wrapper
    return deco

@_retry(max_attempts=3, base=1.0, factor=2.0)
def _assume(role_arn: str, external_id: str) -> Dict[str, Any]:
    params = {
        "RoleArn": role_arn,
        "RoleSessionName": "ec2-patch-send-ssm",
        "DurationSeconds": 3600,
    }
    if external_id:
        params["ExternalId"] = external_id
    resp = _sts.assume_role(**params)
    return resp["Credentials"]

@_retry(max_attempts=3, base=1.0, factor=2.0)
def _send_command(
    ssm,
    document_name: str,
    targets: list,
    max_concurrency: str,
    max_errors: str,
    parameters: Optional[Dict[str, Any]] = None,
    output_s3_bucket: Optional[str] = None,
    output_s3_prefix: Optional[str] = None,
) -> Dict[str, Any]:
    kwargs: Dict[str, Any] = {
        "DocumentName": document_name,
        "Targets": targets,
        "MaxConcurrency": max_concurrency,
        "MaxErrors": max_errors,
    }
    if parameters:
        kwargs["Parameters"] = parameters
    if output_s3_bucket:
        kwargs["OutputS3BucketName"] = output_s3_bucket
    if output_s3_prefix:
        kwargs["OutputS3KeyPrefix"] = output_s3_prefix
    return ssm.send_command(**kwargs)


def handler(event, context):
    """
    Input contract:
    {
      "roleArn": "arn:aws:iam::<spoke>:role/<PatchExecRole>",
      "externalId": "<external-id>",
      "region": "us-east-1",
      "documentName": "AWS-RunPatchBaseline",
      "targets": [{"Key": "tag:PatchGroup", "Values": ["prod"]}],
      "maxConcurrency": "10%",
      "maxErrors": "1",
      "parameters": { ... optional SSM doc params ... }
    }

    Output:
    { "CommandId": "<id>", "Region": "<region>", "Account": "<derived from role arn>" }
    """
    logger.info("Event: %s", json.dumps(event))

    role_arn = event.get("roleArn")
    external_id = event.get("externalId", "")
    region = event.get("region")
    document_name = event.get("documentName", "AWS-RunPatchBaseline")
    targets = event.get("targets") or []
    max_conc = event.get("maxConcurrency", "10%")
    max_err = event.get("maxErrors", "1")
    parameters = event.get("parameters")
    output_s3_bucket = event.get("outputS3Bucket")
    output_s3_prefix = event.get("outputS3Prefix")

    if not role_arn or not region:
        raise ValueError("roleArn and region are required")

    creds = _assume(role_arn, external_id)
    ssm = _session.client(
        "ssm",
        region_name=region,
        aws_access_key_id=creds["AccessKeyId"],
        aws_secret_access_key=creds["SecretAccessKey"],
        aws_session_token=creds["SessionToken"],
        config=Config(retries={"max_attempts": 10, "mode": "standard"}),
    )

    resp = _send_command(
        ssm,
        document_name=document_name,
        targets=targets,
        max_concurrency=max_conc,
        max_errors=max_err,
        parameters=parameters,
        output_s3_bucket=output_s3_bucket,
        output_s3_prefix=output_s3_prefix,
    )

    cmd_id = resp.get("Command", {}).get("CommandId")
    account_id = role_arn.split(":")[4]
    return {"CommandId": cmd_id, "Region": region, "Account": account_id}
