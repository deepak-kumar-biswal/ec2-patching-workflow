# Multi-Agent Workflow Diagrams

## Document Information
| Attribute | Value |
|-----------|-------|
| Version | 1.0 |
| Last Updated | January 14, 2026 |
| Status | Draft |
| Foundation Model | anthropic.claude-4.5-sonnet-20250101-v1:0 |

---

## 1. High-Level Multi-Agent Architecture

```mermaid
flowchart TB
    subgraph Users["👥 Users & Systems"]
        SLACK[("🔔 Slack/Teams")]
        CONSOLE["🖥️ AWS Console"]
        API["🔌 API Gateway"]
        SCHEDULE["⏰ EventBridge Scheduler"]
    end

    subgraph Orchestrator["🎯 Agent Orchestrator"]
        ROUTER{{"🧭 Request Router"}}
        CONTEXT[("📋 Shared Context Store")]
    end

    subgraph Agents["🤖 Bedrock Agents (Claude 4.5 Sonnet)"]
        AUDIT["📊 Audit & Compliance\nAgent"]
        REPORT["📈 Reporting &\nAnalytics Agent"]
        ANOMALY["🔍 Anomaly Detection\n& RCA Agent"]
        CHATOPS["💬 ChatOps\nAgent"]
        PREDICT["🔮 Predictive\nPlanning Agent"]
        REMEDIATE["🔧 Auto-Remediation\nAgent"]
    end

    subgraph KnowledgeBases["📚 Knowledge Bases (OpenSearch)"]
        KB_PATCH[("patch-artifacts")]
        KB_EXEC[("execution-records")]
        KB_DOCS[("operational-docs")]
        KB_ERROR[("error-patterns")]
        KB_COMPLY[("compliance-frameworks")]
    end

    subgraph DataSources["💾 Data Sources"]
        S3[("🪣 S3 Snapshots\nBucket")]
        DDB[("📋 DynamoDB\nPatchRunsTable")]
        CW[("📉 CloudWatch\nMetrics")]
    end

    subgraph Actions["⚡ Action Execution"]
        SSM["📜 SSM Documents"]
        SF["🔄 Step Functions"]
        SNS["📨 SNS Notifications"]
    end

    %% User inputs
    SLACK --> ROUTER
    CONSOLE --> ROUTER
    API --> ROUTER
    SCHEDULE --> ROUTER

    %% Router to Agents
    ROUTER --> AUDIT
    ROUTER --> REPORT
    ROUTER --> ANOMALY
    ROUTER --> CHATOPS
    ROUTER --> PREDICT
    ROUTER --> REMEDIATE

    %% Context sharing
    AUDIT <--> CONTEXT
    REPORT <--> CONTEXT
    ANOMALY <--> CONTEXT
    CHATOPS <--> CONTEXT
    PREDICT <--> CONTEXT
    REMEDIATE <--> CONTEXT

    %% Agents to Knowledge Bases
    AUDIT --> KB_COMPLY
    AUDIT --> KB_EXEC
    REPORT --> KB_PATCH
    REPORT --> KB_EXEC
    ANOMALY --> KB_ERROR
    ANOMALY --> KB_PATCH
    CHATOPS --> KB_DOCS
    PREDICT --> KB_EXEC
    REMEDIATE --> KB_ERROR

    %% Knowledge Base ingestion
    S3 -.-> KB_PATCH
    DDB -.-> KB_EXEC
    CW -.-> KB_PATCH

    %% Action execution
    REMEDIATE --> SSM
    REMEDIATE --> SF
    CHATOPS --> SF
    AUDIT --> SNS
    ANOMALY --> SNS

    style Orchestrator fill:#e1f5fe,stroke:#01579b
    style Agents fill:#f3e5f5,stroke:#7b1fa2
    style KnowledgeBases fill:#e8f5e9,stroke:#2e7d32
    style DataSources fill:#fff3e0,stroke:#ef6c00
    style Actions fill:#fce4ec,stroke:#c2185b
```

---

## 2. Knowledge Base Ingestion Pipeline

