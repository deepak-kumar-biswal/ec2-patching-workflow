"""
Generate an AWS architecture diagram using mingrammer/diagrams.
Prereqs: Graphviz installed and on PATH; pip install diagrams.
"""

import sys

from diagrams import Cluster, Diagram, Edge
from diagrams.aws.compute import EC2, Lambda
from diagrams.aws.database import Dynamodb
from diagrams.aws.integration import Eventbridge, SNS, StepFunctions
from diagrams.aws.management import Cloudformation, Cloudwatch
from diagrams.aws.security import IAM, KMS
from diagrams.aws.storage import S3

# APIGateway import path can vary by diagrams version; add a fallback.
try:  # diagrams >= 0.20
    from diagrams.aws.network import APIGateway as APIIcon  # type: ignore
except Exception:  # pragma: no cover - fallback to a generic icon
    try:
        from diagrams.aws.general import Client as APIIcon  # type: ignore
    except Exception:  # last resort
        APIIcon = Lambda  # type: ignore


DIAGRAM_TITLE = "EC2 Patching Orchestrator (Hub-and-Spoke)"
FILENAME = "architecture"


def render() -> None:
    with Diagram(DIAGRAM_TITLE, filename=FILENAME, show=False, outformat="png"):
        # Hub
        with Cluster("Hub Account (Control Plane)"):
            eb = Eventbridge("Schedule/Trigger")
            sfn = StepFunctions("State Machine: Waves → Accounts → Regions")
            inv = Lambda("PreEC2Inventory")
            send = Lambda("SendSsmCommand")
            poll = Lambda("PollSsmCommand")
            post = Lambda("PostEC2Verify")
            authorizer = Lambda("ApprovalAuthorizer")
            approval = Lambda("ApprovalCallback")
            api = APIIcon("Approvals API")
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
            [sfn, Lambda("All Functions"), Dynamodb("Table"), S3("Bucket")] >> cw

        # Spokes
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


if __name__ == "__main__":
    try:
        render()
    except Exception as e:
        # Common failure is Graphviz 'dot' not found or diagrams import mismatch
        print(f"Failed to render diagram: {e}")
        print(
            "Hints: 1) Ensure 'dot -V' works. 2) pip install diagrams. 3) If APIGateway import fails, script falls back to a generic icon."
        )
        sys.exit(1)
