# EC2 Multi-Account Patching – Terraform (Hub & Spoke)

This codebase deploys a **production-grade** EC2 patching orchestrator (hub) and the **cross-account role** (spoke) used to patch instances across multiple accounts/regions with **per-account wave windows**, **manual approval**, **SNS alerts**, **Bedrock analysis**, **S3/DynamoDB state**, and a **CloudWatch dashboard**.

## Structure
```
terraform/
  hub/    # deploy in HUB (orchestrator) account
  spoke/  # deploy in each TARGET (spoke) account
.github/workflows/
examples/
```

## Prereqs
- Terraform >= 1.5, AWS CLI, and an **OIDC-enabled GitHub role** in each account for CI/CD (or use local AWS credentials).
- SSM Agent installed and managed on EC2 instances.
- Instances tagged with `PatchGroup=default` (or adjust `tagKey/tagValue` in EventBridge input).

## Variables (hub)
- `region` – e.g. `us-east-1`
- `orchestrator_account_id` – 12-digit account ID of hub
- `name_prefix` – short name, e.g. `ec2patch`
- `sns_email_subscriptions` – list of emails to notify (optional)
- `wave_rules` – list of objects: `{ name, schedule_expression, accounts, regions }`
- `bedrock_agent_id`, `bedrock_agent_alias_id`
- `wave_pause_seconds` – pause between waves when executed via SFN input
- `abort_on_issues` – fail the state machine if issues are detected

## Variables (spoke)
- `region` – region for spoke resources
- `orchestrator_account_id` – hub account ID
- `role_name` – default `PatchExecRole`

## Deploy – Hub
```
cd terraform/hub
terraform init
terraform apply   -var='region=us-east-1'   -var='orchestrator_account_id=111111111111'   -var='name_prefix=ec2patch'   -var='bedrock_agent_id=AGENT_ID'   -var='bedrock_agent_alias_id=ALIAS_ID'   -var='wave_rules=[
      { name="use1-wave1", schedule_expression="cron(0 3 ? * SAT *)", accounts=["222222222222","333333333333"], regions=["us-east-1"] },
      { name="use1-wave2", schedule_expression="cron(30 3 ? * SAT *)", accounts=["444444444444","555555555555"], regions=["us-east-1"] }
    ]'
```

## Deploy – Spoke (repeat per target account)
```
cd terraform/spoke
terraform init
terraform apply -var='region=us-east-1' -var='orchestrator_account_id=111111111111'
```

## Manual Approval
- An **SNS email** includes two links (`Approve`/`Reject`) pointing to the API Gateway `/callback` route.
- Approval triggers the **Step Functions** state machine to proceed.

## Start a Run Manually
You can start execution with a JSON `input` similar to what EventBridge sends:
```json
{
  "accountWaves": [
    { "accounts": ["222222222222","333333333333"], "regions": ["us-east-1"] }
  ],
  "ec2": { "tagKey": "PatchGroup", "tagValue": "default" },
  "snsTopicArn": "arn:aws:sns:us-east-1:111111111111:ec2patch-PatchAlerts",
  "bedrock": { "agentId": "AGENT_ID", "agentAliasId": "ALIAS_ID" },
  "wavePauseSeconds": 0,
  "abortOnIssues": true
}
```

## CloudWatch Dashboard
A dashboard named `${name_prefix}-dashboard` is created with **Step Functions** and **Lambda** error metrics.

## Security Notes
- `PatchExecRole` is limited to SSM/EC2 read + required operations.
- Step Functions assumes `PatchExecRole` in each target account.
