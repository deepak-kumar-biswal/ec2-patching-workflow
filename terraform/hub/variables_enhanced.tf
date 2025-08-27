# Enhanced variables for production-grade deployment
variable "region" {
  type        = string
  description = "AWS region for deployment"
  
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.region))
    error_message = "Region must be a valid AWS region format (e.g., us-east-1)."
  }
}

variable "orchestrator_account_id" {
  type        = string
  description = "12-digit AWS account ID for the hub/orchestrator"
  
  validation {
    condition     = can(regex("^[0-9]{12}$", var.orchestrator_account_id))
    error_message = "Account ID must be exactly 12 digits."
  }
}

variable "name_prefix" {
  type        = string
  description = "Short name to prefix resources (e.g., ec2patch)"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]*[a-zA-Z0-9]$", var.name_prefix)) && length(var.name_prefix) <= 20
    error_message = "Name prefix must start with a letter, contain only alphanumeric characters and hyphens, and be 20 characters or less."
  }
}

variable "environment" {
  type        = string
  description = "Environment name (dev, staging, production)"
  default     = "production"
  
  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "Environment must be one of: dev, staging, production."
  }
}

# Enhanced SNS configuration
variable "sns_email_subscriptions" {
  type        = list(string)
  default     = []
  description = "List of email addresses to subscribe to SNS notifications"
  
  validation {
    condition = alltrue([
      for email in var.sns_email_subscriptions : can(regex("^[\\w\\.-]+@[\\w\\.-]+\\.[a-zA-Z]{2,}$", email))
    ])
    error_message = "All email addresses must be valid email format."
  }
}

variable "sns_sms_subscriptions" {
  type        = list(string)
  default     = []
  description = "List of phone numbers to subscribe to SMS notifications (for critical alerts)"
  
  validation {
    condition = alltrue([
      for phone in var.sns_sms_subscriptions : can(regex("^\\+[1-9]\\d{1,14}$", phone))
    ])
    error_message = "All phone numbers must be in E.164 format (e.g., +1234567890)."
  }
}

variable "slack_webhook_url" {
  type        = string
  default     = ""
  description = "Slack webhook URL for notifications (optional)"
  sensitive   = true
}

variable "teams_webhook_url" {
  type        = string
  default     = ""
  description = "Microsoft Teams webhook URL for notifications (optional)"
  sensitive   = true
}

# Enhanced wave configuration
variable "wave_rules" {
  description = "Per-account wave schedules for EventBridge rules"
  type = list(object({
    name                = string
    description         = optional(string, "")
    schedule_expression = string
    accounts            = list(string)
    regions             = list(string)
    enabled             = optional(bool, true)
    retry_attempts      = optional(number, 3)
    timeout_minutes     = optional(number, 240)  # 4 hours default
    parallel_execution  = optional(bool, false)
    priority            = optional(number, 5)     # 1-10 scale
  }))
  default = []
  
  validation {
    condition = alltrue([
      for rule in var.wave_rules : 
      length(rule.name) > 0 && 
      length(rule.accounts) > 0 && 
      length(rule.regions) > 0 &&
      rule.priority >= 1 && rule.priority <= 10
    ])
    error_message = "Each wave rule must have a name, at least one account, at least one region, and priority between 1-10."
  }
}

# Enhanced Bedrock configuration
variable "bedrock_agent_id" {
  type        = string
  description = "Amazon Bedrock Agent ID for AI-powered analysis"
  
  validation {
    condition     = can(regex("^[A-Z0-9]{10}$", var.bedrock_agent_id))
    error_message = "Bedrock Agent ID must be 10 alphanumeric characters."
  }
}

variable "bedrock_agent_alias_id" {
  type        = string
  description = "Amazon Bedrock Agent Alias ID"
  
  validation {
    condition     = can(regex("^[A-Z0-9]{10}$", var.bedrock_agent_alias_id))
    error_message = "Bedrock Agent Alias ID must be 10 alphanumeric characters."
  }
}

variable "bedrock_model_id" {
  type        = string
  default     = "anthropic.claude-3-sonnet-20240229-v1:0"
  description = "Bedrock model ID for analysis"
}

# Enhanced operational configuration
variable "wave_pause_seconds" {
  type        = number
  default     = 300  # 5 minutes
  description = "Pause seconds between waves when invoked via Step Functions"
  
  validation {
    condition     = var.wave_pause_seconds >= 0 && var.wave_pause_seconds <= 3600
    error_message = "Wave pause seconds must be between 0 and 3600 (1 hour)."
  }
}

variable "abort_on_issues" {
  type        = bool
  default     = true
  description = "Whether to abort execution when critical issues are detected"
}

variable "max_concurrent_executions" {
  type        = number
  default     = 5
  description = "Maximum number of concurrent patch executions"
  
  validation {
    condition     = var.max_concurrent_executions >= 1 && var.max_concurrent_executions <= 20
    error_message = "Max concurrent executions must be between 1 and 20."
  }
}

