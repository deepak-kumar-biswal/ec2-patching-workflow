#############################################
# EC2 Patching Spoke (Target Account)
#############################################

# Cross-account role for hub to assume and operate SSM
data "aws_caller_identity" "current" {}

resource "aws_iam_role" "patch_exec" {
  name = var.role_name
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect="Allow",
      Principal={ AWS = "arn:aws:iam::${var.orchestrator_account_id}:root" },
      Action="sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_full" {
  role       = aws_iam_role.patch_exec.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMFullAccess"
}

resource "aws_iam_role_policy_attachment" "ec2_read" {
  role       = aws_iam_role.patch_exec.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess"
}

# Optional inline extras
resource "aws_iam_role_policy" "extras" {
  role = aws_iam_role.patch_exec.id
  policy = jsonencode({
    Version="2012-10-17",
    Statement=[
      { Effect="Allow", Action=[
          "ssm:SendCommand","ssm:GetCommandInvocation","ssm:ListCommands","ssm:ListCommandInvocations",
          "ssm:DescribeInstanceInformation","ssm:DescribeInstancePatchStates","ssm:DescribeInstancePatches"
        ], Resource="*" }
    ]
  })
}

# (Optional) Define a Patch Group via SSM Patch Baseline/Association if you don't use Default baseline.
# Tag instances with PatchGroup=default for orchestrator targeting.
