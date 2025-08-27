#############################################
# EC2 Patching Orchestrator (Hub Account)
#############################################

locals {
  s3_bucket_name     = "${var.name_prefix}-${var.orchestrator_account_id}-snapshots"
  ddb_table_name     = "${var.name_prefix}-PatchRuns"
  sns_topic_name     = "${var.name_prefix}-PatchAlerts"
  sfn_name           = "${var.name_prefix}-EC2PatchOrchestrator"
  approval_lambda    = "${var.name_prefix}-SendApprovalRequest"
  callback_lambda    = "${var.name_prefix}-ApprovalCallback"
}

# S3 for pre/post snapshots
resource "aws_s3_bucket" "snapshots" {
  bucket = local.s3_bucket_name
  force_destroy = false
}

# DynamoDB to track runs
resource "aws_dynamodb_table" "patchruns" {
  name         = local.ddb_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "scope"
  range_key    = "id"
  attribute { name = "scope" type = "S" }
  attribute { name = "id"    type = "S" }
}

# SNS for alerts
resource "aws_sns_topic" "alerts" {
  name = local.sns_topic_name
}

resource "aws_sns_topic_subscription" "emails" {
  count     = length(var.sns_email_subscriptions)
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.sns_email_subscriptions[count.index]
}

# ---------------- Lambda packaging ----------------
data "archive_file" "pre_ec2" {
  type        = "zip"
  source_file = "${path.module}/lambda/PreEC2Inventory.py"
  output_path = "${path.module}/lambda/PreEC2Inventory.zip"
}

data "archive_file" "poll_ssm" {
  type        = "zip"
  source_file = "${path.module}/lambda/PollSsmCommand.py"
  output_path = "${path.module}/lambda/PollSsmCommand.zip"
}

data "archive_file" "post_ec2" {
  type        = "zip"
  source_file = "${path.module}/lambda/PostEC2Verify.py"
  output_path = "${path.module}/lambda/PostEC2Verify.zip"
}

data "archive_file" "bedrock" {
  type        = "zip"
  source_file = "${path.module}/lambda/AnalyzeWithBedrock.py"
  output_path = "${path.module}/lambda/AnalyzeWithBedrock.zip"
}

data "archive_file" "approval" {
  type        = "zip"
  source_file = "${path.module}/lambda/SendApprovalRequest.py"
  output_path = "${path.module}/lambda/SendApprovalRequest.zip"
}

# Inline code for ApprovalCallback Lambda is bundled via file below
data "archive_file" "callback" {
  type        = "zip"
  source_file = "${path.module}/lambda/ApprovalCallback.py"
  output_path = "${path.module}/lambda/ApprovalCallback.zip"
}

# ---------------- Lambda IAM ----------------
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals { type = "Service" identifiers = ["lambda.amazonaws.com"] }
  }
}

