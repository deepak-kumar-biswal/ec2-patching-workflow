# Enhanced Step Functions definition with comprehensive error handling
locals {
  sfn_definition_enhanced = jsonencode({
    Comment = "EC2 patch orchestrator with comprehensive error handling and monitoring",
    StartAt = "InitializeExecution",
    States = {
      
      # Initialize execution with metadata
      InitializeExecution = {
        Type = "Task",
        Resource = "arn:aws:states:::lambda:invoke",
        Parameters = {
          FunctionName = "${aws_lambda_function.initialize_execution.function_name}",
          Payload = {
            executionId.$  = "$$.Execution.Name",
            startTime.$    = "$$.Execution.StartTime",
            inputData.$    = "$"
          }
        },
        ResultPath = "$.execution",
        Retry = [
          {
            ErrorEquals = ["Lambda.ServiceException", "Lambda.AWSLambdaException", "Lambda.SdkClientException"],
            IntervalSeconds = 2,
            MaxAttempts = 3,
            BackoffRate = 2.0
          }
        ],
        Catch = [
          {
            ErrorEquals = ["States.TaskFailed"],
            Next = "HandleInitializationFailure",
            ResultPath = "$.error"
          }
        ],
        Next = "ValidateInput"
      },

      # Input validation
      ValidateInput = {
        Type = "Task",
        Resource = "arn:aws:states:::lambda:invoke",
        Parameters = {
          FunctionName = "${aws_lambda_function.validate_input.function_name}",
          Payload.$  = "$"
        },
        ResultPath = "$.validation",
        Retry = [
          {
            ErrorEquals = ["Lambda.ServiceException", "Lambda.AWSLambdaException"],
            IntervalSeconds = 1,
            MaxAttempts = 2,
            BackoffRate = 1.5
          }
        ],
        Catch = [
          {
            ErrorEquals = ["ValidationError", "States.TaskFailed"],
            Next = "HandleValidationFailure",
            ResultPath = "$.error"
          }
        ],
        Next = "CheckPrerequisites"
      },

      # Check prerequisites (SSM Agent status, patch groups, etc.)
      CheckPrerequisites = {
        Type = "Task",
        Resource = "arn:aws:states:::lambda:invoke",
        Parameters = {
          FunctionName = "${aws_lambda_function.check_prerequisites.function_name}",
          Payload.$  = "$"
        },
        ResultPath = "$.prerequisites",
        TimeoutSeconds = 300,
        Retry = [
          {
            ErrorEquals = ["Lambda.ServiceException", "Lambda.AWSLambdaException"],
            IntervalSeconds = 5,
            MaxAttempts = 3,
            BackoffRate = 2.0
          }
        ],
        Catch = [
          {
            ErrorEquals = ["PrerequisiteError", "States.TaskFailed"],
            Next = "HandlePrerequisiteFailure",
            ResultPath = "$.error"
          }
        ],
        Next = "ManualApproval"
      },

      # Enhanced manual approval with timeout and escalation
      ManualApproval = {
        Type = "Task",
        Resource = "arn:aws:states:::lambda:invoke.waitForTaskToken",
        Parameters = {
          FunctionName = aws_lambda_function.approval.function_name,
          Payload = {
            taskToken.$     = "$$.Task.Token",
            subject         = "🚨 EC2 Patch Approval Required - Production Environment",
            executionId.$   = "$$.Execution.Name",
            accountWaves.$  = "$.accountWaves",
            estimatedDuration = 120,  # minutes
            details.$       = "$"
          }
        },
        ResultPath = "$.approval",
        TimeoutSeconds = 3600,  # 1 hour timeout
        Catch = [
          {
            ErrorEquals = ["States.Timeout"],
            Next = "HandleApprovalTimeout",
            ResultPath = "$.error"
          },
          {
            ErrorEquals = ["ApprovalRejected"],
            Next = "HandleApprovalRejection",
            ResultPath = "$.error"
          }
        ],
        Next = "NotifyApprovalSuccess"
      },

      # Notify successful approval
      NotifyApprovalSuccess = {
        Type = "Task",
        Resource = "arn:aws:states:::sns:publish",
        Parameters = {
          TopicArn = aws_sns_topic.alerts.arn,
          Subject = "✅ EC2 Patching Approved - Starting Execution",
          Message = {
            executionId.$   = "$$.Execution.Name",
            approvedBy.$    = "$.approval.approvedBy",
            approvedAt.$    = "$.approval.approvedAt",
            accountCount.$  = "$.accountWaves[*].accounts[*] | length(@)"
          }
        },
        ResultPath = null,
        Next = "WaveMap"
      },

      # Enhanced wave processing with parallel execution monitoring
      WaveMap = {
        Type = "Map",
        ItemsPath = "$.accountWaves",
        MaxConcurrency = 1,
        ResultPath = "$.waveResults",
        Iterator = {
          StartAt = "PreWaveChecks",
          States = {
            
            # Pre-wave validation and inventory
            PreWaveChecks = {
              Type = "Parallel",
              ResultPath = "$.preWave",
              Branches = [
                {
                  StartAt = "PreWaveInventory",
                  States = {
                    PreWaveInventory = {
                      Type = "Task",
                      Resource = "arn:aws:states:::lambda:invoke",
                      Parameters = {
                        FunctionName = aws_lambda_function.pre_ec2.function_name,
                        Payload = {
                          accounts.$  = "$.accounts",
                          regions.$   = "$.regions",
                          waveIndex.$ = "$$.Map.Item.Index"
                        }
                      },
                      ResultPath = "$.inventory",
                      Retry = [
                        {
                          ErrorEquals = ["Lambda.ServiceException", "Lambda.AWSLambdaException"],
                          IntervalSeconds = 10,
                          MaxAttempts = 3,
                          BackoffRate = 2.0
                        }
                      ],
                      End = true
                    }
                  }
                },
                {
                  StartAt = "ValidateWaveTargets",
                  States = {
                    ValidateWaveTargets = {
                      Type = "Task",
                      Resource = "arn:aws:states:::lambda:invoke",
                      Parameters = {
                        FunctionName = "${aws_lambda_function.validate_wave_targets.function_name}",
                        Payload = {
                          accounts.$  = "$.accounts",
                          regions.$   = "$.regions",
                          tagKey.$    = "$.tagKey",
                          tagValue.$  = "$.tagValue"
                        }
                      },
                      Retry = [
                        {
                          ErrorEquals = ["Lambda.ServiceException"],
                          IntervalSeconds = 5,
                          MaxAttempts = 2
                        }
                      ],
                      End = true
                    }
                  }
                }
              ],
              Catch = [
                {
                  ErrorEquals = ["States.TaskFailed"],
                  Next = "HandlePreWaveFailure",
                  ResultPath = "$.error"
                }
              ],
              Next = "EvaluateWaveReadiness"
            },

            # Evaluate if wave is ready to proceed
            EvaluateWaveReadiness = {
              Type = "Choice",
              Choices = [
                {
                  Variable = "$.preWave[0].inventory.Payload.success",
                  BooleanEquals = false,
                  Next = "HandlePreWaveFailure"
                },
                {
                  Variable = "$.preWave[1].Payload.validTargets",
                  BooleanEquals = false,
                  Next = "HandleInvalidTargets"
                }
              ],
              Default = "ProcessAccountsInWave"
            },

            # Process accounts with enhanced error handling
            ProcessAccountsInWave = {
              Type = "Map",
              ItemsPath = "$.accounts",
              MaxConcurrency = 2,  # Limit concurrency to prevent overwhelming
              Parameters = {
                accountId.$     = "$$.Map.Item.Value",
                regions.$       = "$.regions",
                tagKey.$        = "$.tagKey", 
                tagValue.$      = "$.tagValue",
                roleArn.$       = "States.Format('arn:aws:iam::{}:role/PatchExecRole', $$.Map.Item.Value)",
                waveIndex.$     = "$$.Map.Item.Index",
                executionId.$   = "$$.Execution.Name"
              },
              Iterator = {
                StartAt = "ProcessRegions",
                States = {
                  ProcessRegions = {
                    Type = "Map",
                    ItemsPath = "$.regions",
                    MaxConcurrency = 1,
                    Parameters = {
                      accountId.$     = "$.accountId",
                      region.$        = "$$.Map.Item.Value",
                      tagKey.$        = "$.tagKey",
                      tagValue.$      = "$.tagValue", 
                      roleArn.$       = "$.roleArn",
                      executionId.$   = "$.executionId"
                    },
                    Iterator = {
                      StartAt = "SendPatchCommandWithRetry",
                      States = {
                        SendPatchCommandWithRetry = {
                          Type = "Task",
                          Resource = "arn:aws:states:::aws-sdk:ssm:sendCommand",
                          Parameters = {
                            DocumentName = "AWS-RunPatchBaseline",
                            Targets = [
                              {
                                Key.$       = "States.Format('tag:{}', $.tagKey)",
                                Values.$    = "States.Array($.tagValue)"
                              }
                            ],
                            MaxConcurrency = "25%",  # More conservative
                            MaxErrors = "5%",        # Percentage-based
                            TimeoutSeconds = 7200,   # 2 hours
                            Parameters = {
                              Operation = ["Install"],
                              RebootOption = ["RebootIfNeeded"]
                            },
                            NotificationConfig = {
                              NotificationArn = aws_sns_topic.alerts.arn,
                              NotificationEvents = ["Failed", "Success"],
                              NotificationType = "Command"
                            }
                          },
                          Credentials = { RoleArn.$ = "$.roleArn" },
                          ResultPath = "$.command",
                          Retry = [
                            {
                              ErrorEquals = ["SSM.InvalidRole", "SSM.AccessDenied"],
                              IntervalSeconds = 30,
                              MaxAttempts = 3,
                              BackoffRate = 2.0
                            },
                            {
                              ErrorEquals = ["SSM.ThrottlingException"],
                              IntervalSeconds = 60,
                              MaxAttempts = 5,
                              BackoffRate = 2.0
                            }
                          ],
                          Catch = [
                            {
                              ErrorEquals = ["States.TaskFailed"],
                              Next = "HandleCommandFailure",
                              ResultPath = "$.error"
                            }
                          ],
                          Next = "MonitorCommandExecution"
                        },

                        # Enhanced command monitoring with detailed status tracking
                        MonitorCommandExecution = {
                          Type = "Task",
                          Resource = "arn:aws:states:::lambda:invoke",
                          Parameters = {
                            FunctionName = "${aws_lambda_function.monitor_command.function_name}",
                            Payload.$  = "$"
                          },
                          ResultPath = "$.monitoring",
                          TimeoutSeconds = 7200,  # 2 hours max
                          Retry = [
                            {
                              ErrorEquals = ["Lambda.ServiceException", "MonitoringTimeout"],
                              IntervalSeconds = 30,
                              MaxAttempts = 3
                            }
                          ],
                          Catch = [
                            {
                              ErrorEquals = ["States.TaskFailed", "CommandTimeout"],
                              Next = "HandleMonitoringFailure",
                              ResultPath = "$.error"
                            }
                          ],
                          Next = "EvaluateCommandResults"
                        },

                        # Evaluate command execution results
                        EvaluateCommandResults = {
                          Type = "Choice",
                          Choices = [
                            {
                              Variable = "$.monitoring.Payload.status",
                              StringEquals = "SUCCESS",
                              Next = "RegionSuccess"
                            },
                            {
                              Variable = "$.monitoring.Payload.status", 
                              StringEquals = "PARTIAL_SUCCESS",
                              Next = "HandlePartialSuccess"
                            }
                          ],
                          Default = "HandleCommandFailure"
                        },

                        HandlePartialSuccess = {
                          Type = "Task",
                          Resource = "arn:aws:states:::sns:publish",
                          Parameters = {
                            TopicArn = aws_sns_topic.alerts.arn,
                            Subject = "⚠️ Partial Success in Patch Execution",
                            Message = {
                              account.$    = "$.accountId",
                              region.$     = "$.region", 
                              details.$    = "$.monitoring.Payload",
                              executionId.$ = "$.executionId"
                            }
                          },
                          Next = "RegionSuccess"
                        },

                        HandleCommandFailure = {
                          Type = "Task",
                          Resource = "arn:aws:states:::sns:publish", 
                          Parameters = {
                            TopicArn = aws_sns_topic.alerts.arn,
                            Subject = "❌ Command Execution Failed",
                            Message = {
                              account.$    = "$.accountId",
                              region.$     = "$.region",
                              error.$      = "$.error",
                              executionId.$ = "$.executionId"
                            }
                          },
                          Next = "RegionFailed"
                        },

                        HandleMonitoringFailure = {
                          Type = "Task", 
                          Resource = "arn:aws:states:::sns:publish",
                          Parameters = {
                            TopicArn = aws_sns_topic.alerts.arn,
                            Subject = "❌ Command Monitoring Failed",
                            Message = {
                              account.$    = "$.accountId",
                              region.$     = "$.region",
                              error.$      = "$.error",
                              executionId.$ = "$.executionId"
                            }
                          },
                          Next = "RegionFailed"
                        },

                        RegionSuccess = {
                          Type = "Succeed"
                        },

                        RegionFailed = {
                          Type = "Fail",
                          Cause = "Region processing failed"
                        }
                      }
                    },
                    ResultPath = "$.regionResults",
                    Next = "AccountComplete"
                  },
                  AccountComplete = {
                    Type = "Succeed"
                  }
                }
              },
              ResultPath = "$.accountResults",
              Next = "PostWaveAnalysis"
            },

            # Comprehensive post-wave analysis
            PostWaveAnalysis = {
              Type = "Parallel",
              ResultPath = "$.postWave",
              Branches = [
                {
                  StartAt = "PostWaveVerify",
                  States = {
                    PostWaveVerify = {
                      Type = "Task",
                      Resource = "arn:aws:states:::lambda:invoke",
                      Parameters = {
                        FunctionName = aws_lambda_function.post_ec2.function_name,
                        Payload = {
                          accounts.$  = "$.accounts",
                          regions.$   = "$.regions",
                          waveIndex.$ = "$$.Map.Item.Index"
                        }
                      },
                      Retry = [
                        {
                          ErrorEquals = ["Lambda.ServiceException"],
                          IntervalSeconds = 10,
                          MaxAttempts = 3
                        }
                      ],
                      End = true
                    }
                  }
                },
                {
                  StartAt = "GenerateWaveReport",
                  States = {
                    GenerateWaveReport = {
                      Type = "Task",
                      Resource = "arn:aws:states:::lambda:invoke",
                      Parameters = {
                        FunctionName = "${aws_lambda_function.generate_report.function_name}",
                        Payload = {
                          waveResults.$   = "$.accountResults",
                          accounts.$      = "$.accounts", 
                          regions.$       = "$.regions",
                          waveIndex.$     = "$$.Map.Item.Index"
                        }
                      },
                      End = true
                    }
                  }
                }
              ],
              Next = "EvaluateWaveResults"
            },

            # Evaluate wave results and decide next steps
            EvaluateWaveResults = {
              Type = "Choice",
              Choices = [
                {
                  And = [
                    {
                      Variable = "$.postWave[0].Payload.hasIssues",
                      BooleanEquals = true
                    },
                    {
                      Variable = "$.abortOnIssues", 
                      BooleanEquals = true
                    }
                  ],
                  Next = "AnalyzeWaveIssues"
                },
                {
                  Variable = "$.postWave[0].Payload.hasIssues",
                  BooleanEquals = true,
                  Next = "HandleNonCriticalIssues"
                }
              ],
              Default = "WavePause"
            },

            # AI-powered issue analysis
            AnalyzeWaveIssues = {
              Type = "Task",
              Resource = "arn:aws:states:::lambda:invoke",
              Parameters = {
                FunctionName = aws_lambda_function.bedrock.function_name,
                Payload = {
                  issues.$      = "$.postWave[0].Payload.issues",
                  waveReport.$  = "$.postWave[1].Payload",
                  context = "critical-failure-analysis"
                }
              },
              ResultPath = "$.analysis",
              Retry = [
                {
                  ErrorEquals = ["Bedrock.ServiceException"],
                  IntervalSeconds = 30,
                  MaxAttempts = 2
                }
              ],
              Next = "DecideCriticalAction"
            },

            DecideCriticalAction = {
              Type = "Choice",
              Choices = [
                {
                  Variable = "$.analysis.Payload.recommendation",
                  StringEquals = "ABORT_EXECUTION",
                  Next = "NotifyAndAbort"
                },
                {
                  Variable = "$.analysis.Payload.recommendation", 
                  StringEquals = "CONTINUE_WITH_CAUTION",
                  Next = "HandleNonCriticalIssues"
                }
              ],
              Default = "NotifyAndAbort"
            },

            HandleNonCriticalIssues = {
              Type = "Task",
              Resource = "arn:aws:states:::sns:publish",
              Parameters = {
                TopicArn = aws_sns_topic.alerts.arn,
                Subject = "⚠️ Non-Critical Issues Detected in Wave",
                Message = {
                  issues.$      = "$.postWave[0].Payload.issues",
                  analysis.$    = "$.analysis.Payload",
                  action        = "Continuing to next wave",
                  executionId.$ = "$$.Execution.Name"
                }
              },
              Next = "WavePause"
            },

            NotifyAndAbort = {
              Type = "Task",
              Resource = "arn:aws:states:::sns:publish",
              Parameters = {
                TopicArn = aws_sns_topic.alerts.arn,
                Subject = "🚨 CRITICAL: Patch Execution Aborted",
                Message = {
                  issues.$      = "$.postWave[0].Payload.issues",
                  analysis.$    = "$.analysis.Payload",
                  action        = "Execution aborted due to critical issues",
                  executionId.$ = "$$.Execution.Name"
                }
              },
              Next = "FailWave"
            },

            # Error handling states
            HandlePreWaveFailure = {
              Type = "Task",
              Resource = "arn:aws:states:::sns:publish",
              Parameters = {
                TopicArn = aws_sns_topic.alerts.arn,
                Subject = "❌ Pre-Wave Checks Failed",
                Message = {
                  error.$       = "$.error",
                  accounts.$    = "$.accounts",
                  regions.$     = "$.regions",
                  executionId.$ = "$$.Execution.Name"
                }
              },
              Next = "FailWave"
            },

            HandleInvalidTargets = {
              Type = "Task",
              Resource = "arn:aws:states:::sns:publish",
              Parameters = {
                TopicArn = aws_sns_topic.alerts.arn,
                Subject = "❌ Invalid Patch Targets",
                Message = {
                  details       = "No valid patch targets found for specified criteria",
                  accounts.$    = "$.accounts",
                  regions.$     = "$.regions",
                  executionId.$ = "$$.Execution.Name"
                }
              },
              Next = "FailWave"
            },

            WavePause = {
              Type = "Wait",
              SecondsPath = "$.wavePauseSeconds",
              Next = "WaveComplete"
            },

            WaveComplete = {
              Type = "Succeed"
            },

            FailWave = {
              Type = "Fail",
              Cause = "Wave processing failed with critical errors"
            }
          }
        },
        Catch = [
          {
            ErrorEquals = ["States.TaskFailed"],
            Next = "HandleExecutionFailure",
            ResultPath = "$.error"
          }
        ],
        Next = "GenerateFinalReport"
      },

      # Generate comprehensive final report
      GenerateFinalReport = {
        Type = "Task",
        Resource = "arn:aws:states:::lambda:invoke",
        Parameters = {
          FunctionName = "${aws_lambda_function.final_report.function_name}",
          Payload = {
            executionId.$   = "$$.Execution.Name",
            startTime.$     = "$$.Execution.StartTime", 
            waveResults.$   = "$.waveResults",
            inputData.$     = "$.execution.Payload.inputData"
          }
        },
        ResultPath = "$.finalReport",
        Retry = [
          {
            ErrorEquals = ["Lambda.ServiceException"],
            IntervalSeconds = 5,
            MaxAttempts = 3
          }
        ],
        Next = "NotifyCompletion"
      },

      # Final success notification
      NotifyCompletion = {
        Type = "Task",
        Resource = "arn:aws:states:::sns:publish",
        Parameters = {
          TopicArn = aws_sns_topic.alerts.arn,
          Subject = "✅ EC2 Patching Execution Completed Successfully",
          Message = {
            executionId.$       = "$$.Execution.Name",
            duration.$          = "$.finalReport.Payload.executionDuration",
            summary.$           = "$.finalReport.Payload.summary",
            reportLocation.$    = "$.finalReport.Payload.reportS3Location"
          }
        },
        End = true
      },

      # Global error handling states
      HandleInitializationFailure = {
        Type = "Task",
        Resource = "arn:aws:states:::sns:publish",
        Parameters = {
          TopicArn = aws_sns_topic.alerts.arn,
          Subject = "❌ Patch Execution Initialization Failed",
          Message = {
            error.$         = "$.error",
            executionId.$   = "$$.Execution.Name"
          }
        },
        Next = "ExecutionFailed"
      },

      HandleValidationFailure = {
        Type = "Task", 
        Resource = "arn:aws:states:::sns:publish",
        Parameters = {
          TopicArn = aws_sns_topic.alerts.arn,
          Subject = "❌ Input Validation Failed",
          Message = {
            error.$         = "$.error",
            inputData.$     = "$",
            executionId.$   = "$$.Execution.Name"
          }
        },
        Next = "ExecutionFailed"
      },

      HandlePrerequisiteFailure = {
        Type = "Task",
        Resource = "arn:aws:states:::sns:publish", 
        Parameters = {
          TopicArn = aws_sns_topic.alerts.arn,
          Subject = "❌ Prerequisites Check Failed",
          Message = {
            error.$         = "$.error",
            executionId.$   = "$$.Execution.Name"
          }
        },
        Next = "ExecutionFailed"
      },

      HandleApprovalTimeout = {
        Type = "Task",
        Resource = "arn:aws:states:::sns:publish",
        Parameters = {
          TopicArn = aws_sns_topic.alerts.arn,
          Subject = "⏰ Patch Approval Timeout - Execution Cancelled",
          Message = {
            message         = "No approval received within timeout period",
            timeoutMinutes  = 60,
            executionId.$   = "$$.Execution.Name"
          }
        },
        Next = "ExecutionFailed"
      },

      HandleApprovalRejection = {
        Type = "Task",
        Resource = "arn:aws:states:::sns:publish",
        Parameters = {
          TopicArn = aws_sns_topic.alerts.arn,
          Subject = "🚫 Patch Execution Rejected",
          Message = {
            rejectedBy.$    = "$.error.rejectedBy",
            rejectedAt.$    = "$.error.rejectedAt",
            reason.$        = "$.error.reason",
            executionId.$   = "$$.Execution.Name"
          }
        },
        Next = "ExecutionFailed"
      },

      HandleExecutionFailure = {
        Type = "Task",
        Resource = "arn:aws:states:::sns:publish",
        Parameters = {
          TopicArn = aws_sns_topic.alerts.arn,
          Subject = "🚨 CRITICAL: Patch Execution Failed",
          Message = {
            error.$         = "$.error",
            executionId.$   = "$$.Execution.Name",
            urgency         = "HIGH"
          }
        },
        Next = "ExecutionFailed"
      },

      ExecutionFailed = {
        Type = "Fail",
        Cause = "Patch execution failed - check notifications for details"
      }
    }
  })
}
