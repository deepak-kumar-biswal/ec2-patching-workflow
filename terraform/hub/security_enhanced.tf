# Enhanced Security Configuration
# KMS Key for encryption of sensitive data
resource "aws_kms_key" "patching_encryption" {
  description             = "KMS key for EC2 patching orchestrator encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM Root Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.orchestrator_account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow Lambda Functions"
        Effect = "Allow"
        Principal = {
          AWS = [
            aws_iam_role.lambda_exec.arn,
            aws_iam_role.sfn_role.arn
          ]
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name        = "${var.name_prefix}-patching-encryption"
    Purpose     = "Patching"
    Environment = var.environment
  }
}

resource "aws_kms_alias" "patching_encryption" {
  name          = "alias/${var.name_prefix}-patching-encryption"
  target_key_id = aws_kms_key.patching_encryption.key_id
}

# Enhanced S3 bucket with security controls
resource "aws_s3_bucket" "snapshots_secure" {
  bucket        = local.s3_bucket_name
  force_destroy = false

  tags = {
    Name        = local.s3_bucket_name
    Purpose     = "Patching Snapshots and Reports"
    Environment = var.environment
    DataClass   = "Internal"
  }
}

# S3 Bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "snapshots_encryption" {
  bucket = aws_s3_bucket.snapshots_secure.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.patching_encryption.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

# S3 Bucket versioning
resource "aws_s3_bucket_versioning" "snapshots_versioning" {
  bucket = aws_s3_bucket.snapshots_secure.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 Bucket public access block
resource "aws_s3_bucket_public_access_block" "snapshots_pab" {
  bucket = aws_s3_bucket.snapshots_secure.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 Bucket lifecycle management
resource "aws_s3_bucket_lifecycle_configuration" "snapshots_lifecycle" {
  bucket = aws_s3_bucket.snapshots_secure.id

  rule {
    id     = "patching_data_lifecycle"
    status = "Enabled"

    expiration {
      days = 90  # Keep patch data for 90 days
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# S3 Bucket notification for security monitoring
resource "aws_s3_bucket_notification" "snapshots_notification" {
  bucket = aws_s3_bucket.snapshots_secure.id

  topic {
    topic_arn = aws_sns_topic.security_alerts.arn
    events    = ["s3:ObjectCreated:*", "s3:ObjectRemoved:*"]
  }

  depends_on = [aws_sns_topic_policy.security_alerts_policy]
}

# DynamoDB with encryption and point-in-time recovery
resource "aws_dynamodb_table" "patchruns_secure" {
  name                        = local.ddb_table_name
  billing_mode                = "PAY_PER_REQUEST"
  hash_key                    = "scope"
  range_key                   = "id"
  deletion_protection_enabled = true
  
  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.patching_encryption.arn
  }

  attribute {
    name = "scope"
    type = "S"
  }

  attribute {
    name = "id"
    type = "S"
  }

  # Global Secondary Index for queries by timestamp
  global_secondary_index {
    name     = "TimestampIndex"
    hash_key = "scope"
    range_key = "timestamp"
    
    projection_type = "ALL"
  }

  attribute {
    name = "timestamp"
    type = "S"
  }

  tags = {
    Name        = local.ddb_table_name
    Purpose     = "Patching State"
    Environment = var.environment
    DataClass   = "Internal"
  }
}

# Enhanced IAM roles with least privilege
data "aws_iam_policy_document" "lambda_assume_enhanced" {
  statement {
    actions = ["sts:AssumeRole"]
    
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.region]
    }
  }
}

resource "aws_iam_role" "lambda_exec_enhanced" {
  name               = "${var.name_prefix}-lambda-exec-enhanced"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_enhanced.json
  path               = "/patching/"
  
  tags = {
    Purpose = "Patching Lambda Execution"
    ManagedBy = "Terraform"
  }
}

# Granular permissions policy
resource "aws_iam_policy" "lambda_permissions_enhanced" {
  name        = "${var.name_prefix}-lambda-permissions-enhanced"
  path        = "/patching/"
  description = "Enhanced permissions for patching Lambda functions"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # S3 permissions with resource restrictions
      {
        Sid    = "S3PatchingBucketAccess"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.snapshots_secure.arn,
          "${aws_s3_bucket.snapshots_secure.arn}/*"
        ]
        Condition = {
          StringEquals = {
            "s3:x-amz-server-side-encryption" = "aws:kms"
          }
        }
      },
      # DynamoDB permissions with resource restrictions
      {
        Sid    = "DynamoDBPatchingAccess"
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:BatchGetItem"
        ]
        Resource = [
          aws_dynamodb_table.patchruns_secure.arn,
          "${aws_dynamodb_table.patchruns_secure.arn}/index/*"
        ]
      },
      # SNS permissions
      {
        Sid    = "SNSPublishAccess"
        Effect = "Allow"
        Action = ["sns:Publish"]
        Resource = [
          aws_sns_topic.alerts.arn,
          aws_sns_topic.security_alerts.arn
        ]
      },
      # Cross-account assume role with conditions
      {
        Sid    = "AssumeSpokePatchRole"
        Effect = "Allow"
        Action = ["sts:AssumeRole"]
        Resource = "arn:aws:iam::*:role/PatchExecRole"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.region
          }
          StringLike = {
            "aws:userid" = "*:${var.name_prefix}-*"
          }
        }
      },
      # Bedrock permissions with resource restrictions
      {
        Sid    = "BedrockAgentAccess"
        Effect = "Allow"
        Action = [
          "bedrock:InvokeAgent",
          "bedrock:GetAgent",
          "bedrock:GetAgentAlias"
        ]
        Resource = [
          "arn:aws:bedrock:${var.region}:${var.orchestrator_account_id}:agent/${var.bedrock_agent_id}",
          "arn:aws:bedrock:${var.region}:${var.orchestrator_account_id}:agent-alias/${var.bedrock_agent_id}/${var.bedrock_agent_alias_id}"
        ]
      },
      # KMS permissions
      {
        Sid    = "KMSAccess"
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = [aws_kms_key.patching_encryption.arn]
      },
      # CloudWatch permissions
      {
        Sid    = "CloudWatchAccess"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "cloudwatch:PutMetricData"
        ]
        Resource = [
          "arn:aws:logs:${var.region}:${var.orchestrator_account_id}:log-group:/aws/lambda/${var.name_prefix}-*",
          "arn:aws:cloudwatch:${var.region}:${var.orchestrator_account_id}:metric/${var.name_prefix}/*"
        ]
      },
      # X-Ray tracing
      {
        Sid    = "XRayAccess"
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ]
        Resource = "*"
      }
    ]
  })
}