```mermaid
flowchart LR
    subgraph Sources["📊 Data Sources"]
        S3["🪣 S3 Bucket\n(Patch Artifacts)"]
        DDB["📋 DynamoDB\n(Execution State)"]
        DOCS["📄 Documentation\n(Markdown)"]
    end

    subgraph Triggers["⚡ Event Triggers"]
        S3_EVT["S3 ObjectCreated"]
        DDB_STREAM["DynamoDB Streams"]
        MANUAL["Manual Sync"]
    end

    subgraph Processing["🔧 Processing Pipeline"]
        S3_PARSER["S3 Artifact\nParser Lambda"]
        DDB_PARSER["DynamoDB Stream\nProcessor Lambda"]
        DOC_PARSER["Document\nChunker Lambda"]
        
        EMBEDDER["Amazon Titan\nEmbeddings V2"]
    end

    subgraph OpenSearch["🔍 OpenSearch Serverless"]
        IDX_PATCH[("patch-artifacts\nindex")]
        IDX_EXEC[("execution-records\nindex")]
        IDX_DOCS[("operational-docs\nindex")]
        IDX_ERR[("error-patterns\nindex")]
        IDX_COMPLY[("compliance-frameworks\nindex")]
    end

    S3 --> S3_EVT
    DDB --> DDB_STREAM
    DOCS --> MANUAL

    S3_EVT --> S3_PARSER
    DDB_STREAM --> DDB_PARSER
    MANUAL --> DOC_PARSER

    S3_PARSER --> EMBEDDER
    DDB_PARSER --> EMBEDDER
    DOC_PARSER --> EMBEDDER

    EMBEDDER --> IDX_PATCH
    EMBEDDER --> IDX_EXEC
    EMBEDDER --> IDX_DOCS
    EMBEDDER --> IDX_ERR
    EMBEDDER --> IDX_COMPLY

    style Sources fill:#fff3e0,stroke:#ef6c00
    style Triggers fill:#e3f2fd,stroke:#1976d2
    style Processing fill:#f3e5f5,stroke:#7b1fa2
    style OpenSearch fill:#e8f5e9,stroke:#2e7d32
```

---

## 3. Agent Interaction Flow - Query Processing

```mermaid
sequenceDiagram
    autonumber
    participant User as 👤 User
    participant Router as 🧭 Request Router
    participant Agent as 🤖 Bedrock Agent
    participant KB as 📚 Knowledge Base
    participant Tools as 🔧 Action Groups
    participant AWS as ☁️ AWS Services

    User->>Router: Natural Language Query
    Router->>Router: Classify Intent
    Router->>Agent: Route to Appropriate Agent
    
    activate Agent
    Agent->>Agent: Parse User Intent
    
    loop RAG Retrieval
        Agent->>KB: Semantic Search Query
        KB-->>Agent: Relevant Documents
    end
    
    Agent->>Agent: Generate Response Plan
    
    opt Tool Execution Required
        Agent->>Tools: Invoke Action Group
        Tools->>AWS: API Call (DynamoDB/S3/SSM)
        AWS-->>Tools: Response Data
        Tools-->>Agent: Tool Result
    end
    
    Agent->>Agent: Synthesize Final Response
    deactivate Agent
    
    Agent-->>Router: Structured Response
    Router-->>User: Natural Language Answer
```

---

## 4. Audit & Compliance Agent Flow

```mermaid
flowchart TB
    subgraph Input["📥 Input"]
        QUERY["Compliance Query"]
    end

    subgraph Agent["🤖 Audit Agent"]
        PARSE["Parse Query Intent"]
        
        subgraph Tools["Action Groups"]
            COMPLIANCE["check_compliance_status"]
            EVIDENCE["get_compliance_evidence"]
            GAPS["identify_compliance_gaps"]
            EXPORT["export_audit_report"]
        end
    end

    subgraph KB["📚 Knowledge Bases"]
        FRAMEWORKS["compliance-frameworks\n(SOC2, PCI-DSS, HIPAA)"]
        EXEC["execution-records"]
        PATCH["patch-artifacts"]
    end

    subgraph Output["📤 Output"]
        REPORT["Compliance Report"]
        GAPS_OUT["Gap Analysis"]
        EVIDENCE_OUT["Evidence Package"]
    end

    QUERY --> PARSE
    PARSE --> COMPLIANCE
    PARSE --> EVIDENCE
    PARSE --> GAPS
    PARSE --> EXPORT

    COMPLIANCE --> FRAMEWORKS
    COMPLIANCE --> EXEC
    EVIDENCE --> PATCH
    GAPS --> FRAMEWORKS
    GAPS --> EXEC

    COMPLIANCE --> REPORT
    EVIDENCE --> EVIDENCE_OUT
    GAPS --> GAPS_OUT
    EXPORT --> REPORT

    style Input fill:#e3f2fd,stroke:#1976d2
    style Agent fill:#f3e5f5,stroke:#7b1fa2
    style KB fill:#e8f5e9,stroke:#2e7d32
    style Output fill:#fff3e0,stroke:#ef6c00
```