resource "aws_iam_role" "lambda_exec" {
  name               = "${var.name_prefix}-lambda-exec"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Permissions for Lambdas
resource "aws_iam_policy" "lambda_permissions" {
  name = "${var.name_prefix}-lambda-permissions"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["s3:PutObject","s3:PutObjectAcl"]
        Resource = "${aws_s3_bucket.snapshots.arn}/*"
      },
      {
        Effect = "Allow"
        Action = ["dynamodb:PutItem","dynamodb:UpdateItem","dynamodb:GetItem","dynamodb:Query"]
        Resource = aws_dynamodb_table.patchruns.arn
      },
      {
        Effect = "Allow"
        Action = ["sns:Publish"]
        Resource = aws_sns_topic.alerts.arn
      },
      {
        Effect = "Allow"
        Action = ["sts:AssumeRole"]
        Resource = "arn:aws:iam::*:role/${var.name_prefix != "" ? "PatchExecRole" : "PatchExecRole"}"
      },
      {
        Effect = "Allow"
        Action = ["bedrock:InvokeAgent"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_permissions_attach" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_permissions.arn
}

# ---------------- Lambda functions ----------------
resource "aws_lambda_function" "pre_ec2" {
  function_name = "${var.name_prefix}-PreEC2Inventory"
  role          = aws_iam_role.lambda_exec.arn
  filename         = data.archive_file.pre_ec2.output_path
  source_code_hash = data.archive_file.pre_ec2.output_base64sha256
  handler       = "PreEC2Inventory.handler"
  runtime       = "python3.11"
  environment {
    variables = {
      S3_BUCKET = aws_s3_bucket.snapshots.bucket
      DDB_TABLE = aws_dynamodb_table.patchruns.name
    }
  }
}

resource "aws_lambda_function" "poll_ssm" {
  function_name = "${var.name_prefix}-PollSsmCommand"
  role          = aws_iam_role.lambda_exec.arn
  filename         = data.archive_file.poll_ssm.output_path
  source_code_hash = data.archive_file.poll_ssm.output_base64sha256
  handler       = "PollSsmCommand.handler"
  runtime       = "python3.11"
}

resource "aws_lambda_function" "post_ec2" {
  function_name = "${var.name_prefix}-PostEC2Verify"
  role          = aws_iam_role.lambda_exec.arn
  filename         = data.archive_file.post_ec2.output_path
  source_code_hash = data.archive_file.post_ec2.output_base64sha256
  handler       = "PostEC2Verify.handler"
  runtime       = "python3.11"
  environment {
    variables = {
      S3_BUCKET = aws_s3_bucket.snapshots.bucket
      DDB_TABLE = aws_dynamodb_table.patchruns.name
    }
  }
}

resource "aws_lambda_function" "bedrock" {
  function_name = "${var.name_prefix}-AnalyzeWithBedrock"
  role          = aws_iam_role.lambda_exec.arn
  filename         = data.archive_file.bedrock.output_path
  source_code_hash = data.archive_file.bedrock.output_base64sha256
  handler       = "AnalyzeWithBedrock.handler"
  runtime       = "python3.11"
}

resource "aws_lambda_function" "approval" {
  function_name = local.approval_lambda
  role          = aws_iam_role.lambda_exec.arn
  filename         = data.archive_file.approval.output_path
  source_code_hash = data.archive_file.approval.output_base64sha256
  handler       = "SendApprovalRequest.handler"
  runtime       = "python3.11"
  environment {
    variables = {
      TOPIC_ARN  = aws_sns_topic.alerts.arn
      APIGW_BASE = aws_apigatewayv2_api.http_api.api_endpoint
    }
  }
}

resource "aws_lambda_function" "callback" {
  function_name = local.callback_lambda
  role          = aws_iam_role.lambda_exec.arn
  filename         = data.archive_file.callback.output_path
  source_code_hash = data.archive_file.callback.output_base64sha256
  handler       = "ApprovalCallback.handler"
  runtime       = "python3.11"
}

# ---------------- API Gateway HTTP API ----------------
resource "aws_apigatewayv2_api" "http_api" {
  name          = "${var.name_prefix}-ApprovalCallbackAPI"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "lambda_proxy" {
  api_id           = aws_apigatewayv2_api.http_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.callback.invoke_arn
}

resource "aws_apigatewayv2_route" "callback" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "GET /callback"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_proxy.id}"
}

resource "aws_lambda_permission" "allow_apigw" {
  statement_id  = "AllowInvokeByAPIGW"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.callback.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}

# ---------------- Step Functions ----------------
data "aws_iam_policy_document" "sfn_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals { type = "Service" identifiers = ["states.amazonaws.com"] }
  }
}

resource "aws_iam_role" "sfn_role" {
  name               = "${var.name_prefix}-sfn-role"
  assume_role_policy = data.aws_iam_policy_document.sfn_assume.json
}

resource "aws_iam_role_policy" "sfn_inline" {
  role = aws_iam_role.sfn_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      { Effect="Allow", Action=["lambda:InvokeFunction"], Resource=[
        aws_lambda_function.pre_ec2.arn,
        aws_lambda_function.poll_ssm.arn,
        aws_lambda_function.post_ec2.arn,
        aws_lambda_function.bedrock.arn,
        aws_lambda_function.approval.arn
      ]},
      { Effect="Allow", Action=["sns:Publish"], Resource=[aws_sns_topic.alerts.arn] },
      { Effect="Allow", Action=["ssm:SendCommand","ssm:GetCommandInvocation","ssm:ListCommandInvocations","ssm:ListCommands"], Resource="*" },
      { Effect="Allow", Action=["sts:AssumeRole"], Resource="arn:aws:iam::*:role/PatchExecRole" }
    ]
  })
}

