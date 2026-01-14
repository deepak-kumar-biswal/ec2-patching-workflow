# Knowledge Base Indexing Pipeline - Technical Design

## Document Information
| Attribute | Value |
|-----------|-------|
| Version | 1.0 |
| Last Updated | January 14, 2026 |
| Status | Draft |
| Owner | Platform Engineering |

---

## 1. Executive Summary

This document details the technical design for the **Knowledge Base Indexing Pipeline** that powers all Bedrock Agents in the EC2 Patching Platform. The pipeline ingests data from S3 (patch artifacts), DynamoDB (execution state), and CloudWatch (metrics/logs) into Amazon OpenSearch Serverless for Retrieval Augmented Generation (RAG).

---

## 2. Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                           DATA SOURCES                                           │
├─────────────────┬─────────────────┬─────────────────┬───────────────────────────┤
│   S3 Bucket     │   DynamoDB      │   CloudWatch    │   Static Documents        │
│   (Snapshots)   │   (PatchRuns)   │   (Logs/Metrics)│   (Runbooks/Docs)         │
│                 │                 │                 │                           │
│ • stdout.txt    │ • scope/id      │ • Lambda logs   │ • runbook-operations.md   │
│ • stderr.txt    │ • status        │ • SF execution  │ • troubleshooting.md      │
│ • meta.json     │ • metadata      │ • SSM commands  │ • api.md                  │
└────────┬────────┴────────┬────────┴────────┬────────┴──────────────┬────────────┘
         │                 │                 │                       │
         ▼                 ▼                 ▼                       ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                        EVENT TRIGGERS                                            │
├─────────────────┬─────────────────┬─────────────────┬───────────────────────────┤
│  S3 Events      │  DynamoDB       │  CloudWatch     │   GitHub Actions          │
│  (EventBridge)  │  Streams        │  Subscription   │   (on-commit)             │
│                 │                 │  Filters        │                           │
└────────┬────────┴────────┬────────┴────────┬────────┴──────────────┬────────────┘
         │                 │                 │                       │
         └─────────────────┴────────┬────────┴───────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                     INGESTION LAYER (Lambda Functions)                           │
├─────────────────────────────────────────────────────────────────────────────────┤
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────────────────┐   │
│  │ S3ArtifactParser │  │ DDBStreamProcessor│ │ DocumentChunker              │   │
│  │                  │  │                   │  │                              │   │
│  │ • Extract text   │  │ • Transform record│  │ • Split large docs          │   │
│  │ • Parse meta.json│  │ • Enrich metadata │  │ • Add metadata              │   │
│  │ • Normalize      │  │ • Handle deletes  │  │ • Semantic chunking         │   │
│  └──────────────────┘  └──────────────────┘  └──────────────────────────────┘   │
│                                    │                                             │
│                                    ▼                                             │
│  ┌──────────────────────────────────────────────────────────────────────────┐   │
│  │                    DOCUMENT ENRICHMENT                                    │   │
│  │  • Add account/region/instance metadata                                   │   │
│  │  • Calculate embeddings (Titan Embeddings V2)                            │   │
│  │  • Add timestamp and TTL                                                  │   │
│  │  • Tag document type (stdout, stderr, meta, execution, runbook)          │   │
│  └──────────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                    AMAZON OPENSEARCH SERVERLESS                                  │
├─────────────────────────────────────────────────────────────────────────────────┤
│  Collection: ec2-patching-knowledge-base                                         │
│  Type: VECTORSEARCH                                                              │
│                                                                                  │
│  ┌────────────────────────────────────────────────────────────────────────────┐ │
│  │ Index: patch-artifacts                                                      │ │
│  │ ├── execution_id (keyword)      ├── account_id (keyword)                   │ │
│  │ ├── region (keyword)            ├── instance_id (keyword)                  │ │
│  │ ├── artifact_type (keyword)     ├── os_type (keyword)                      │ │
│  │ ├── timestamp (date)            ├── content (text)                         │ │
│  │ ├── status (keyword)            ├── embedding (knn_vector, 1024d)          │ │
│  │ └── s3_path (keyword)           └── ttl (date)                             │ │
│  └────────────────────────────────────────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────────────────────────────────────────┐ │
│  │ Index: execution-records                                                    │ │
│  │ ├── execution_id (keyword)      ├── scope (keyword)                        │ │
│  │ ├── status (keyword)            ├── wave_name (keyword)                    │ │
│  │ ├── start_time (date)           ├── end_time (date)                        │ │
│  │ ├── accounts (keyword[])        ├── regions (keyword[])                    │ │
│  │ ├── instance_count (integer)    ├── success_count (integer)                │ │
│  │ ├── failure_count (integer)     ├── metadata (object)                      │ │
│  │ └── embedding (knn_vector, 1024d)                                          │ │
│  └────────────────────────────────────────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────────────────────────────────────────┐ │
│  │ Index: operational-docs                                                     │ │
│  │ ├── doc_id (keyword)            ├── doc_type (keyword)                     │ │
│  │ ├── title (text)                ├── content (text)                         │ │
│  │ ├── section (keyword)           ├── version (keyword)                      │ │
│  │ ├── last_updated (date)         ├── embedding (knn_vector, 1024d)          │ │
│  │ └── source_file (keyword)                                                  │ │
│  └────────────────────────────────────────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────────────────────────────────────────┐ │
│  │ Index: error-patterns                                                       │ │
│  │ ├── pattern_id (keyword)        ├── error_signature (text)                 │ │
│  │ ├── category (keyword)          ├── root_cause (text)                      │ │
│  │ ├── remediation (text)          ├── occurrence_count (integer)             │ │
│  │ ├── last_seen (date)            ├── affected_os (keyword[])                │ │
│  │ ├── embedding (knn_vector, 1024d)                                          │ │
│  │ └── confidence_score (float)                                               │ │
│  └────────────────────────────────────────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────────────────────────────────────────┐ │
│  │ Index: compliance-frameworks                                                │ │
│  │ ├── framework_id (keyword)      ├── control_id (keyword)                   │ │
│  │ ├── control_name (text)         ├── requirement (text)                     │ │
│  │ ├── evidence_required (text)    ├── patch_relevance (keyword)              │ │
│  │ └── embedding (knn_vector, 1024d)                                          │ │
│  └────────────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                    BEDROCK KNOWLEDGE BASE                                        │
├─────────────────────────────────────────────────────────────────────────────────┤
│  Knowledge Base ID: kb-ec2patching-prod                                          │
│  Foundation Model for Embeddings: amazon.titan-embed-text-v2:0                  │
│  Vector Store: OpenSearch Serverless (above)                                    │
│                                                                                  │
│  Retrieval Configuration:                                                        │
│  ├── numberOfResults: 10                                                         │
│  ├── overrideSearchType: HYBRID (semantic + keyword)                            │
│  └── vectorSearchConfiguration:                                                  │
│      └── numberOfResults: 20                                                     │
│      └── overrideSearchType: SEMANTIC                                           │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Data Source Details

