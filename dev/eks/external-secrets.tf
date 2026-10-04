# Secret container only. Set the value out-of-band so it never lands in Terraform state:
#   aws secretsmanager put-secret-value --secret-id ticket-triage --secret-string '{"ANTHROPIC_API_KEY":"..."}'
resource "aws_secretsmanager_secret" "ticket_triage" {
  name                    = "ticket-triage"
  recovery_window_in_days = 0 # Remove this if you want to recover within 30 days
}

data "aws_iam_policy_document" "external_secrets_assume" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }

    actions = [
      "sts:AssumeRole",
      "sts:TagSession"
    ]
  }
}

resource "aws_iam_role" "external_secrets" {
  name               = "${aws_eks_cluster.eks.name}-external-secrets"
  assume_role_policy = data.aws_iam_policy_document.external_secrets_assume.json
}

data "aws_iam_policy_document" "external_secrets" {
  statement {
    effect = "Allow"

    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]

    resources = [aws_secretsmanager_secret.ticket_triage.arn]
  }
}

resource "aws_iam_role_policy" "external_secrets" {
  name   = "read-ticket-triage-secrets"
  role   = aws_iam_role.external_secrets.id
  policy = data.aws_iam_policy_document.external_secrets.json
}

resource "aws_eks_pod_identity_association" "external_secrets" {
  cluster_name    = aws_eks_cluster.eks.name
  namespace       = "external-secrets"
  service_account = "external-secrets"
  role_arn        = aws_iam_role.external_secrets.arn

  depends_on = [aws_eks_addon.pod_identity]
}

resource "helm_release" "external_secrets" {
  name = "external-secrets"

  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  namespace        = "external-secrets"
  create_namespace = true
  version          = "0.19.2"

  set = [
    {
      name  = "serviceAccount.name"
      value = "external-secrets"
  }]

  depends_on = [
    aws_eks_node_group.general,
    aws_eks_pod_identity_association.external_secrets,
  ]
}
