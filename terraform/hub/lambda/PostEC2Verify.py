import os, json, boto3, datetime
s3=boto3.client('s3'); ddb=boto3.resource('dynamodb').Table(os.environ['DDB_TABLE'])
BUCKET=os.environ['S3_BUCKET']

def handler(event, ctx):
    today = datetime.datetime.utcnow().strftime('%Y/%m/%d')
    issues=[]
    accounts = event.get('accounts') or []
    regions = event.get('regions') or [os.environ.get('AWS_REGION','us-east-1')]
    for account in accounts:
        role=f"arn:aws:iam::{account}:role/PatchExecRole"
        c=boto3.client('sts').assume_role(RoleArn=role, RoleSessionName='post')['Credentials']
        for region in regions:
            client = boto3.client('ssm', region_name=region,
                aws_access_key_id=c['AccessKeyId'],
                aws_secret_access_key=c['SecretAccessKey'],
                aws_session_token=c['SessionToken'])
            paginator = client.get_paginator('describe_instance_patch_states')
            states=[]
            for page in paginator.paginate(InstanceIds=[]):
                states.extend(page.get('InstancePatchStates', []))
            key = f"{today}/{account}/{region}/post_ec2_patchstates.json"
            s3.put_object(Bucket=BUCKET, Key=key, Body=json.dumps(states).encode('utf-8'))
            bad = [s for s in states if s.get('MissingCount',0)>0 or s.get('FailedCount',0)>0]
            if bad:
                issues.append({'account':account,'region':region,'count':len(bad),'s3key':key})
            ddb.put_item(Item={'scope':'EC2#POST','id':f'{account}:{region}:{today}','s3key':key,'bad':len(bad)})
    return {"hasIssues": bool(issues), "issues": issues}
