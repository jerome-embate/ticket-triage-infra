variable "region" {
  type        = string
  description = "AWS region to provision infrastructure."
}

variable "bucket" {
  type        = string
  description = "S3 bucket for terraform state."
}

variable "github_repos" {
  type        = map(object({
    repo_id  = number
  }))
  description = "GitHub repositories."
}

variable "github_account" {
  type        = string
  description = "GitHub account/organization that owns the repositories."
}