### 3.1 S3 Patch Artifacts

**Source Bucket:** `${NamePrefix}-${Environment}-snapshots`

**Object Structure:**
```
runs/
├── {ExecutionId}/
│   ├── pre/                           # Pre-collection data
│   │   └── account-{AccountId}/
│   │       └── region-{Region}/
│   │           ├── linux/{InstanceId}/
│   │           │   ├── stdout.txt     # System info, packages, services
│   │           │   ├── stderr.txt     # Error output
│   │           │   └── meta.json      # Status, response codes
│   │           └── windows/{InstanceId}/
│   │               └── ...
│   ├── custom-pre/                    # Custom pre-patch outputs
│   │   └── ...
│   ├── custom-patch/                  # Patch execution outputs
│   │   └── ...
│   └── custom-post/                   # Post-patch outputs
│       └── ...
```

**Sample meta.json:**
```json
{
  "CommandId": "abc123-def456",
  "InstanceId": "i-0abc123def456",
  "Status": "Success",
  "ResponseCode": 0,
  "ExecutionStartDateTime": "2026-01-14T02:15:00Z",
  "ExecutionEndDateTime": "2026-01-14T02:18:30Z",
  "StandardOutputUrl": "s3://bucket/runs/.../stdout.txt",
  "StandardErrorUrl": "s3://bucket/runs/.../stderr.txt",
  "PluginName": "aws:runShellScript"
}
```

**Sample stdout.txt (Linux Pre-Collection):**
```
Linux ip-10-0-1-50 5.15.0-1052-aws #57~20.04.1-Ubuntu SMP x86_64
NAME="Ubuntu"
VERSION="20.04.6 LTS (Focal Fossa)"
2026-01-14T02:15:30+00:00
Filesystem      Size  Used Avail Use% Mounted on
/dev/nvme0n1p1  100G   45G   55G  45% /
              total        used        free      shared  buff/cache   available
Mem:           7983        2345        3456         123        2182        5234
  PID USER      PR  NI    VIRT    RES    SHR S  %CPU  %MEM     COMMAND
 1234 root      20   0  123456  12345   1234 S   2.5   1.5     amazon-ssm-agen
...
```

### 3.2 DynamoDB Execution Records

**Table:** `${NamePrefix}-${Environment}-patchruns`

**Schema:**
```
Primary Key: scope (HASH), id (RANGE)
Attributes:
├── scope: "wave" | "account" | "region" | "instance"
├── id: "<identifier>"
├── execution_id: "<step-functions-execution-id>"
├── status: "pending" | "running" | "success" | "partial" | "failed"
├── start_time: ISO8601 timestamp
├── end_time: ISO8601 timestamp
├── metadata: {
│   ├── wave_name: "canary-wave-1"
│   ├── accounts: ["111111111111", "222222222222"]
│   ├── regions: ["us-east-1", "us-west-2"]
│   ├── instance_count: 150
│   ├── success_count: 145
│   ├── failure_count: 5
│   ├── patches_installed: 234
│   └── duration_seconds: 1845
│   }
└── ttl: Unix timestamp (90 days from creation)
```

**Sample Record:**
```json
{
  "scope": "wave",
  "id": "wave-canary-2026-01-14",
  "execution_id": "arn:aws:states:us-east-1:111111111111:execution:ec2-patch-prod-orchestrator:wave-canary-2026-01-14",
  "status": "success",
  "start_time": "2026-01-14T02:00:00Z",
  "end_time": "2026-01-14T02:45:30Z",
  "metadata": {
    "wave_name": "canary-wave-1",
    "accounts": ["222222222222", "333333333333"],
    "regions": ["us-east-1"],
    "instance_count": 25,
    "success_count": 24,
    "failure_count": 1,
    "patches_installed": 89,
    "duration_seconds": 2730
  },
  "ttl": 1713139200
}
```

### 3.3 Static Documentation

**Source:** Git repository `docs/` folder

| Document | Purpose | Update Frequency |
|----------|---------|------------------|
| `runbook-operations.md` | Day-2 operations procedures | On change |
| `troubleshooting-guide.md` | Common issues and fixes | On change |
| `api.md` | API reference | On change |
| `deployment-guide.md` | Deployment procedures | On change |
| `custom-ssm-documents.md` | SSM document reference | On change |