# Enhanced Step Functions role
data "aws_iam_policy_document" "sfn_assume_enhanced" {
  statement {
    actions = ["sts:AssumeRole"]
    
    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
    
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.region]
    }
  }
}

resource "aws_iam_role" "sfn_role_enhanced" {
  name               = "${var.name_prefix}-sfn-role-enhanced"
  assume_role_policy = data.aws_iam_policy_document.sfn_assume_enhanced.json
  path               = "/patching/"
  
  tags = {
    Purpose = "Patching Step Functions Execution"
    ManagedBy = "Terraform"
  }
}

resource "aws_iam_policy" "sfn_permissions_enhanced" {
  name        = "${var.name_prefix}-sfn-permissions-enhanced"
  path        = "/patching/"
  description = "Enhanced permissions for patching Step Functions"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Lambda invocation permissions
      {
        Sid    = "LambdaInvoke"
        Effect = "Allow"
        Action = ["lambda:InvokeFunction"]
        Resource = [
          "${aws_lambda_function.pre_ec2.arn}:*",
          "${aws_lambda_function.post_ec2.arn}:*",
          "${aws_lambda_function.poll_ssm.arn}:*",
          "${aws_lambda_function.bedrock.arn}:*",
          "${aws_lambda_function.approval.arn}:*",
          aws_lambda_function.pre_ec2.arn,
          aws_lambda_function.post_ec2.arn,
          aws_lambda_function.poll_ssm.arn,
          aws_lambda_function.bedrock.arn,
          aws_lambda_function.approval.arn
        ]
      },
      # SNS publishing
      {
        Sid    = "SNSPublish"
        Effect = "Allow"
        Action = ["sns:Publish"]
        Resource = [
          aws_sns_topic.alerts.arn,
          aws_sns_topic.security_alerts.arn
        ]
      },
      # SSM permissions for patch execution
      {
        Sid    = "SSMPatchExecution"
        Effect = "Allow"
        Action = [
          "ssm:SendCommand",
          "ssm:GetCommandInvocation",
          "ssm:ListCommandInvocations",
          "ssm:ListCommands",
          "ssm:DescribeInstanceInformation"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "ssm:resourceTag/PatchGroup" = var.default_patch_group
          }
        }
      },
      # Cross-account assume role
      {
        Sid    = "AssumeSpokePatchRole"
        Effect = "Allow"
        Action = ["sts:AssumeRole"]
        Resource = "arn:aws:iam::*:role/PatchExecRole"
        Condition = {
          StringLike = {
            "aws:userid" = "*:${var.name_prefix}-*"
          }
        }
      },
      # X-Ray tracing
      {
        Sid    = "XRayAccess"
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords",
          "xray:GetTraceGraph",
          "xray:GetTraceSummaries"
        ]
        Resource = "*"
      }
    ]
  })
}