locals {
  sfn_definition = jsonencode({
    Comment = "EC2 patch orchestrator with per-account waves and manual approval",
    StartAt = "ManualApproval",
    States = {
      ManualApproval = {
        Type = "Task",
        Resource = "arn:aws:states:::lambda:invoke.waitForTaskToken",
        Parameters = {
          FunctionName = aws_lambda_function.approval.function_name,
          Payload = {
            taskToken.$ = "$$.Task.Token",
            subject     = "Approve EC2 patch run (per-account waves)",
            details.$   = "$"
          }
        },
        ResultPath = "$.approval",
        Next = "WaveMap"
      },
      WaveMap = {
        Type = "Map",
        ItemsPath = "$.accountWaves",
        MaxConcurrency = 1,
        Iterator = {
          StartAt = "PreWaveInventory",
          States = {
            PreWaveInventory = {
              Type = "Task",
              Resource = "arn:aws:states:::lambda:invoke",
              Parameters = {
                FunctionName = aws_lambda_function.pre_ec2.function_name,
                Payload = {
                  accounts.$ = "$.accounts",
                  regions.$  = "$.regions"
                }
              },
              ResultPath = "$.pre",
              Next = "AccountsInWave"
            },
            AccountsInWave = {
              Type = "Map",
              ItemsPath = "$.accounts",
              MaxConcurrency = 1,
              Parameters = {
                accountId.$ = "$$.Map.Item.Value",
                regions.$   = "$.regions",
                tagKey.$    = "$.tagKey",
                tagValue.$  = "$.tagValue",
                roleArn.$   = "States.Format('arn:aws:iam::{}:role/PatchExecRole', $$.Map.Item.Value)"
              },
              Iterator = {
                StartAt = "RegionMap",
                States = {
                  RegionMap = {
                    Type = "Map",
                    ItemsPath = "$.regions",
                    MaxConcurrency = 1,
                    Parameters = {
                      accountId.$ = "$.accountId",
                      region.$    = "$$.Map.Item.Value",
                      tagKey.$    = "$.tagKey",
                      tagValue.$  = "$.tagValue",
                      roleArn.$   = "$.roleArn"
                    },
                    Iterator = {
                      StartAt = "SendPatchCommand",
                      States = {
                        SendPatchCommand = {
                          Type = "Task",
                          Resource = "arn:aws:states:::aws-sdk:ssm:sendCommand",
                          Parameters = {
                            DocumentName = "AWS-RunPatchBaseline",
                            Targets = [
                              {
                                Key.$    = "States.Format('tag:{}', $.tagKey)",
                                Values.$ = "States.Array($.tagValue)"
                              }
                            ],
                            MaxConcurrency = "10%",
                            MaxErrors      = "2",
                            Parameters     = { Operation = ["Install"], RebootOption = ["RebootIfNeeded"] }
                          },
                          Credentials = { RoleArn.$ = "$.roleArn" },
                          ResultPath  = "$.cmd",
                          Next        = "Wait60"
                        },
                        Wait60 = { Type = "Wait", Seconds = 60, Next = "Poll" },
                        Poll = {
                          Type = "Task",
                          Resource = "arn:aws:states:::lambda:invoke",
                          Parameters = { FunctionName = aws_lambda_function.poll_ssm.function_name, Payload.$ = "$" },
                          ResultSelector = { allDone.$ = "$.Payload.allDone" },
                          ResultPath     = "$.poll",
                          Next           = "DoneChoice"
                        },
                        DoneChoice = {
                          Type = "Choice",
                          Choices = [ { Variable = "$.poll.allDone", BooleanEquals = true, Next = "Success" } ],
                          Default = "Wait60"
                        },
                        Success = { Type = "Succeed" }
                      }
                    },
                    Next = "RegionDone"
                  },
                  RegionDone = { Type = "Succeed" }
                }
              },
              Next = "PostWaveVerify"
            },
            PostWaveVerify = {
              Type = "Task",
              Resource = "arn:aws:states:::lambda:invoke",
              Parameters = {
                FunctionName = aws_lambda_function.post_ec2.function_name,
                Payload = {
                  accounts.$ = "$.accounts",
                  regions.$  = "$.regions"
                }
              },
              ResultPath = "$.post",
              Next = "IssuesChoice"
            },
            IssuesChoice = {
              Type = "Choice",
              Choices = [ { Variable = "$.post.Payload.hasIssues", BooleanEquals = true, Next = "AnalyzeWaveIssues" } ],
              Default = "WavePause"
            },
            AnalyzeWaveIssues = {
              Type = "Task",
              Resource = "arn:aws:states:::lambda:invoke",
              Parameters = { FunctionName = aws_lambda_function.bedrock.function_name, Payload.$ = "$" },
              ResultPath = "$.analysis",
              Next = "AbortOrContinue"
            },
            AbortOrContinue = {
              Type = "Choice",
              Choices = [ { Variable = "$.abortOnIssues", BooleanEquals = true, Next = "FailWave" } ],
              Default = "WavePause"
            },
            FailWave = { Type = "Fail", Cause = "Issues detected; abortOnIssues == true" },
            WavePause = { Type = "Wait", SecondsPath = "$.wavePauseSeconds", Next = "WaveDone" },
            WaveDone = { Type = "Succeed" }
          }
        },
        Next = "Done"
      },
      Done = { Type = "Succeed" }
    }
  })
}