### 3.4 Compliance Frameworks (Manually Curated)

**Source:** S3 bucket `${NamePrefix}-${Environment}-compliance-docs`

| Framework | Controls Relevant to Patching |
|-----------|------------------------------|
| SOC 2 | CC6.1, CC7.1, CC7.2, CC8.1 |
| PCI-DSS | 6.2, 6.3, 11.2 |
| HIPAA | §164.308(a)(5), §164.312(a)(1) |
| NIST 800-53 | SI-2, SI-3, CM-3 |

---

## 4. Ingestion Lambda Functions

### 4.1 S3 Artifact Parser

**Function Name:** `${NamePrefix}-${Environment}-kb-s3-parser`

**Trigger:** EventBridge rule for S3 object creation

**EventBridge Rule:**
```json
{
  "source": ["aws.s3"],
  "detail-type": ["Object Created"],
  "detail": {
    "bucket": {
      "name": ["${SnapshotsBucket}"]
    },
    "object": {
      "key": [{
        "prefix": "runs/"
      }]
    }
  }
}
```

**Lambda Code:**
```python
"""
S3 Artifact Parser for Knowledge Base Ingestion
Parses stdout, stderr, and meta.json files from patch runs
"""

import json
import boto3
import re
from datetime import datetime
from typing import Dict, Any, List, Optional
import hashlib

# Clients
s3_client = boto3.client('s3')
bedrock_client = boto3.client('bedrock-runtime')
opensearch_client = boto3.client('opensearchserverless')

# Configuration
OPENSEARCH_ENDPOINT = os.environ['OPENSEARCH_ENDPOINT']
EMBEDDING_MODEL_ID = 'amazon.titan-embed-text-v2:0'
INDEX_NAME = 'patch-artifacts'
MAX_CONTENT_LENGTH = 10000  # Characters to embed

def handler(event, context):
    """Process S3 event and index document to OpenSearch"""
    
    for record in event.get('detail', {}).get('object', []):
        bucket = event['detail']['bucket']['name']
        key = record['key']
        
        # Parse S3 path to extract metadata
        metadata = parse_s3_path(key)
        if not metadata:
            continue
            
        # Fetch and process content
        content = fetch_s3_content(bucket, key)
        
        # Generate document
        document = create_document(metadata, content, bucket, key)
        
        # Generate embedding
        embedding = generate_embedding(document['content'][:MAX_CONTENT_LENGTH])
        document['embedding'] = embedding
        
        # Index to OpenSearch
        index_document(document)
        
    return {'statusCode': 200, 'indexed': len(event.get('Records', []))}


def parse_s3_path(key: str) -> Optional[Dict[str, str]]:
    """
    Parse S3 key to extract metadata
    Example: runs/ex-123/pre/account-111111111111/region-us-east-1/linux/i-abc123/stdout.txt
    """
    pattern = r'runs/([^/]+)/([^/]+)/account-(\d+)/region-([^/]+)/([^/]+)/([^/]+)/([^/]+)'
    match = re.match(pattern, key)
    
    if not match:
        return None
        
    return {
        'execution_id': match.group(1),
        'phase': match.group(2),       # pre, custom-pre, custom-patch, custom-post
        'account_id': match.group(3),
        'region': match.group(4),
        'os_type': match.group(5),      # linux, windows
        'instance_id': match.group(6),
        'artifact_type': match.group(7).replace('.txt', '').replace('.json', '')
    }


def fetch_s3_content(bucket: str, key: str) -> str:
    """Fetch content from S3"""
    try:
        response = s3_client.get_object(Bucket=bucket, Key=key)
        content = response['Body'].read().decode('utf-8', errors='replace')
        return content
    except Exception as e:
        print(f"Error fetching {key}: {e}")
        return ""


def create_document(metadata: Dict, content: str, bucket: str, key: str) -> Dict[str, Any]:
    """Create document for indexing"""
    
    # Generate unique document ID
    doc_id = hashlib.sha256(f"{bucket}/{key}".encode()).hexdigest()[:16]
    
    # Parse status from meta.json if available
    status = "unknown"
    if metadata['artifact_type'] == 'meta':
        try:
            meta_content = json.loads(content)
            status = meta_content.get('Status', 'unknown')
        except:
            pass
    
    return {
        'doc_id': doc_id,
        'execution_id': metadata['execution_id'],
        'account_id': metadata['account_id'],
        'region': metadata['region'],
        'instance_id': metadata['instance_id'],
        'os_type': metadata['os_type'],
        'phase': metadata['phase'],
        'artifact_type': metadata['artifact_type'],
        'status': status,
        'content': content,
        's3_path': f"s3://{bucket}/{key}",
        'timestamp': datetime.utcnow().isoformat(),
        'ttl': (datetime.utcnow().timestamp() + 90 * 24 * 3600)  # 90 days
    }


def generate_embedding(text: str) -> List[float]:
    """Generate embedding using Titan Embeddings V2"""
    
    response = bedrock_client.invoke_model(
        modelId=EMBEDDING_MODEL_ID,
        contentType='application/json',
        accept='application/json',
        body=json.dumps({
            'inputText': text,
            'dimensions': 1024,
            'normalize': True
        })
    )
    
    result = json.loads(response['body'].read())
    return result['embedding']


def index_document(document: Dict[str, Any]):
    """Index document to OpenSearch Serverless"""
    
    # Use requests library with SigV4 signing
    from requests_aws4auth import AWS4Auth
    from opensearchpy import OpenSearch, RequestsHttpConnection
    
    credentials = boto3.Session().get_credentials()
    awsauth = AWS4Auth(
        credentials.access_key,
        credentials.secret_key,
        os.environ['AWS_REGION'],
        'aoss',
        session_token=credentials.token
    )
    
    client = OpenSearch(
        hosts=[{'host': OPENSEARCH_ENDPOINT, 'port': 443}],
        http_auth=awsauth,
        use_ssl=True,
        verify_certs=True,
        connection_class=RequestsHttpConnection
    )
    
    client.index(
        index=INDEX_NAME,
        body=document,
        id=document['doc_id']
    )
```

