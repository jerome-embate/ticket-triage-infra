# IRSA: IAM OIDC identity provider for the cluster's service account tokens.
# thumbprint_list is omitted; AWS validates the EKS OIDC endpoint through its own trusted CA library.
resource "aws_iam_openid_connect_provider" "eks" {
  url            = aws_eks_cluster.eks.identity[0].oidc[0].issuer
  client_id_list = ["sts.amazonaws.com"]
}

locals {
  eks_oidc_issuer = replace(aws_eks_cluster.eks.identity[0].oidc[0].issuer, "https://", "")
}

data "aws_iam_policy_document" "flux_ecr_access_assume" {
  statement {
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test     = "StringEquals"
      variable = "${local.eks_oidc_issuer}:sub"
      values   = ["system:serviceaccount:flux-system:image-reflector-controller"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.eks_oidc_issuer}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "flux_ecr_access" {
  name               = "FluxECRAccess"
  assume_role_policy = data.aws_iam_policy_document.flux_ecr_access_assume.json
}

resource "aws_iam_role_policy_attachment" "flux_ecr_access" {
  role       = aws_iam_role.flux_ecr_access.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}
