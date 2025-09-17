# Operations Runbook

This runbook covers day-2 operations for the EC2 Patching Orchestrator.

## 1. Scheduling & Launching Waves

- Use maintenance windows and tags (e.g., `PatchGroup`) to shape scope.
- Start executions via Step Functions console or API.
- Prefer small canary waves for first runs in each environment.

## 2. Approvals

- Manual approvals are sent via SNS/Email (or chat integration if wired).
- Approval links call API Gateway with a task token.
- If an approval times out, the execution follows the timeout branch; re-run the wave as needed.

## 3. SSM Run Command

- Patching is executed via `AWS-RunPatchBaseline`.
- Outputs are written to S3 (artifact bucket) per instance for auditing.
- Use MaxConcurrency and MaxErrors to control blast radius.

## 4. Monitoring & Alarms

- CloudWatch Dashboards expose execution, errors, and resource KPIs.
- CloudWatch Alarms cover Step Functions failures, Lambda errors/throttles, and elevated durations.
- Route alarms to your incident channel and page on repeated failures.

## 5. Investigations

- Step Functions execution history: inspect failed branches and inputs/outputs.
- Lambda logs: `/aws/lambda/<function-name>`; check error traces and contextual logs.
- SSM: review command invocations for failing instances and S3-captured outputs.
 - Pre-collection (hub-write): use the execution ID to locate snapshots quickly in the hub S3 bucket under:
	 - `runs/<ExecutionId>/pre/account-<AccountId>/region-<Region>/<os>/<InstanceId>/`
	 - Files per instance: `stdout.txt`, `stderr.txt`, `meta.json`
	 - Example (list first 20 keys):
		 ```bash
		 aws s3api list-objects-v2 \
			 --bucket <SnapshotsBucket> \
			 --prefix runs/<ExecutionId>/pre/ \
			 --max-keys 20 \
			 --query 'Contents[].Key'
		 ```

## 6. Retry Strategy

- Single-instance failures: re-target via SSM manually or re-run the wave with a filtered scope.
- Partial success policy: the system records 206 outcomes; re-run is safe after investigation.
- Use exponential backoff for repeated transient errors.

## 7. Abort/Cancel

- Standard Step Functions executions can be stopped from the console/API.
- For long-running SSM commands, cancel invocations where appropriate to free capacity.

## 8. Scaling Knobs

- Step Functions: Map concurrency at wave/account/region layers.
- Lambda: reserved concurrency for Send/Poll/Approval handlers to avoid noisy-neighbor.
- SSM: tune `MaxConcurrency` (percentage or count) and `MaxErrors` conservatively, then raise.

## 9. Cost Awareness

- Large parallelism increases Lambda/Step Functions/SSM costs. Scale gradually.
- Use log retention and filter patterns to control CloudWatch Logs spend.

## 10. Security Posture

- KMS key policies for S3/DynamoDB/SNS validated and least-privilege IAM.
- TLS-only S3 bucket policy; DynamoDB PITR and TTL enabled.

## 11. Runbooks for Common Issues

- Role assumption failures → verify spoke trust and ExternalId.
- Step Functions timeouts → check per-state timeouts and Lambda durations.
- Lambda throttles → increase reserved concurrency or reduce parallelism upstream.
- SSM command errors → inspect per-instance output in S3; verify patch baseline.

## 12. Useful CLI

```powershell
# List executions
aws stepfunctions list-executions --state-machine-arn <arn> --status-filter RUNNING

# Tail logs for a function
aws logs tail /aws/lambda/<function> --follow

# Check SSM command status
aws ssm list-commands --filters Key=DocumentName,Values=AWS-RunPatchBaseline
```

## 13. Change Management

- Use GitHub Actions for repeatable deploys with JSON parameter files.
- Promote changes via PRs; tag releases and record parameter deltas.

## 14. Contacts & Ownership

- Define on-call rotation and escalation path for patch windows.
- Keep runbook owners current; review quarterly.
