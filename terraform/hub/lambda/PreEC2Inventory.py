import os, json, boto3, datetime
s3 = boto3.client('s3'); ddb = boto3.resource('dynamodb')
TABLE = ddb.Table(os.environ['DDB_TABLE']); BUCKET = os.environ['S3_BUCKET']

def assume(role_arn):
    sts = boto3.client('sts')
    creds = sts.assume_role(RoleArn=role_arn, RoleSessionName='preinv')['Credentials']
    return creds

def ssm_client(creds, region):
    return boto3.client('ssm', region_name=region,
        aws_access_key_id=creds['AccessKeyId'],
        aws_secret_access_key=creds['SecretAccessKey'],
        aws_session_token=creds['SessionToken'])

def handler(event, ctx):
    today = datetime.datetime.utcnow().strftime('%Y/%m/%d')
    accounts = event.get('accounts') or []
    regions = event.get('regions') or [os.environ.get('AWS_REGION','us-east-1')]
    for account in accounts:
        role = f"arn:aws:iam::{account}:role/PatchExecRole"
        creds = assume(role)
        for region in regions:
            ssm = ssm_client(creds, region)
            infos = []
            paginator = ssm.get_paginator('describe_instance_information')
            for page in paginator.paginate():
                infos.extend(page.get('InstanceInformationList', []))
            inv = { ii['InstanceId']: {'Instance': ii} for ii in infos }
            key = f"{today}/{account}/{region}/pre_ec2.json"
            s3.put_object(Bucket=BUCKET, Key=key, Body=json.dumps(inv).encode('utf-8'))
            TABLE.put_item(Item={ 'scope':'EC2#PRE', 'id': f'{account}:{region}:{today}', 's3key': key, 'count': len(infos) })
    return {"ok": True}