resource "aws_sfn_state_machine" "orchestrator" {
  name     = local.sfn_name
  role_arn = aws_iam_role.sfn_role.arn
  definition = local.sfn_definition
}

# ---------------- EventBridge multi-rule (per-account waves) ----------------
resource "aws_iam_role" "events_invoke" {
  name               = "${var.name_prefix}-events-invoke-sfn"
  assume_role_policy = jsonencode({
    Version="2012-10-17", Statement=[{
      Effect="Allow", Principal={Service="events.amazonaws.com"}, Action="sts:AssumeRole"
    }]
  })
}
resource "aws_iam_role_policy" "events_invoke" {
  role = aws_iam_role.events_invoke.id
  policy = jsonencode({
    Version="2012-10-17", Statement=[{
      Effect="Allow", Action="states:StartExecution", Resource=aws_sfn_state_machine.orchestrator.arn
    }]
  })
}

resource "aws_cloudwatch_event_rule" "waves" {
  for_each           = { for w in var.wave_rules : w.name => w }
  name               = "${var.name_prefix}-${each.value.name}"
  description        = "Wave rule ${each.value.name}"
  schedule_expression = each.value.schedule_expression
  is_enabled         = true
}

resource "aws_cloudwatch_event_target" "waves" {
  for_each  = aws_cloudwatch_event_rule.waves
  rule      = each.value.name
  target_id = "sfn"
  arn       = aws_sfn_state_machine.orchestrator.arn
  role_arn  = aws_iam_role.events_invoke.arn
  input     = jsonencode({
    accountWaves      = [ { accounts = each.value.accounts, regions = each.value.regions } ]
    ec2               = { tagKey = "PatchGroup", tagValue = "default" }
    snsTopicArn       = aws_sns_topic.alerts.arn
    bedrock           = { agentId = var.bedrock_agent_id, agentAliasId = var.bedrock_agent_alias_id }
    wavePauseSeconds  = var.wave_pause_seconds
    abortOnIssues     = var.abort_on_issues
  })
}

# ---------------- CloudWatch Dashboard ----------------
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.name_prefix}-dashboard"
  dashboard_body = jsonencode({
    widgets = [
      {
        "type":"metric","x":0,"y":0,"width":12,"height":6,
        "properties":{
          "metrics":[ ["AWS/States","ExecutionsStarted","StateMachineArn", aws_sfn_state_machine.orchestrator.arn],
                      ["AWS/States","ExecutionsFailed","StateMachineArn", aws_sfn_state_machine.orchestrator.arn],
                      ["AWS/States","ExecutionsSucceeded","StateMachineArn", aws_sfn_state_machine.orchestrator.arn] ],
          "view":"timeSeries","stacked":false,"region":var.region,"title":"Step Functions Executions"
        }
      },
      {
        "type":"metric","x":12,"y":0,"width":12,"height":6,
        "properties":{
          "metrics":[ ["AWS/Lambda","Errors","FunctionName", aws_lambda_function.pre_ec2.function_name],
                      ["AWS/Lambda","Errors","FunctionName", aws_lambda_function.post_ec2.function_name],
                      ["AWS/Lambda","Errors","FunctionName", aws_lambda_function.poll_ssm.function_name] ],
          "view":"timeSeries","stacked":false,"region":var.region,"title":"Lambda Errors"
        }
      }
    ]
  })
}