### 4.2 DynamoDB Stream Processor

**Function Name:** `${NamePrefix}-${Environment}-kb-ddb-processor`

**Trigger:** DynamoDB Streams

**Lambda Code:**
```python
"""
DynamoDB Stream Processor for Knowledge Base Ingestion
Processes patch execution records from DynamoDB Streams
"""

import json
import boto3
from datetime import datetime
from typing import Dict, Any, List
from boto3.dynamodb.types import TypeDeserializer

deserializer = TypeDeserializer()
bedrock_client = boto3.client('bedrock-runtime')

EMBEDDING_MODEL_ID = 'amazon.titan-embed-text-v2:0'
INDEX_NAME = 'execution-records'

def handler(event, context):
    """Process DynamoDB stream events"""
    
    for record in event.get('Records', []):
        event_name = record['eventName']  # INSERT, MODIFY, REMOVE
        
        if event_name == 'REMOVE':
            # Handle deletion
            old_image = deserialize_item(record['dynamodb'].get('OldImage', {}))
            delete_document(old_image)
        else:
            # Handle insert or update
            new_image = deserialize_item(record['dynamodb'].get('NewImage', {}))
            document = transform_to_document(new_image)
            
            # Generate embedding from execution summary
            summary = create_execution_summary(new_image)
            document['embedding'] = generate_embedding(summary)
            
            index_document(document)
    
    return {'statusCode': 200}


def deserialize_item(item: Dict) -> Dict:
    """Deserialize DynamoDB item"""
    return {k: deserializer.deserialize(v) for k, v in item.items()}


def transform_to_document(item: Dict) -> Dict[str, Any]:
    """Transform DynamoDB record to OpenSearch document"""
    
    metadata = item.get('metadata', {})
    
    return {
        'doc_id': f"{item['scope']}_{item['id']}",
        'execution_id': item.get('execution_id', ''),
        'scope': item['scope'],
        'scope_id': item['id'],
        'status': item.get('status', 'unknown'),
        'wave_name': metadata.get('wave_name', ''),
        'accounts': metadata.get('accounts', []),
        'regions': metadata.get('regions', []),
        'instance_count': metadata.get('instance_count', 0),
        'success_count': metadata.get('success_count', 0),
        'failure_count': metadata.get('failure_count', 0),
        'patches_installed': metadata.get('patches_installed', 0),
        'duration_seconds': metadata.get('duration_seconds', 0),
        'start_time': item.get('start_time', ''),
        'end_time': item.get('end_time', ''),
        'timestamp': datetime.utcnow().isoformat()
    }


def create_execution_summary(item: Dict) -> str:
    """Create text summary for embedding"""
    
    metadata = item.get('metadata', {})
    
    summary = f"""
    Patch execution record for {item['scope']} scope.
    Execution ID: {item.get('execution_id', 'N/A')}
    Wave: {metadata.get('wave_name', 'N/A')}
    Status: {item.get('status', 'unknown')}
    Accounts: {', '.join(metadata.get('accounts', []))}
    Regions: {', '.join(metadata.get('regions', []))}
    Total instances: {metadata.get('instance_count', 0)}
    Successful: {metadata.get('success_count', 0)}
    Failed: {metadata.get('failure_count', 0)}
    Patches installed: {metadata.get('patches_installed', 0)}
    Duration: {metadata.get('duration_seconds', 0)} seconds
    Start: {item.get('start_time', 'N/A')}
    End: {item.get('end_time', 'N/A')}
    """
    
    return summary.strip()


def generate_embedding(text: str) -> List[float]:
    """Generate embedding using Titan Embeddings V2"""
    
    response = bedrock_client.invoke_model(
        modelId=EMBEDDING_MODEL_ID,
        contentType='application/json',
        accept='application/json',
        body=json.dumps({
            'inputText': text,
            'dimensions': 1024,
            'normalize': True
        })
    )
    
    result = json.loads(response['body'].read())
    return result['embedding']
```

### 4.3 Document Chunker (Markdown Parser)

**Function Name:** `${NamePrefix}-${Environment}-kb-doc-chunker`

**Trigger:** S3 event on documentation bucket OR GitHub Actions webhook

