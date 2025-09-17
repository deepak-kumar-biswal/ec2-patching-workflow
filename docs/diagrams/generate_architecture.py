# Generates architecture diagrams using diagrams (https://github.com/mingrammer/diagrams)
# Prereqs: Graphviz installed and on PATH; pip install diagrams

from diagrams import Cluster, Diagram, Edge
from diagrams.aws.compute import EC2
from diagrams.aws.integration import Eventbridge
from diagrams.aws.management import Cloudwatch
from diagrams.aws.management import Cloudformation
from diagrams.aws.integration import StepFunctions
from diagrams.aws.compute import Lambda
from diagrams.aws.security import IAM
from diagrams.aws.database import Dynamodb
from diagrams.aws.storage import S3
from diagrams.aws.integration import SNS
from diagrams.aws.integration import APIGateway
from diagrams.aws.security import KMS

# Style options
DIAGRAM_TITLE = "EC2 Patching Orchestrator (Hub-and-Spoke)"
FILENAME = "architecture"

with Diagram(DIAGRAM_TITLE, filename=FILENAME, show=False, outformat="png"):
    with Cluster("Hub Account (Control Plane)"):
        eb = Eventbridge("Schedule/Trigger")
        sfn = StepFunctions("State Machine: Waves → Accounts → Regions")
        inv = Lambda("PreEC2Inventory")
        send = Lambda("SendSsmCommand")
        poll = Lambda("PollSsmCommand")
        post = Lambda("PostEC2Verify")
        authorizer = Lambda("ApprovalAuthorizer")
        approval = Lambda("ApprovalCallback")
        api = APIGateway("Approvals API")
        sns = SNS("Notifications")
        ddb = Dynamodb("Execution State (TTL/PITR)")
        s3 = S3("Artifacts & SSM Outputs (SSE-KMS)")
        kms = KMS("KMS Keys")
        cw = Cloudwatch("Dashboards & Alarms")
        cf = Cloudformation("CFN-Only Deployments")

        eb >> sfn
        sfn >> inv >> s3
        sfn >> send >> poll >> post
        sfn >> sns
        api >> authorizer >> approval >> sfn
        [inv, send, poll, post, approval] >> ddb
        [send, poll, post] >> s3
        [ddb, s3, sns] >> kms
        [sfn, Lambda("All Functions"), Dynamodb("Table") , S3("Bucket")] >> cw

    with Cluster("Spoke Accounts (Targets)"):
        with Cluster("Spoke 1..N"):
            iam = IAM("Cross-Account Execute Role (ExternalId)")
            with Cluster("Regions"):
                with Cluster("Region A..Z"):
                    ec2 = EC2("Tagged Instances")

    # Cross-account assume role path
    inv >> Edge(label="AssumeRole") >> iam
    send >> Edge(label="AssumeRole") >> iam
    poll >> Edge(label="AssumeRole") >> iam
    post >> Edge(label="AssumeRole") >> iam

    # SSM Run Command path (conceptual)
    send >> Edge(label="SSM RunPatchBaseline") >> ec2
    poll << Edge(label="GetCommandResults") << ec2
