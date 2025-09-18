"""
Generate an AWS architecture diagram for the Simplified EC2 Patching Orchestrator.
Prereqs: Graphviz installed and on PATH; pip install diagrams.

Key Simplifications:
- No manual approval workflow
- Single unified IAM role
- EventBridge scheduled automation  
- Direct execution flow
- Optional SNS notifications for operational visibility
- Support for custom SSM documents (Windows/Linux pre/patch/post)
"""

import sys

from diagrams import Cluster, Diagram, Edge
from diagrams.aws.compute import EC2, Lambda
from diagrams.aws.database import Dynamodb
from diagrams.aws.integration import Eventbridge, StepFunctions, SNS
from diagrams.aws.management import Cloudformation, Cloudwatch
from diagrams.aws.security import IAM, KMS
from diagrams.aws.storage import S3
try:
    from diagrams.generic.blank import Blank as TextNode  # type: ignore
except Exception:  # fallback
    TextNode = Lambda  # type: ignore


DIAGRAM_TITLE = "EC2 Patching Orchestrator (Simplified Hub-and-Spoke)"
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
        with Cluster("Hub Account (Simplified Control Plane)"):
            with Cluster("Orchestration"):
                eb = Eventbridge("EventBridge\nScheduled Trigger")
                sfn = StepFunctions("State Machine\nDirect Execution")

            with Cluster("Core Lambdas (4 Functions)"):
                inv = Lambda("PreEC2Inventory")
                send = Lambda("SendSsmCommand")
                poll = Lambda("PollSsmCommand")
                post = Lambda("PostEC2Verify")

            with Cluster("Unified Security"):
                iam_unified = IAM("UnifiedExecutionRole\n(Single IAM Role)")

            with Cluster("Data & Storage"):
                ddb = Dynamodb("Execution State\n(TTL / PITR)")
                s3 = S3("Artifacts & Outputs\n(SSE-KMS)")

            with Cluster("Observability"):
                cw = Cloudwatch("Dashboards & Alarms")

            with Cluster("Notifications"):
                sns = SNS("SNS Topic\n(Optional Email)")

            with Cluster("Security & Keys"):
                kms = KMS("KMS Keys")

            with Cluster("Deployment"):
                cf = Cloudformation("CFN-Only Deployments")

            with Cluster("Custom SSM Documents (Optional)"):
                with Cluster("Windows Documents"):
                    win_pre = TextNode("WindowsPrePatch")
                    win_patch = TextNode("WindowsPatch")
                    win_post = TextNode("WindowsPostPatch")
                with Cluster("Linux Documents"):
                    lin_pre = TextNode("LinuxPrePatch")
                    lin_patch = TextNode("LinuxPatch")
                    lin_post = TextNode("LinuxPostPatch")

            # Simplified hub flows
            eb >> sfn
            sfn >> inv
            sfn >> send
            sfn >> poll
            sfn >> post

            # All Lambda functions use unified role
            for fn in [inv, send, poll, post]:
                iam_unified >> fn
                fn >> ddb

            for fn in [send, poll, post]:
                fn >> s3

            for svc in [ddb, s3, sns]:
                svc >> kms

            for src in [sfn, ddb, s3]:
                src >> cw

            # CloudWatch alarms trigger SNS notifications
            cw >> Edge(label="Alerts", color="orange") >> sns

            # Lambda functions can send notifications
            for fn in [inv, send, poll, post]:
                fn >> Edge(label="Status", style="dotted", color="orange") >> sns

            # Custom SSM Documents connections (optional workflow)
            send >> Edge(label="PrePatch", style="dashed", color="purple") >> win_pre
            send >> Edge(label="Patch", style="dashed", color="purple") >> win_patch
            send >> Edge(label="PostPatch", style="dashed", color="purple") >> win_post
            send >> Edge(label="PrePatch", style="dashed", color="purple") >> lin_pre
            send >> Edge(label="Patch", style="dashed", color="purple") >> lin_patch
            send >> Edge(label="PostPatch", style="dashed", color="purple") >> lin_post

        # Parameters & Limits section removed for a cleaner layout

        # Spokes (split by OS) - arrange horizontally
        with Cluster("Spoke Accounts (Targets)"):
            with Cluster("Spoke 1..N"):
                iam = IAM("Cross-Account Execute Role\n(ExternalId)")
                with Cluster("Regions"):
                    # Keep OS targets on the same horizontal rank within each region
                    with Cluster("Region A..Z", graph_attr={"rank": "same"}):
                        ec2_win = EC2("Windows (Tagged)")
                        ec2_lin = EC2("Linux (Tagged)")
                        # Invisible edge nudges Graphviz to keep them side-by-side
                        ec2_win >> Edge(style="invis", weight="100", constraint="true") >> ec2_lin

        # Cross-account assume role path
        for fn in [inv, send, poll, post]:
            fn >> Edge(label="AssumeRole", style="dashed", color="gray50", constraint="false") >> iam

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