**Lambda Code:**
```python
"""
Document Chunker for Operational Documentation
Parses markdown files and creates semantic chunks for indexing
"""

import json
import boto3
import re
from typing import Dict, Any, List, Tuple
import hashlib

bedrock_client = boto3.client('bedrock-runtime')
s3_client = boto3.client('s3')

EMBEDDING_MODEL_ID = 'amazon.titan-embed-text-v2:0'
INDEX_NAME = 'operational-docs'
CHUNK_SIZE = 1500  # Characters per chunk
CHUNK_OVERLAP = 200  # Overlap between chunks

def handler(event, context):
    """Process documentation files"""
    
    bucket = event['bucket']
    key = event['key']
    
    # Fetch markdown content
    content = fetch_s3_content(bucket, key)
    
    # Parse into sections
    sections = parse_markdown_sections(content)
    
    # Create chunks from each section
    chunks = []
    for section in sections:
        section_chunks = create_chunks(section)
        chunks.extend(section_chunks)
    
    # Index each chunk
    for chunk in chunks:
        chunk['source_file'] = key
        chunk['embedding'] = generate_embedding(chunk['content'])
        index_document(chunk)
    
    return {'statusCode': 200, 'chunks_indexed': len(chunks)}


def parse_markdown_sections(content: str) -> List[Dict[str, str]]:
    """Parse markdown into sections based on headers"""
    
    sections = []
    current_section = {'title': 'Introduction', 'level': 0, 'content': ''}
    
    lines = content.split('\n')
    
    for line in lines:
        # Check for headers
        header_match = re.match(r'^(#{1,6})\s+(.+)$', line)
        
        if header_match:
            # Save current section if it has content
            if current_section['content'].strip():
                sections.append(current_section.copy())
            
            # Start new section
            level = len(header_match.group(1))
            title = header_match.group(2)
            current_section = {
                'title': title,
                'level': level,
                'content': f"# {title}\n"
            }
        else:
            current_section['content'] += line + '\n'
    
    # Don't forget last section
    if current_section['content'].strip():
        sections.append(current_section)
    
    return sections


def create_chunks(section: Dict[str, str]) -> List[Dict[str, Any]]:
    """Create overlapping chunks from a section"""
    
    content = section['content']
    chunks = []
    
    # If content is small enough, keep as single chunk
    if len(content) <= CHUNK_SIZE:
        chunks.append({
            'doc_id': hashlib.sha256(content.encode()).hexdigest()[:16],
            'title': section['title'],
            'section': section['title'],
            'level': section['level'],
            'content': content,
            'chunk_index': 0
        })
        return chunks
    
    # Split into overlapping chunks
    start = 0
    chunk_index = 0
    
    while start < len(content):
        end = start + CHUNK_SIZE
        
        # Try to end at a sentence or paragraph boundary
        if end < len(content):
            # Look for paragraph break
            para_break = content.rfind('\n\n', start, end)
            if para_break > start + CHUNK_SIZE // 2:
                end = para_break
            else:
                # Look for sentence break
                sentence_break = content.rfind('. ', start, end)
                if sentence_break > start + CHUNK_SIZE // 2:
                    end = sentence_break + 1
        
        chunk_content = content[start:end].strip()
        
        if chunk_content:
            chunks.append({
                'doc_id': hashlib.sha256(f"{section['title']}_{chunk_index}".encode()).hexdigest()[:16],
                'title': section['title'],
                'section': section['title'],
                'level': section['level'],
                'content': chunk_content,
                'chunk_index': chunk_index
            })
        
        start = end - CHUNK_OVERLAP
        chunk_index += 1
    
    return chunks
```

---

## 5. OpenSearch Serverless Configuration

### 5.1 Collection Definition

```json
{
  "name": "ec2-patching-knowledge-base",
  "type": "VECTORSEARCH",
  "description": "Knowledge base for EC2 Patching Platform AI Agents"
}
```

### 5.2 Data Access Policy

```json
{
  "Rules": [
    {
      "Resource": ["collection/ec2-patching-knowledge-base"],
      "Permission": [
        "aoss:CreateCollectionItems",
        "aoss:UpdateCollectionItems",
        "aoss:DescribeCollectionItems"
      ],
      "ResourceType": "collection"
    },
    {
      "Resource": ["index/ec2-patching-knowledge-base/*"],
      "Permission": [
        "aoss:CreateIndex",
        "aoss:UpdateIndex",
        "aoss:DescribeIndex",
        "aoss:ReadDocument",
        "aoss:WriteDocument"
      ],
      "ResourceType": "index"
    }
  ],
  "Principal": [
    "arn:aws:iam::${AWS::AccountId}:role/${NamePrefix}-${Environment}-kb-ingestion-role",
    "arn:aws:iam::${AWS::AccountId}:role/${NamePrefix}-${Environment}-bedrock-agent-role"
  ]
}
```

### 5.3 Network Access Policy

```json
{
  "Rules": [
    {
      "Resource": ["collection/ec2-patching-knowledge-base"],
      "ResourceType": "collection"
    }
  ],
  "AllowFromPublic": false,
  "SourceVPCEs": ["vpce-0123456789abcdef0"]
}
```

### 5.4 Index Mappings

**patch-artifacts index:**
```json
{
  "settings": {
    "index": {
      "knn": true,
      "knn.algo_param.ef_search": 512
    }
  },
  "mappings": {
    "properties": {
      "doc_id": { "type": "keyword" },
      "execution_id": { "type": "keyword" },
      "account_id": { "type": "keyword" },
      "region": { "type": "keyword" },
      "instance_id": { "type": "keyword" },
      "os_type": { "type": "keyword" },
      "phase": { "type": "keyword" },
      "artifact_type": { "type": "keyword" },
      "status": { "type": "keyword" },
      "content": { 
        "type": "text",
        "analyzer": "standard"
      },
      "s3_path": { "type": "keyword" },
      "timestamp": { "type": "date" },
      "ttl": { "type": "date" },
      "embedding": {
        "type": "knn_vector",
        "dimension": 1024,
        "method": {
          "name": "hnsw",
          "space_type": "cosinesimil",
          "engine": "nmslib",
          "parameters": {
            "ef_construction": 512,
            "m": 16
          }
        }
      }
    }
  }
}
```

---

## 6. Bedrock Knowledge Base Configuration

### 6.1 Knowledge Base Definition