---

## 5. Anomaly Detection & Root Cause Analysis Flow

```mermaid
flowchart TB
    subgraph Trigger["⚡ Triggers"]
        FAILURE["Patch Failure Event"]
        SCHEDULED["Scheduled Analysis"]
        MANUAL["Manual Investigation"]
    end

    subgraph Detection["🔍 Anomaly Detection"]
        BASELINE["Compare to\nHistorical Baseline"]
        PATTERN["Pattern\nMatching"]
        CLUSTER["Error\nClustering"]
    end

    subgraph Analysis["🧠 Root Cause Analysis"]
        CORRELATE["Correlate with\nInfrastructure"]
        TIMELINE["Build Event\nTimeline"]
        SIMILAR["Find Similar\nPast Incidents"]
    end

    subgraph KB["📚 Knowledge Bases"]
        ERROR_KB["error-patterns"]
        PATCH_KB["patch-artifacts"]
    end

    subgraph Actions["⚡ Actions"]
        ALERT["Generate Alert"]
        REMEDIATE["Trigger\nRemediation"]
        TICKET["Create\nIncident Ticket"]
    end

    FAILURE --> BASELINE
    SCHEDULED --> BASELINE
    MANUAL --> BASELINE

    BASELINE --> PATTERN
    PATTERN --> CLUSTER
    
    CLUSTER --> CORRELATE
    CORRELATE --> TIMELINE
    TIMELINE --> SIMILAR

    PATTERN --> ERROR_KB
    SIMILAR --> ERROR_KB
    CORRELATE --> PATCH_KB

    SIMILAR --> ALERT
    SIMILAR --> REMEDIATE
    SIMILAR --> TICKET

    style Trigger fill:#ffebee,stroke:#c62828
    style Detection fill:#e3f2fd,stroke:#1976d2
    style Analysis fill:#f3e5f5,stroke:#7b1fa2
    style KB fill:#e8f5e9,stroke:#2e7d32
    style Actions fill:#fff3e0,stroke:#ef6c00
```

---

## 6. ChatOps Agent Conversation Flow

```mermaid
stateDiagram-v2
    [*] --> Idle
    
    Idle --> ReceiveMessage: User Message
    
    ReceiveMessage --> ClassifyIntent: Parse Input
    
    ClassifyIntent --> StatusQuery: status_check
    ClassifyIntent --> ExecutionQuery: execution_details
    ClassifyIntent --> RunbookExec: runbook_action
    ClassifyIntent --> HelpRequest: help_request
    
    StatusQuery --> RetrieveData: Query DynamoDB
    ExecutionQuery --> RetrieveData: Query S3/DynamoDB
    RunbookExec --> CheckAuth: Validate Permissions
    HelpRequest --> SearchKB: Search Docs
    
    RetrieveData --> FormatResponse
    SearchKB --> FormatResponse
    
    CheckAuth --> ApprovalRequired: Elevated Action
    CheckAuth --> ExecuteAction: Standard Action
    
    ApprovalRequired --> WaitApproval: Request Approval
    WaitApproval --> ExecuteAction: Approved
    WaitApproval --> FormatResponse: Denied/Timeout
    
    ExecuteAction --> FormatResponse: Action Result
    
    FormatResponse --> SendResponse: Format for Channel
    SendResponse --> Idle: Response Sent
```

