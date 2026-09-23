data "aws_eks_cluster" "eks" {
  name = aws_eks_cluster.eks.name
}

data "aws_eks_cluster_auth" "eks" {
  name = aws_eks_cluster.eks.name
}

data "terraform_remote_state" "vpc" {
  backend = "s3"
  config = {
    bucket = var.bucket
    key    = "dev/vpc/terraform.tfstate"
    region = var.region
  }
}