# Security alerts SNS topic
resource "aws_sns_topic" "security_alerts" {
  name              = "${var.name_prefix}-security-alerts"
  kms_master_key_id = aws_kms_key.patching_encryption.key_id
  
  tags = {
    Purpose = "Security Alerts"
    ManagedBy = "Terraform"
  }
}

resource "aws_sns_topic_policy" "security_alerts_policy" {
  arn = aws_sns_topic.security_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowS3BucketNotification"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.security_alerts.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = var.orchestrator_account_id
          }
          ArnEquals = {
            "aws:SourceArn" = aws_s3_bucket.snapshots_secure.arn
          }
        }
      }
    ]
  })
}

# VPC Endpoints for secure communication (optional but recommended)
data "aws_vpc" "main" {
  count   = var.vpc_id != "" ? 1 : 0
  id      = var.vpc_id
}

data "aws_subnets" "private" {
  count = var.vpc_id != "" ? 1 : 0
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
  
  tags = {
    Type = "Private"
  }
}

# VPC Endpoint for S3
resource "aws_vpc_endpoint" "s3" {
  count           = var.vpc_id != "" ? 1 : 0
  vpc_id          = var.vpc_id
  service_name    = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  
  tags = {
    Name = "${var.name_prefix}-s3-endpoint"
    Purpose = "Patching S3 Access"
  }
}

# VPC Endpoint for DynamoDB
resource "aws_vpc_endpoint" "dynamodb" {
  count           = var.vpc_id != "" ? 1 : 0
  vpc_id          = var.vpc_id
  service_name    = "com.amazonaws.${var.region}.dynamodb"
  vpc_endpoint_type = "Gateway"
  
  tags = {
    Name = "${var.name_prefix}-dynamodb-endpoint"
    Purpose = "Patching DynamoDB Access"
  }
}

# Security Group for Lambda functions (if deployed in VPC)
resource "aws_security_group" "lambda_sg" {
  count       = var.vpc_id != "" ? 1 : 0
  name        = "${var.name_prefix}-lambda-sg"
  description = "Security group for patching Lambda functions"
  vpc_id      = var.vpc_id

  # Outbound HTTPS for AWS API calls
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS outbound for AWS APIs"
  }

  # Outbound HTTP for package downloads (if needed)
  egress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP outbound for package downloads"
  }

  tags = {
    Name = "${var.name_prefix}-lambda-sg"
    Purpose = "Patching Lambda Security"
  }
}

# CloudTrail for audit logging
resource "aws_cloudtrail" "patching_audit" {
  name           = "${var.name_prefix}-audit-trail"
  s3_bucket_name = aws_s3_bucket.audit_logs.bucket
  
  kms_key_id                = aws_kms_key.patching_encryption.arn
  include_global_service_events = true
  is_multi_region_trail     = false
  enable_logging           = true
  
  event_selector {
    read_write_type           = "All"
    include_management_events = true
    
    data_resource {
      type   = "AWS::S3::Object"
      values = ["${aws_s3_bucket.snapshots_secure.arn}/*"]
    }
    
    data_resource {
      type   = "AWS::DynamoDB::Table"
      values = [aws_dynamodb_table.patchruns_secure.arn]
    }
  }
  
  tags = {
    Purpose = "Patching Audit"
    ManagedBy = "Terraform"
  }
}

# Separate S3 bucket for audit logs
resource "aws_s3_bucket" "audit_logs" {
  bucket        = "${var.name_prefix}-${var.orchestrator_account_id}-audit-logs"
  force_destroy = false

  tags = {
    Name        = "${var.name_prefix}-audit-logs"
    Purpose     = "CloudTrail Audit Logs"
    Environment = var.environment
    DataClass   = "Confidential"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "audit_logs_encryption" {
  bucket = aws_s3_bucket.audit_logs.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.patching_encryption.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "audit_logs_pab" {
  bucket = aws_s3_bucket.audit_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket policy for CloudTrail
resource "aws_s3_bucket_policy" "audit_logs_policy" {
  bucket = aws_s3_bucket.audit_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.audit_logs.arn
        Condition = {
          StringEquals = {
            "aws:SourceArn" = "arn:aws:cloudtrail:${var.region}:${var.orchestrator_account_id}:trail/${var.name_prefix}-audit-trail"
          }
        }
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.audit_logs.arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
            "aws:SourceArn" = "arn:aws:cloudtrail:${var.region}:${var.orchestrator_account_id}:trail/${var.name_prefix}-audit-trail"
          }
        }
      }
    ]
  })
}