---

## 7. Auto-Remediation Agent Decision Flow

```mermaid
flowchart TB
    subgraph Input["⚡ Trigger"]
        FAILURE["Failure Detected"]
    end

    subgraph Validation["✅ Validation Layer"]
        ACTION_TYPE{"Action Type?"}
        
        T1["Tier 1\nAutonomous"]
        T2["Tier 2\nThreshold-Based"]
        T3["Tier 3\nApproval Required"]
        T4["Tier 4\nProhibited"]
    end

    subgraph RateLimits["⏱️ Rate Limits"]
        CHECK_RATE{"Rate Limit\nOK?"}
        CHECK_BLAST{"Blast Radius\nOK?"}
        CHECK_THRESH{"Below\nThreshold?"}
    end

    subgraph Approval["🔐 Approval Flow"]
        REQUEST["Request Approval"]
        NOTIFY["Notify Approvers"]
        WAIT{"Wait for\nApproval"}
        TIMEOUT["Timeout\n(30 min)"]
    end

    subgraph Execution["⚡ Execution"]
        CAPTURE_PRE["Capture\nPre-State"]
        EXECUTE["Execute\nAction"]
        CAPTURE_POST["Capture\nPost-State"]
        VERIFY["Verify\nSuccess"]
    end

    subgraph Outcomes["📤 Outcomes"]
        SUCCESS["✅ Success"]
        DENIED["❌ Denied"]
        ESCALATE["⚠️ Escalate"]
        ROLLBACK["↩️ Rollback"]
    end

    FAILURE --> ACTION_TYPE
    
    ACTION_TYPE --> T1
    ACTION_TYPE --> T2
    ACTION_TYPE --> T3
    ACTION_TYPE --> T4
    
    T1 --> CHECK_RATE
    T2 --> CHECK_THRESH
    T3 --> REQUEST
    T4 --> DENIED
    
    CHECK_RATE -->|Yes| CHECK_BLAST
    CHECK_RATE -->|No| DENIED
    
    CHECK_BLAST -->|Yes| CAPTURE_PRE
    CHECK_BLAST -->|No| DENIED
    
    CHECK_THRESH -->|Yes| CHECK_RATE
    CHECK_THRESH -->|No| REQUEST
    
    REQUEST --> NOTIFY
    NOTIFY --> WAIT
    WAIT -->|Approved| CAPTURE_PRE
    WAIT -->|Denied| DENIED
    WAIT -->|Timeout| TIMEOUT
    TIMEOUT --> ESCALATE
    
    CAPTURE_PRE --> EXECUTE
    EXECUTE --> CAPTURE_POST
    CAPTURE_POST --> VERIFY
    
    VERIFY -->|Pass| SUCCESS
    VERIFY -->|Fail| ROLLBACK
    ROLLBACK --> ESCALATE

    style Input fill:#ffebee,stroke:#c62828
    style Validation fill:#e3f2fd,stroke:#1976d2
    style RateLimits fill:#fff3e0,stroke:#ef6c00
    style Approval fill:#f3e5f5,stroke:#7b1fa2
    style Execution fill:#e8f5e9,stroke:#2e7d32
    style Outcomes fill:#fce4ec,stroke:#c2185b
```

---

## 8. Multi-Agent Collaboration Pattern

```mermaid
sequenceDiagram
    autonumber
    participant User as 👤 User
    participant Chat as 💬 ChatOps Agent
    participant Predict as 🔮 Predictive Agent
    participant Audit as 📊 Audit Agent
    participant Remediate as 🔧 Remediation Agent

    User->>Chat: "Plan next patching window for prod"
    
    activate Chat
    Chat->>Predict: Request wave optimization
    activate Predict
    Predict->>Predict: Analyze historical data
    Predict->>Predict: Calculate risk scores
    Predict-->>Chat: Recommended configuration
    deactivate Predict
    
    Chat->>Audit: Check compliance requirements
    activate Audit
    Audit->>Audit: Verify SLA windows
    Audit->>Audit: Check maintenance calendars
    Audit-->>Chat: Compliance constraints
    deactivate Audit
    
    Chat->>Chat: Synthesize recommendations
    Chat-->>User: "Recommended window: Sat 2AM-6AM\nWave config: 3 waves, 50 instances each"
    deactivate Chat
    
    Note over User,Chat: User approves plan
    
    User->>Chat: "Execute the plan"
    Chat->>Remediate: Initiate patching workflow
    
    activate Remediate
    loop During Execution
        Remediate->>Remediate: Monitor progress
        Remediate-->>Chat: Status updates
        Chat-->>User: Real-time updates
    end
    
    Remediate-->>Chat: Execution complete
    deactivate Remediate
    
    Chat->>Audit: Generate compliance report
    Audit-->>Chat: Report generated
    Chat-->>User: "Patching complete. Compliance report ready."
```