```yaml
KnowledgeBase:
  name: ec2-patching-knowledge-base
  description: "Knowledge base for EC2 Patching Platform containing execution history, artifacts, and operational documentation"
  roleArn: !GetAtt BedrockKnowledgeBaseRole.Arn
  
  knowledgeBaseConfiguration:
    type: VECTOR
    vectorKnowledgeBaseConfiguration:
      embeddingModelArn: "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
  
  storageConfiguration:
    type: OPENSEARCH_SERVERLESS
    opensearchServerlessConfiguration:
      collectionArn: !GetAtt OpenSearchCollection.Arn
      vectorIndexName: "patch-artifacts"
      fieldMapping:
        vectorField: "embedding"
        textField: "content"
        metadataField: "metadata"
```

### 6.2 Data Source Configurations

```yaml
DataSources:
  - name: patch-artifacts
    description: "Patch execution artifacts from S3"
    dataSourceConfiguration:
      type: S3
      s3Configuration:
        bucketArn: !GetAtt SnapshotsBucket.Arn
        inclusionPrefixes: ["runs/"]
    vectorIngestionConfiguration:
      chunkingConfiguration:
        chunkingStrategy: FIXED_SIZE
        fixedSizeChunkingConfiguration:
          maxTokens: 300
          overlapPercentage: 10
    
  - name: operational-docs
    description: "Operational documentation from S3"
    dataSourceConfiguration:
      type: S3
      s3Configuration:
        bucketArn: !GetAtt DocsBucket.Arn
        inclusionPrefixes: ["docs/"]
    vectorIngestionConfiguration:
      chunkingConfiguration:
        chunkingStrategy: SEMANTIC
        semanticChunkingConfiguration:
          maxTokens: 500
          bufferSize: 50
          breakpointPercentileThreshold: 95
```

---

## 7. CloudFormation Template