variable "execution_timeout_minutes" {
  type        = number
  default     = 480  # 8 hours
  description = "Maximum execution time for the entire patching workflow"
  
  validation {
    condition     = var.execution_timeout_minutes >= 60 && var.execution_timeout_minutes <= 1440
    error_message = "Execution timeout must be between 60 minutes and 24 hours."
  }
}

# Enhanced patch configuration
variable "default_patch_group" {
  type        = string
  default     = "default"
  description = "Default patch group tag value"
}

variable "patch_classification_filter" {
  type        = list(string)
  default     = ["Critical", "Important", "Moderate"]
  description = "Patch classifications to include (Critical, Important, Moderate, Low)"
  
  validation {
    condition = alltrue([
      for classification in var.patch_classification_filter :
      contains(["Critical", "Important", "Moderate", "Low"], classification)
    ])
    error_message = "Patch classifications must be one of: Critical, Important, Moderate, Low."
  }
}

variable "reboot_option" {
  type        = string
  default     = "RebootIfNeeded"
  description = "Reboot option for patch installation"
  
  validation {
    condition     = contains(["RebootIfNeeded", "NoReboot"], var.reboot_option)
    error_message = "Reboot option must be either 'RebootIfNeeded' or 'NoReboot'."
  }
}

variable "max_concurrency_percentage" {
  type        = number
  default     = 25
  description = "Maximum percentage of instances to patch concurrently"
  
  validation {
    condition     = var.max_concurrency_percentage >= 1 && var.max_concurrency_percentage <= 100
    error_message = "Max concurrency percentage must be between 1 and 100."
  }
}

variable "max_error_percentage" {
  type        = number
  default     = 5
  description = "Maximum percentage of instances allowed to fail before aborting"
  
  validation {
    condition     = var.max_error_percentage >= 0 && var.max_error_percentage <= 50
    error_message = "Max error percentage must be between 0 and 50."
  }
}

# Enhanced security configuration
variable "kms_key_deletion_window" {
  type        = number
  default     = 7
  description = "KMS key deletion window in days"
  
  validation {
    condition     = var.kms_key_deletion_window >= 7 && var.kms_key_deletion_window <= 30
    error_message = "KMS key deletion window must be between 7 and 30 days."
  }
}

variable "enable_cloudtrail" {
  type        = bool
  default     = true
  description = "Enable CloudTrail for audit logging"
}

variable "cloudtrail_retention_days" {
  type        = number
  default     = 90
  description = "CloudTrail log retention in days"
  
  validation {
    condition     = var.cloudtrail_retention_days >= 30 && var.cloudtrail_retention_days <= 2557
    error_message = "CloudTrail retention must be between 30 days and 7 years."
  }
}

# Network configuration
variable "vpc_id" {
  type        = string
  default     = ""
  description = "VPC ID for Lambda functions (optional, uses default VPC if empty)"
}

variable "subnet_ids" {
  type        = list(string)
  default     = []
  description = "Subnet IDs for Lambda functions (required if vpc_id is specified)"
}

variable "enable_vpc_endpoints" {
  type        = bool
  default     = true
  description = "Enable VPC endpoints for secure communication"
}

# Monitoring and alerting configuration
variable "enable_detailed_monitoring" {
  type        = bool
  default     = true
  description = "Enable detailed CloudWatch monitoring"
}

variable "metric_retention_days" {
  type        = number
  default     = 30
  description = "CloudWatch metrics retention in days"
}

variable "log_retention_days" {
  type        = number
  default     = 30
  description = "CloudWatch logs retention in days"
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch Logs retention value."
  }
}

variable "enable_xray_tracing" {
  type        = bool
  default     = true
  description = "Enable AWS X-Ray tracing"
}

variable "xray_sampling_rate" {
  type        = number
  default     = 0.1
  description = "X-Ray sampling rate (0.0 to 1.0)"
  
  validation {
    condition     = var.xray_sampling_rate >= 0.0 && var.xray_sampling_rate <= 1.0
    error_message = "X-Ray sampling rate must be between 0.0 and 1.0."
  }
}

# Data retention and lifecycle
variable "s3_lifecycle_rules" {
  type = object({
    snapshot_retention_days      = optional(number, 90)
    report_retention_days        = optional(number, 365)
    audit_log_retention_days     = optional(number, 2557)  # 7 years
    transition_to_ia_days        = optional(number, 30)
    transition_to_glacier_days   = optional(number, 90)
    transition_to_deep_archive_days = optional(number, 365)
  })
  default = {}
  description = "S3 lifecycle configuration for data retention"
}