---

## 9. Predictive Planning Agent Flow

```mermaid
flowchart TB
    subgraph Input["📥 Planning Request"]
        PLAN_REQ["Wave Planning\nRequest"]
        MAINT_REQ["Maintenance Window\nRecommendation"]
        RISK_REQ["Risk Assessment\nRequest"]
    end

    subgraph DataCollection["📊 Data Collection"]
        HIST["Historical\nExecution Data"]
        INST["Instance\nCharacteristics"]
        CAL["Change\nCalendars"]
        DEP["Dependency\nMaps"]
    end

    subgraph Models["🧮 ML Models"]
        DURATION["Duration\nPrediction Model\n(XGBoost)"]
        RISK["Risk Scoring\nModel"]
        OPT["Optimization\nAlgorithm"]
    end

    subgraph Output["📤 Recommendations"]
        WAVE_CFG["Wave\nConfiguration"]
        WINDOW["Optimal\nMaintenance Window"]
        RISK_SCORE["Risk Scores\nby Instance"]
        FORECAST["Duration\nForecast"]
    end

    PLAN_REQ --> HIST
    PLAN_REQ --> INST
    MAINT_REQ --> CAL
    RISK_REQ --> DEP

    HIST --> DURATION
    INST --> DURATION
    INST --> RISK
    DEP --> RISK

    DURATION --> FORECAST
    RISK --> RISK_SCORE
    
    FORECAST --> OPT
    RISK_SCORE --> OPT
    CAL --> OPT

    OPT --> WAVE_CFG
    OPT --> WINDOW

    style Input fill:#e3f2fd,stroke:#1976d2
    style DataCollection fill:#fff3e0,stroke:#ef6c00
    style Models fill:#f3e5f5,stroke:#7b1fa2
    style Output fill:#e8f5e9,stroke:#2e7d32
```

---

## 10. End-to-End Patching with Agents

```mermaid
flowchart TB
    subgraph Planning["📋 Planning Phase"]
        direction LR
        P1["User requests\npatching window"]
        P2["Predictive Agent\nanalyzes risk"]
        P3["Audit Agent\nchecks compliance"]
        P4["Optimal plan\ngenerated"]
        P1 --> P2 --> P3 --> P4
    end

    subgraph Execution["⚙️ Execution Phase"]
        direction LR
        E1["Step Functions\nstarts execution"]
        E2["Pre-patch\ninventory"]
        E3["SSM patch\ninstallation"]
        E4["Post-patch\nverification"]
        E1 --> E2 --> E3 --> E4
    end

    subgraph Monitoring["👁️ Monitoring Phase"]
        direction LR
        M1["ChatOps Agent\nstreams updates"]
        M2["Anomaly Agent\ndetects issues"]
        M3["Auto-Remediation\nfixes failures"]
        M1 --> M2 --> M3
    end

    subgraph Reporting["📊 Reporting Phase"]
        direction LR
        R1["Reporting Agent\ngenerates summary"]
        R2["Audit Agent\ncreates evidence"]
        R3["Compliance\nreport ready"]
        R1 --> R2 --> R3
    end

    Planning --> Execution
    Execution --> Monitoring
    Monitoring --> Reporting

    style Planning fill:#e3f2fd,stroke:#1976d2
    style Execution fill:#e8f5e9,stroke:#2e7d32
    style Monitoring fill:#fff3e0,stroke:#ef6c00
    style Reporting fill:#f3e5f5,stroke:#7b1fa2
```