```yaml
AWSTemplateFormatVersion: '2010-09-09'
Description: EC2 Patching - Knowledge Base Pipeline Infrastructure

Parameters:
  NamePrefix:
    Type: String
    Default: ec2-patch
  Environment:
    Type: String
    AllowedValues: [dev, stage, prod]
  SnapshotsBucketName:
    Type: String
  PatchRunsTableName:
    Type: String
  VpcId:
    Type: AWS::EC2::VPC::Id
  SubnetIds:
    Type: List<AWS::EC2::Subnet::Id>

Resources:
  # OpenSearch Serverless Collection
  OpenSearchCollection:
    Type: AWS::OpenSearchServerless::Collection
    Properties:
      Name: !Sub '${NamePrefix}-${Environment}-kb'
      Type: VECTORSEARCH
      Description: Knowledge base for EC2 Patching AI Agents
    DependsOn: 
      - OpenSearchEncryptionPolicy
      - OpenSearchNetworkPolicy
      - OpenSearchDataAccessPolicy

  OpenSearchEncryptionPolicy:
    Type: AWS::OpenSearchServerless::SecurityPolicy
    Properties:
      Name: !Sub '${NamePrefix}-${Environment}-kb-encryption'
      Type: encryption
      Policy: !Sub |
        {
          "Rules": [
            {
              "Resource": ["collection/${NamePrefix}-${Environment}-kb"],
              "ResourceType": "collection"
            }
          ],
          "AWSOwnedKey": true
        }

  OpenSearchNetworkPolicy:
    Type: AWS::OpenSearchServerless::SecurityPolicy
    Properties:
      Name: !Sub '${NamePrefix}-${Environment}-kb-network'
      Type: network
      Policy: !Sub |
        [
          {
            "Rules": [
              {
                "Resource": ["collection/${NamePrefix}-${Environment}-kb"],
                "ResourceType": "collection"
              }
            ],
            "AllowFromPublic": false,
            "SourceVPCEs": ["${OpenSearchVpcEndpoint}"]
          }
        ]

  OpenSearchDataAccessPolicy:
    Type: AWS::OpenSearchServerless::AccessPolicy
    Properties:
      Name: !Sub '${NamePrefix}-${Environment}-kb-access'
      Type: data
      Policy: !Sub |
        [
          {
            "Rules": [
              {
                "Resource": ["collection/${NamePrefix}-${Environment}-kb"],
                "Permission": ["aoss:*"],
                "ResourceType": "collection"
              },
              {
                "Resource": ["index/${NamePrefix}-${Environment}-kb/*"],
                "Permission": ["aoss:*"],
                "ResourceType": "index"
              }
            ],
            "Principal": [
              "${KBIngestionRole.Arn}",
              "${BedrockAgentRole.Arn}"
            ]
          }
        ]

  OpenSearchVpcEndpoint:
    Type: AWS::OpenSearchServerless::VpcEndpoint
    Properties:
      Name: !Sub '${NamePrefix}-${Environment}-kb-vpce'
      VpcId: !Ref VpcId
      SubnetIds: !Ref SubnetIds
      SecurityGroupIds:
        - !Ref OpenSearchSecurityGroup

  OpenSearchSecurityGroup:
    Type: AWS::EC2::SecurityGroup
    Properties:
      GroupDescription: Security group for OpenSearch Serverless endpoint
      VpcId: !Ref VpcId
      SecurityGroupIngress:
        - IpProtocol: tcp
          FromPort: 443
          ToPort: 443
          SourceSecurityGroupId: !Ref LambdaSecurityGroup

  # IAM Roles
  KBIngestionRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: !Sub '${NamePrefix}-${Environment}-kb-ingestion-role'
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: lambda.amazonaws.com
            Action: sts:AssumeRole
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole
      Policies:
        - PolicyName: KBIngestionPolicy
          PolicyDocument:
            Version: '2012-10-17'
            Statement:
              - Effect: Allow
                Action:
                  - s3:GetObject
                  - s3:ListBucket
                Resource:
                  - !Sub 'arn:aws:s3:::${SnapshotsBucketName}'
                  - !Sub 'arn:aws:s3:::${SnapshotsBucketName}/*'
              - Effect: Allow
                Action:
                  - dynamodb:GetRecords
                  - dynamodb:GetShardIterator
                  - dynamodb:DescribeStream
                  - dynamodb:ListStreams
                Resource:
                  - !Sub 'arn:aws:dynamodb:${AWS::Region}:${AWS::AccountId}:table/${PatchRunsTableName}/stream/*'
              - Effect: Allow
                Action:
                  - bedrock:InvokeModel
                Resource:
                  - 'arn:aws:bedrock:*::foundation-model/amazon.titan-embed-text-v2:0'
              - Effect: Allow
                Action:
                  - aoss:APIAccessAll
                Resource:
                  - !Sub 'arn:aws:aoss:${AWS::Region}:${AWS::AccountId}:collection/*'

  BedrockAgentRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: !Sub '${NamePrefix}-${Environment}-bedrock-agent-role'
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: bedrock.amazonaws.com
            Action: sts:AssumeRole
      Policies:
        - PolicyName: BedrockAgentPolicy
          PolicyDocument:
            Version: '2012-10-17'
            Statement:
              - Effect: Allow
                Action:
                  - bedrock:InvokeModel
                Resource: '*'
              - Effect: Allow
                Action:
                  - aoss:APIAccessAll
                Resource:
                  - !Sub 'arn:aws:aoss:${AWS::Region}:${AWS::AccountId}:collection/*'

  # Lambda Functions
  S3ArtifactParserFunction:
    Type: AWS::Lambda::Function
    Properties:
      FunctionName: !Sub '${NamePrefix}-${Environment}-kb-s3-parser'
      Runtime: python3.11
      Handler: index.handler
      Role: !GetAtt KBIngestionRole.Arn
      Timeout: 300
      MemorySize: 512
      VpcConfig:
        SecurityGroupIds:
          - !Ref LambdaSecurityGroup
        SubnetIds: !Ref SubnetIds
      Environment:
        Variables:
          OPENSEARCH_ENDPOINT: !GetAtt OpenSearchCollection.CollectionEndpoint
          INDEX_NAME: patch-artifacts

  DDBStreamProcessorFunction:
    Type: AWS::Lambda::Function
    Properties:
      FunctionName: !Sub '${NamePrefix}-${Environment}-kb-ddb-processor'
      Runtime: python3.11
      Handler: index.handler
      Role: !GetAtt KBIngestionRole.Arn
      Timeout: 300
      MemorySize: 512
      VpcConfig:
        SecurityGroupIds:
          - !Ref LambdaSecurityGroup
        SubnetIds: !Ref SubnetIds
      Environment:
        Variables:
          OPENSEARCH_ENDPOINT: !GetAtt OpenSearchCollection.CollectionEndpoint
          INDEX_NAME: execution-records

  # EventBridge Rule for S3 Events
  S3EventRule:
    Type: AWS::Events::Rule
    Properties:
      Name: !Sub '${NamePrefix}-${Environment}-kb-s3-events'
      EventPattern:
        source:
          - aws.s3
        detail-type:
          - Object Created
        detail:
          bucket:
            name:
              - !Ref SnapshotsBucketName
          object:
            key:
              - prefix: 'runs/'
      Targets:
        - Id: S3ArtifactParser
          Arn: !GetAtt S3ArtifactParserFunction.Arn

  # DynamoDB Stream Event Source Mapping
  DDBStreamMapping:
    Type: AWS::Lambda::EventSourceMapping
    Properties:
      EventSourceArn: !Sub 'arn:aws:dynamodb:${AWS::Region}:${AWS::AccountId}:table/${PatchRunsTableName}/stream/*'
      FunctionName: !Ref DDBStreamProcessorFunction
      StartingPosition: LATEST
      BatchSize: 10

Outputs:
  OpenSearchCollectionEndpoint:
    Value: !GetAtt OpenSearchCollection.CollectionEndpoint
    Export:
      Name: !Sub '${NamePrefix}-${Environment}-opensearch-endpoint'
  
  KBIngestionRoleArn:
    Value: !GetAtt KBIngestionRole.Arn
    Export:
      Name: !Sub '${NamePrefix}-${Environment}-kb-ingestion-role-arn'
  
  BedrockAgentRoleArn:
    Value: !GetAtt BedrockAgentRole.Arn
    Export:
      Name: !Sub '${NamePrefix}-${Environment}-bedrock-agent-role-arn'
```

---

## 8. Data Flow Diagram