# Cost optimization
variable "lambda_reserved_concurrency" {
  type        = number
  default     = -1  # No limit
  description = "Reserved concurrency for Lambda functions (-1 for no limit)"
  
  validation {
    condition     = var.lambda_reserved_concurrency >= -1
    error_message = "Reserved concurrency must be -1 (no limit) or a positive number."
  }
}

variable "dynamodb_backup_retention_days" {
  type        = number
  default     = 7
  description = "DynamoDB point-in-time recovery retention in days"
  
  validation {
    condition     = var.dynamodb_backup_retention_days >= 1 && var.dynamodb_backup_retention_days <= 35
    error_message = "DynamoDB backup retention must be between 1 and 35 days."
  }
}

# Compliance and governance
variable "compliance_framework" {
  type        = string
  default     = "SOC2"
  description = "Compliance framework (SOC2, ISO27001, NIST, PCI-DSS)"
  
  validation {
    condition     = contains(["SOC2", "ISO27001", "NIST", "PCI-DSS", "CUSTOM"], var.compliance_framework)
    error_message = "Compliance framework must be one of: SOC2, ISO27001, NIST, PCI-DSS, CUSTOM."
  }
}

variable "data_classification" {
  type        = string
  default     = "Internal"
  description = "Data classification level (Public, Internal, Confidential, Restricted)"
  
  validation {
    condition     = contains(["Public", "Internal", "Confidential", "Restricted"], var.data_classification)
    error_message = "Data classification must be one of: Public, Internal, Confidential, Restricted."
  }
}

# Resource tagging strategy
variable "additional_tags" {
  type        = map(string)
  default     = {}
  description = "Additional tags to apply to all resources"
}

variable "cost_center" {
  type        = string
  default     = ""
  description = "Cost center for resource billing"
}

variable "owner" {
  type        = string
  default     = ""
  description = "Resource owner (email or team name)"
}

variable "business_unit" {
  type        = string
  default     = ""
  description = "Business unit responsible for the resources"
}

# Disaster recovery configuration
variable "enable_cross_region_backup" {
  type        = bool
  default     = false
  description = "Enable cross-region backup for disaster recovery"
}

variable "backup_region" {
  type        = string
  default     = ""
  description = "Secondary region for disaster recovery backups"
}

variable "rpo_hours" {
  type        = number
  default     = 24
  description = "Recovery Point Objective in hours"
  
  validation {
    condition     = var.rpo_hours >= 1 && var.rpo_hours <= 168
    error_message = "RPO must be between 1 hour and 7 days."
  }
}

variable "rto_hours" {
  type        = number
  default     = 4
  description = "Recovery Time Objective in hours"
  
  validation {
    condition     = var.rto_hours >= 1 && var.rto_hours <= 72
    error_message = "RTO must be between 1 hour and 3 days."
  }
}

# Local values for computed configurations
locals {
  common_tags = merge(
    {
      Environment    = var.environment
      ManagedBy     = "Terraform"
      Project       = "EC2Patching"
      Owner         = var.owner
      CostCenter    = var.cost_center
      BusinessUnit  = var.business_unit
      DataClass     = var.data_classification
      Compliance    = var.compliance_framework
    },
    var.additional_tags
  )
  
  # Resource naming convention
  resource_name_prefix = "${var.name_prefix}-${var.environment}"
  
  # S3 bucket names (must be globally unique)
  s3_bucket_name     = "${var.name_prefix}-${var.orchestrator_account_id}-${var.environment}-snapshots"
  audit_bucket_name  = "${var.name_prefix}-${var.orchestrator_account_id}-${var.environment}-audit"
  
  # Other resource names
  ddb_table_name     = "${local.resource_name_prefix}-PatchRuns"
  sns_topic_name     = "${local.resource_name_prefix}-PatchAlerts"
  sfn_name           = "${local.resource_name_prefix}-EC2PatchOrchestrator"
  kms_key_alias      = "alias/${local.resource_name_prefix}-patching-encryption"
  
  # Lambda function names
  lambda_functions = {
    pre_inventory    = "${local.resource_name_prefix}-PreEC2Inventory"
    post_verify      = "${local.resource_name_prefix}-PostEC2Verify"
    poll_ssm         = "${local.resource_name_prefix}-PollSsmCommand"
    bedrock_analyze  = "${local.resource_name_prefix}-AnalyzeWithBedrock"
    send_approval    = "${local.resource_name_prefix}-SendApprovalRequest"
    handle_callback  = "${local.resource_name_prefix}-ApprovalCallback"
    validate_input   = "${local.resource_name_prefix}-ValidateInput"
    check_prereqs    = "${local.resource_name_prefix}-CheckPrerequisites"
    monitor_command  = "${local.resource_name_prefix}-MonitorCommand"
    generate_report  = "${local.resource_name_prefix}-GenerateReport"
    final_report     = "${local.resource_name_prefix}-FinalReport"
    initialize_exec  = "${local.resource_name_prefix}-InitializeExecution"
  }
}