---

## 11. Agent Security & Guardrails

```mermaid
flowchart TB
    subgraph Request["📥 Incoming Request"]
        USER_REQ["User Request"]
    end

    subgraph Guardrails["🛡️ Bedrock Guardrails"]
        CONTENT["Content\nFilters"]
        TOPIC["Topic\nRestrictions"]
        WORD["Word\nBlacklist"]
        PII["PII\nDetection"]
    end

    subgraph Validation["✅ Custom Validation"]
        ACTION["Action\nClassification"]
        RATE["Rate Limit\nCheck"]
        BLAST["Blast Radius\nCheck"]
        AUTH["Authorization\nCheck"]
    end

    subgraph Agent["🤖 Agent Processing"]
        PROCESS["Process\nRequest"]
    end

    subgraph IAM["🔐 IAM Controls"]
        BOUNDARY["Permission\nBoundary"]
        ROLE["Scoped\nIAM Role"]
        DENY["Explicit\nDeny Rules"]
    end

    subgraph Audit["📋 Audit Trail"]
        LOG["CloudWatch\nLogs"]
        TRAIL["CloudTrail\nEvents"]
        DDB_AUDIT["DynamoDB\nAudit Table"]
    end

    USER_REQ --> CONTENT
    CONTENT --> TOPIC
    TOPIC --> WORD
    WORD --> PII
    
    PII -->|Pass| ACTION
    PII -->|Fail| BLOCKED["❌ Blocked"]
    
    ACTION --> RATE
    RATE --> BLAST
    BLAST --> AUTH
    
    AUTH -->|Pass| PROCESS
    AUTH -->|Fail| DENIED["❌ Denied"]
    
    PROCESS --> BOUNDARY
    BOUNDARY --> ROLE
    ROLE --> DENY
    
    PROCESS --> LOG
    PROCESS --> TRAIL
    PROCESS --> DDB_AUDIT

    style Request fill:#e3f2fd,stroke:#1976d2
    style Guardrails fill:#ffebee,stroke:#c62828
    style Validation fill:#fff3e0,stroke:#ef6c00
    style Agent fill:#f3e5f5,stroke:#7b1fa2
    style IAM fill:#e8f5e9,stroke:#2e7d32
    style Audit fill:#eceff1,stroke:#546e7a
```

---

## 12. Agent Model Configuration Summary

```mermaid
mindmap
  root((Claude 4.5 Sonnet<br/>Multi-Agent System))
    Audit Agent
      Temperature: 0.1
      Max Tokens: 4096
      Focus: Factual accuracy
      Tools: compliance-queries, compliance-reports
    Reporting Agent
      Temperature: 0.2
      Max Tokens: 8192
      Focus: Narrative + accuracy
      Tools: metrics-analytics, report-generation
    Anomaly Agent
      Temperature: 0.3
      Max Tokens: 16384
      Focus: Enhanced reasoning
      Tools: anomaly-detection, root-cause-analysis
    ChatOps Agent
      Temperature: 0.15
      Max Tokens: 2048
      Focus: Consistent responses
      Tools: status-queries, runbook-operations
    Predictive Agent
      Temperature: 0.2
      Max Tokens: 4096
      Focus: Analytical reasoning
      Tools: forecasting, optimization
    Remediation Agent
      Temperature: 0.0
      Max Tokens: 2048
      Focus: Deterministic
      Tools: recovery-actions, escalation
```

---

## Usage Notes

### Rendering Mermaid Diagrams

These diagrams can be rendered in:
- **GitHub**: Automatic rendering in markdown files
- **VS Code**: Install "Markdown Preview Mermaid Support" extension
- **Confluence**: Use Mermaid macro
- **Mermaid Live Editor**: https://mermaid.live

### Diagram Types Used

| Diagram Type | Use Case |
|--------------|----------|
| `flowchart` | System architecture, data flows |
| `sequenceDiagram` | Agent interactions, API calls |
| `stateDiagram-v2` | State machines, conversation flows |
| `mindmap` | Configuration summaries |

---

*Generated for EC2 Patching Platform Multi-Agent System*
