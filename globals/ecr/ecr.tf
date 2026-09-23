locals {
  repo_names = toset([for name, ids in var.github_repos : name])
}

module "ecr" {
  source  = "terraform-aws-modules/ecr/aws"
  version = "3.1.0"

  for_each = local.repo_names

  repository_name = lower(each.key)

  repository_lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1,
        description  = "Keep last 30 images",
        selection = {
          tagStatus = "tagged",
          tagPatternList : ["v"]
          countType   = "imageCountMoreThan",
          countNumber = 30
        },
        action = {
          type = "expire"
        }
      }
    ]
  })
}
