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
try:
    from diagrams.generic.blank import Blank as TextNode  # type: ignore
except Exception:  # fallback
    TextNode = Lambda  # type: ignore

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

# Layout and style
GRAPH_ATTR = {
    "bgcolor": "white",
    "pad": "0.5",
    "ranksep": "1.0",
    "nodesep": "0.6",
    "labelloc": "t",
    "fontsize": "20",
    "concentrate": "true",
}
NODE_ATTR = {"shape": "box", "fontname": "Segoe UI", "fontsize": "12"}
EDGE_ATTR = {"color": "gray40", "fontsize": "10"}


def render(outfmt: str = "png") -> None:
    with Diagram(
        DIAGRAM_TITLE,
        filename=FILENAME,
        show=False,
        outformat=outfmt,
        direction="LR",
        graph_attr=GRAPH_ATTR,
        node_attr=NODE_ATTR,
        edge_attr=EDGE_ATTR,
    ):
        # Hub
        with Cluster("Hub Account (Control Plane)"):
            with Cluster("Orchestration"):
                eb = Eventbridge("Schedule / Trigger")
                sfn = StepFunctions("State Machine\nWaves → Accounts → Regions")

            with Cluster("Patching Lambdas"):
                inv = Lambda("PreEC2Inventory")
                send = Lambda("SendSsmCommand")
                poll = Lambda("PollSsmCommand")
                post = Lambda("PostEC2Verify")

            with Cluster("Approval Flow"):
                api = APIIcon("Approvals API")
                authorizer = Lambda("ApprovalAuthorizer")
                approval = Lambda("ApprovalCallback")
                rejected = Lambda("Rejected")

            with Cluster("Data & Storage"):
                ddb = Dynamodb("Execution State\n(TTL / PITR)")
                s3 = S3("Artifacts & Outputs\n(SSE-KMS)")

            with Cluster("Notifications & Observability"):
                sns = SNS("Notifications")
                cw = Cloudwatch("Dashboards & Alarms")

            with Cluster("Security & Keys"):
                kms = KMS("KMS Keys")

            with Cluster("Deployment"):
                cf = Cloudformation("CFN-Only Deployments")

            # Hub flows
            eb >> sfn
            sfn >> inv
            sfn >> send
            sfn >> poll
            sfn >> post
            sfn >> sns

            # API Gateway Authorizer: green allow, red reject
            authorizer_allow = Edge(color="darkgreen", label="Allow", penwidth="2.0")
            authorizer_deny = Edge(color="red", style="dashed", label="Deny")
            api >> Edge(color="gray40", label="AuthN/AuthZ") >> authorizer
            authorizer >> authorizer_allow >> approval
            authorizer >> authorizer_deny >> rejected
            approval >> sfn

            for fn in [inv, send, poll, post, approval]:
                fn >> ddb

            for fn in [send, poll, post]:
                fn >> s3

            for svc in [ddb, s3, sns]:
                svc >> kms

            for src in [sfn, ddb, s3]:
                src >> cw

        # Parameters & Limits section removed for a cleaner layout

        # Spokes (split by OS)
        with Cluster("Spoke Accounts (Targets)"):
            with Cluster("Spoke 1..N"):
                iam = IAM("Cross-Account Execute Role\n(ExternalId)")
                with Cluster("Regions"):
                    with Cluster("Region A..Z"):
                        with Cluster("Windows Targets"):
                            ec2_win = EC2("Windows (Tagged)")
                        with Cluster("Linux Targets"):
                            ec2_lin = EC2("Linux (Tagged)")

        # Cross-account assume role path
        for fn in [inv, send, poll, post]:
            fn >> Edge(label="AssumeRole", style="dashed", color="gray50") >> iam

        # SSM Run Command path (conceptual)
        send >> Edge(label="RunPatchBaseline", color="steelblue") >> ec2_win
        send >> Edge(label="RunPatchBaseline", color="steelblue") >> ec2_lin
        poll << Edge(label="GetResults", color="steelblue") << ec2_win
        poll << Edge(label="GetResults", color="steelblue") << ec2_lin

        # Legend removed for a cleaner, less cluttered SVG output


if __name__ == "__main__":
    try:
        # Render both PNG and SVG for crisp docs embeds
        render("png")
        render("svg")
    except Exception as e:
        # Common failure is Graphviz 'dot' not found or diagrams import mismatch
        print(f"Failed to render diagram: {e}")
        print(
            "Hints: 1) Ensure 'dot -V' works. 2) pip install diagrams. 3) If APIGateway import fails, script falls back to a generic icon."
        )
        sys.exit(1)
