# Enhanced CloudWatch Dashboard for Production Monitoring
resource "aws_cloudwatch_dashboard" "production_dashboard" {
  dashboard_name = "${var.name_prefix}-production-dashboard"
  
  dashboard_body = jsonencode({
    widgets = [
      # Executive Summary Row
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 6
        height = 6
        properties = {
          metrics = [
            ["AWS/States", "ExecutionTime", "StateMachineArn", aws_sfn_state_machine.orchestrator.arn, { stat = "Average" }],
            ["AWS/States", "ExecutionTime", "StateMachineArn", aws_sfn_state_machine.orchestrator.arn, { stat = "Maximum" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.region
          title   = "Execution Duration (Minutes)"
          yAxis = {
            left = {
              min = 0
              max = 480  # 8 hours max
            }
          }
          period = 300
        }
      },
      {
        type   = "metric"
        x      = 6
        y      = 0
        width  = 6
        height = 6
        properties = {
          metrics = [
            ["AWS/States", "ExecutionsSucceeded", "StateMachineArn", aws_sfn_state_machine.orchestrator.arn, { color = "#2ca02c" }],
            ["AWS/States", "ExecutionsFailed", "StateMachineArn", aws_sfn_state_machine.orchestrator.arn, { color = "#d62728" }],
            ["AWS/States", "ExecutionsAborted", "StateMachineArn", aws_sfn_state_machine.orchestrator.arn, { color = "#ff7f0e" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.region
          title   = "Execution Status Overview"
          period  = 300
        }
      },
      {
        type   = "metric" 
        x      = 12
        y      = 0
        width  = 6
        height = 6
        properties = {
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.pre_ec2.function_name, { stat = "Average" }],
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.post_ec2.function_name, { stat = "Average" }],
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.poll_ssm.function_name, { stat = "Average" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.region
          title   = "Lambda Function Performance"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 18
        y      = 0
        width  = 6
        height = 6
        properties = {
          metrics = [
            ["AWS/SNS", "NumberOfMessagesPublished", "TopicName", local.sns_topic_name],
            ["AWS/SNS", "NumberOfNotificationsFailed", "TopicName", local.sns_topic_name, { color = "#d62728" }]
          ]
          view    = "timeSeries"  
          stacked = false
          region  = var.region
          title   = "Notification Delivery"
          period  = 300
        }
      },

      # Error Analysis Row
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 8
        height = 6
        properties = {
          metrics = [
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.pre_ec2.function_name],
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.post_ec2.function_name], 
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.poll_ssm.function_name],
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.approval.function_name],
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.callback.function_name],
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.bedrock.function_name]
          ]
          view    = "timeSeries"
          stacked = true
          region  = var.region
          title   = "Lambda Function Errors"
          period  = 300
          annotations = {
            horizontal = [
              {
                value = 5
                label = "Error Threshold"
                fill  = "above"
              }
            ]
          }
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 6
        width  = 8
        height = 6
        properties = {
          metrics = [
            ["AWS/Lambda", "Throttles", "FunctionName", aws_lambda_function.pre_ec2.function_name],
            ["AWS/Lambda", "Throttles", "FunctionName", aws_lambda_function.post_ec2.function_name],
            ["AWS/Lambda", "Throttles", "FunctionName", aws_lambda_function.poll_ssm.function_name]
          ]
          view    = "timeSeries"
          stacked = true
          region  = var.region
          title   = "Lambda Function Throttles"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 6
        width  = 8
        height = 6
        properties = {
          metrics = [
            ["AWS/States", "ExecutionThrottled", "StateMachineArn", aws_sfn_state_machine.orchestrator.arn]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.region
          title   = "Step Functions Throttling"
          period  = 300
        }
      },

      # Resource Utilization Row
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 8
        height = 6
        properties = {
          metrics = [
            ["AWS/Lambda", "ConcurrentExecutions", "FunctionName", aws_lambda_function.pre_ec2.function_name],
            ["AWS/Lambda", "ConcurrentExecutions", "FunctionName", aws_lambda_function.post_ec2.function_name],
            ["AWS/Lambda", "ConcurrentExecutions", "FunctionName", aws_lambda_function.poll_ssm.function_name]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.region
          title   = "Lambda Concurrent Executions"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 12
        width  = 8
        height = 6
        properties = {
          metrics = [
            ["AWS/DynamoDB", "ConsumedReadCapacityUnits", "TableName", local.ddb_table_name],
            ["AWS/DynamoDB", "ConsumedWriteCapacityUnits", "TableName", local.ddb_table_name]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.region
          title   = "DynamoDB Capacity Usage"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 12
        width  = 8
        height = 6
        properties = {
          metrics = [
            ["AWS/S3", "BucketSizeBytes", "BucketName", local.s3_bucket_name, "StorageType", "StandardStorage"],
            ["AWS/S3", "NumberOfObjects", "BucketName", local.s3_bucket_name, "StorageType", "AllStorageTypes"]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.region
          title   = "S3 Storage Usage"
          period  = 86400  # Daily
        }
      },

      # SSM Command Status Row
      {
        type   = "metric"
        x      = 0
        y      = 18
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/SSM-RunCommand", "CommandsSucceeded", { stat = "Sum" }],
            ["AWS/SSM-RunCommand", "CommandsFailed", { stat = "Sum", color = "#d62728" }],
            ["AWS/SSM-RunCommand", "CommandsCancelled", { stat = "Sum", color = "#ff7f0e" }]
          ]
          view    = "timeSeries"
          stacked = true
          region  = var.region
          title   = "SSM Command Execution Status"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 18
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/SSM-RunCommand", "CommandsDeliveryTimedOut", { stat = "Sum" }],
            ["AWS/SSM-RunCommand", "CommandsExecutionTimedOut", { stat = "Sum" }]
          ]
          view    = "timeSeries"
          stacked = true
          region  = var.region
          title   = "SSM Command Timeouts"
          period  = 300
          annotations = {
            horizontal = [
              {
                value = 0
                label = "Zero Timeouts Goal"
              }
            ]
          }
        }
      },

      # Custom Application Metrics Row
      {
        type   = "metric"
        x      = 0
        y      = 24
        width  = 6
        height = 6
        properties = {
          metrics = [
            ["${var.name_prefix}/Patching", "InstancesPatched", { stat = "Sum" }],
            ["${var.name_prefix}/Patching", "InstancesFailed", { stat = "Sum", color = "#d62728" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.region
          title   = "Instances Processed"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 6
        y      = 24
        width  = 6
        height = 6
        properties = {
          metrics = [
            ["${var.name_prefix}/Patching", "PatchingWindowDuration", { stat = "Average" }],
            ["${var.name_prefix}/Patching", "PatchingWindowDuration", { stat = "Maximum" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.region
          title   = "Patching Window Duration"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 24
        width  = 6
        height = 6
        properties = {
          metrics = [
            ["${var.name_prefix}/Patching", "CriticalPatchesInstalled", { stat = "Sum" }],
            ["${var.name_prefix}/Patching", "SecurityPatchesInstalled", { stat = "Sum" }]
          ]
          view    = "timeSeries"
          stacked = true
          region  = var.region
          title   = "Patch Classifications"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 18
        y      = 24
        width  = 6
        height = 6
        properties = {
          metrics = [
            ["${var.name_prefix}/Patching", "RebootsRequired", { stat = "Sum" }],
            ["${var.name_prefix}/Patching", "RebootsCompleted", { stat = "Sum" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.region
          title   = "Reboot Statistics"
          period  = 300
        }
      },

      # Log Insights Widgets
      {
        type   = "log"
        x      = 0
        y      = 30
        width  = 12
        height = 6
        properties = {
          query = "SOURCE '/aws/lambda/${aws_lambda_function.pre_ec2.function_name}' | fields @timestamp, @message | filter @message like /ERROR/ | sort @timestamp desc | limit 20"
          region = var.region
          title  = "Recent Lambda Errors"
        }
      },
      {
        type   = "log"
        x      = 12
        y      = 30
        width  = 12
        height = 6
        properties = {
          query = "SOURCE '/aws/stepfunctions/${local.sfn_name}' | fields @timestamp, execution_arn, event_type | filter event_type like /Failed/ | sort @timestamp desc | limit 20"
          region = var.region
          title  = "Step Functions Failures"
        }
      }
    ]
  })
}

# Enhanced CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "high_lambda_errors" {
  alarm_name          = "${var.name_prefix}-high-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "High number of Lambda function errors"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.pre_ec2.function_name
  }

  tags = {
    Severity = "High"
    Component = "Lambda"
  }
}

resource "aws_cloudwatch_metric_alarm" "step_function_failures" {
  alarm_name          = "${var.name_prefix}-step-function-failures"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "ExecutionsFailed"
  namespace           = "AWS/States"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "Step Functions execution failed"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    StateMachineArn = aws_sfn_state_machine.orchestrator.arn
  }

  tags = {
    Severity = "Critical"
    Component = "StepFunctions"
  }
}

resource "aws_cloudwatch_metric_alarm" "long_execution_time" {
  alarm_name          = "${var.name_prefix}-long-execution-time"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "ExecutionTime"
  namespace           = "AWS/States"
  period              = "300"
  statistic           = "Maximum"
  threshold           = "14400000"  # 4 hours in milliseconds
  alarm_description   = "Patch execution taking too long"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    StateMachineArn = aws_sfn_state_machine.orchestrator.arn
  }

  tags = {
    Severity = "Medium"
    Component = "StepFunctions"
  }
}

# Custom Metrics for Application-Level Monitoring
resource "aws_cloudwatch_log_metric_filter" "instances_patched" {
  name           = "${var.name_prefix}-instances-patched"
  log_group_name = "/aws/lambda/${aws_lambda_function.post_ec2.function_name}"
  
  pattern = "[timestamp, requestId, level=\"INFO\", message=\"Patched instance\", instanceId, ...]"
  
  metric_transformation {
    name      = "InstancesPatched"
    namespace = "${var.name_prefix}/Patching"
    value     = "1"
    
    default_value = 0
  }
}

resource "aws_cloudwatch_log_metric_filter" "critical_patches" {
  name           = "${var.name_prefix}-critical-patches"
  log_group_name = "/aws/lambda/${aws_lambda_function.post_ec2.function_name}"
  
  pattern = "[timestamp, requestId, level=\"INFO\", message=\"Critical patch installed\", patchId, ...]"
  
  metric_transformation {
    name      = "CriticalPatchesInstalled"
    namespace = "${var.name_prefix}/Patching"
    value     = "1"
    
    default_value = 0
  }
}

# X-Ray Tracing for Distributed Tracing
resource "aws_xray_sampling_rule" "patching_sampling" {
  rule_name      = "${var.name_prefix}-patching-sampling"
  priority       = 9000
  version        = 1
  reservoir_size = 1
  fixed_rate     = 0.1
  
  url_path         = "*"
  host             = "*"
  http_method      = "*"
  resource_arn     = "*"
  service_name     = "${var.name_prefix}-patching"
  service_type     = "*"
}