```
                                    REAL-TIME INGESTION FLOW
                                    ═══════════════════════

   ┌──────────────┐                                              ┌─────────────────┐
   │ Step         │─────────────────────────────────────────────▶│ EventBridge     │
   │ Functions    │  State Change Event                          │                 │
   │ Execution    │                                              └────────┬────────┘
   └──────────────┘                                                       │
          │                                                               │
          │ Writes artifacts                                              │ Triggers
          ▼                                                               ▼
   ┌──────────────┐    S3 Event         ┌─────────────────┐    ┌─────────────────┐
   │ S3 Bucket    │────────────────────▶│ S3 Artifact     │    │ Execution State │
   │ (Snapshots)  │                     │ Parser Lambda   │    │ Processor Lambda│
   └──────────────┘                     └────────┬────────┘    └────────┬────────┘
                                                 │                      │
                                                 │ Parse & Embed        │ Transform
                                                 ▼                      ▼
   ┌──────────────┐    DDB Stream       ┌─────────────────────────────────────────┐
   │ DynamoDB     │────────────────────▶│        EMBEDDING GENERATION             │
   │ (PatchRuns)  │                     │        (Titan Embeddings V2)            │
   └──────────────┘                     └────────────────────┬────────────────────┘
                                                             │
                                                             │ Index Documents
                                                             ▼
                                        ┌─────────────────────────────────────────┐
                                        │      OPENSEARCH SERVERLESS              │
                                        │                                         │
                                        │  ┌─────────────────────────────────┐   │
                                        │  │ patch-artifacts                 │   │
                                        │  │ execution-records               │   │
                                        │  │ operational-docs                │   │
                                        │  │ error-patterns                  │   │
                                        │  │ compliance-frameworks           │   │
                                        │  └─────────────────────────────────┘   │
                                        └─────────────────────────────────────────┘
                                                             │
                                                             │ RAG Retrieval
                                                             ▼
                                        ┌─────────────────────────────────────────┐
                                        │       BEDROCK KNOWLEDGE BASE            │
                                        │                                         │
                                        │  Hybrid Search (Semantic + Keyword)     │
                                        │  Re-ranking for Relevance               │
                                        │  Metadata Filtering                     │
                                        └─────────────────────────────────────────┘
                                                             │
                                                             │ Context for Agents
                                                             ▼
                                        ┌─────────────────────────────────────────┐
                                        │          BEDROCK AGENTS                 │
                                        │                                         │
                                        │  • Audit Agent                          │
                                        │  • Reporting Agent                      │
                                        │  • Anomaly Detection Agent              │
                                        │  • ChatOps Agent                        │
                                        │  • Predictive Agent                     │
                                        │  • Auto-Remediation Agent               │
                                        └─────────────────────────────────────────┘
```

---

## 9. Monitoring & Observability

### 9.1 CloudWatch Metrics

| Metric | Description | Alarm Threshold |
|--------|-------------|-----------------|
| `KBIngestion/DocumentsIndexed` | Documents indexed per minute | < 1 for 5 min |
| `KBIngestion/IngestionLatency` | Time from S3 event to indexed | > 30 seconds |
| `KBIngestion/IngestionErrors` | Failed indexing attempts | > 5 per hour |
| `OpenSearch/SearchLatency` | Query response time | > 5 seconds |
| `OpenSearch/IndexSize` | Index storage size | > 80% capacity |
| `Bedrock/EmbeddingLatency` | Titan embedding generation time | > 2 seconds |

### 9.2 Dashboard Widgets

```json
{
  "widgets": [
    {
      "title": "Documents Indexed (5m)",
      "type": "metric",
      "metrics": [
        ["EC2Patching/KnowledgeBase", "DocumentsIndexed", "Index", "patch-artifacts"],
        ["EC2Patching/KnowledgeBase", "DocumentsIndexed", "Index", "execution-records"]
      ]
    },
    {
      "title": "Ingestion Errors",
      "type": "metric",
      "metrics": [
        ["EC2Patching/KnowledgeBase", "IngestionErrors"]
      ]
    },
    {
      "title": "Index Size (GB)",
      "type": "metric",
      "metrics": [
        ["AWS/AOSS", "StorageUsed", "CollectionId", "${CollectionId}"]
      ]
    }
  ]
}
```

---

## 10. Data Retention & Lifecycle

| Data Type | Retention | Lifecycle Action |
|-----------|-----------|------------------|
| Patch artifacts (S3) | 90 days hot, 365 days archive | Glacier after 90 days, delete after 365 |
| Execution records (DynamoDB) | 90 days | TTL deletion |
| OpenSearch documents | 90 days | Index lifecycle policy |
| Operational docs | Indefinite | Version on update |
| Compliance frameworks | Indefinite | Version on update |

### 10.1 OpenSearch Index Lifecycle Policy

```json
{
  "policy": {
    "description": "Patch artifacts retention policy",
    "default_state": "hot",
    "states": [
      {
        "name": "hot",
        "actions": [],
        "transitions": [
          {
            "state_name": "delete",
            "conditions": {
              "min_index_age": "90d"
            }
          }
        ]
      },
      {
        "name": "delete",
        "actions": [
          {
            "delete": {}
          }
        ]
      }
    ]
  }
}
```

---

## 11. Cost Optimization

| Component | Estimated Monthly Cost | Optimization Strategy |
|-----------|------------------------|----------------------|
| OpenSearch Serverless (2 OCU) | ~$700 | Start with 2 OCU, scale based on usage |
| Titan Embeddings | ~$50 (5M tokens) | Cache embeddings for identical content |
| Lambda (ingestion) | ~$25 | Reserved concurrency, batch processing |
| S3 (index sync) | ~$10 | Lifecycle policies, avoid redundant copies |
| EventBridge | ~$1 | Minimal cost |
| **Total** | **~$786/month** | |

---

## 12. Security Considerations

1. **Encryption at Rest:** OpenSearch Serverless uses AWS-owned keys by default
2. **Encryption in Transit:** TLS 1.2+ for all connections
3. **Access Control:** IAM policies with least privilege
4. **Network Isolation:** VPC endpoints, no public access
5. **Audit Logging:** CloudTrail for all API calls
6. **Data Masking:** PII detection and masking in Lambda processors

---

*Next: Agent 1 - Audit & Compliance Agent Technical Design*
