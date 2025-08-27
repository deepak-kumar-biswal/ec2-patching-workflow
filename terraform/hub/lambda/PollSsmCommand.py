import boto3

def handler(event, ctx):
    sts = boto3.client('sts')
    c = sts.assume_role(RoleArn=event['roleArn'], RoleSessionName='poll')['Credentials']
    ssm = boto3.client('ssm', region_name=event['region'],
                       aws_access_key_id=c['AccessKeyId'],
                       aws_secret_access_key=c['SecretAccessKey'],
                       aws_session_token=c['SessionToken'])
    cmd_id = event['cmd']['Command']['CommandId']
    invs = ssm.list_command_invocations(CommandId=cmd_id, Details=False).get('CommandInvocations', [])
    all_done = all(i['Status'] in ('Success','Cancelled','Failed','TimedOut') for i in invs) and len(invs) > 0
    return {"allDone": all_done}
