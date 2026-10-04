# ticket-triage-infra

Terraform for the AWS infrastructure behind `ticket-triage-agent`: a VPC, an EKS cluster, container registries, CI access for GitHub Actions, and the IAM wiring for in-cluster controllers.

## Layout

The code is split into independent Terraform root modules, each with its own state file in a shared S3 bucket.

```
globals/                  # Account-wide resources, shared by every environment
├── global.tfvars         # Shared variables (region, state bucket, GitHub repos)
├── state.config          # Backend config for `terraform init`
├── s3/                   # S3 bucket that holds all Terraform state
├── ecr/                  # One ECR repository per entry in `github_repos`
└── iam/                  # GitHub Actions OIDC provider and the `github-actions` role
dev/                      # The `dev` environment
├── dev.tfvars            # Environment variables (region, env, cluster name, state bucket)
├── state.config          # Backend config for `terraform init`
├── vpc/                  # VPC, subnets, single NAT gateway
└── eks/                  # EKS cluster, node group, add-ons, and controllers
```

### globals

| Module | What it creates |
| --- | --- |
| `s3` | `ticket-triage-terraform-state` bucket, with versioning, AES256 encryption, and all public access blocked. |
| `ecr` | An ECR repository for each key in `github_repos`. A lifecycle rule keeps the 30 most recent `v*`-tagged images. |
| `iam` | GitHub Actions OIDC identity provider, plus a `github-actions` role that can push to those ECR repositories. Only workflows running on branches of the listed repos can assume the role. |

### dev

| Module | What it creates |
| --- | --- |
| `vpc` | `10.0.0.0/16` VPC in `us-east-1a`/`us-east-1b` with two public and two private subnets, and one NAT gateway on a dedicated Elastic IP. Subnets carry the tags the AWS Load Balancer Controller looks for. |
| `eks` | The `dev-main` EKS cluster (Kubernetes 1.33) and its resources, listed below. |

The `eks` module reads the VPC and subnet IDs from the `vpc` module's remote state, and creates:

- **Cluster:** API authentication mode, a public endpoint, and nodes in private subnets.
- **Node group `general`:** 2 × `t3.large` on-demand nodes, all in the first private subnet so traffic between nodes stays in one AZ and doesn't incur cross-AZ charges.
- **EKS Pod Identity Agent** add-on.
- **AWS Load Balancer Controller** (Helm chart 1.13.4). It gets its IAM role through Pod Identity.
- **External Secrets Operator** (Helm chart 0.19.2). Through Pod Identity it can read the `ticket-triage` Secrets Manager secret.
- **Flux image automation:** an IAM OIDC provider for the cluster and a `FluxECRAccess` role, assumed through IRSA by Flux's `image-reflector-controller` to read from ECR.

## Prerequisites

- Terraform >= 1.0. The S3 backend is configured with `use_lockfile`, which needs Terraform 1.10 or newer.
- AWS credentials with admin-level access to the target account.
- `kubectl` and the AWS CLI, to work with the cluster after it's created.

## Usage

Run every command from inside the module directory. Each module is initialized with its parent folder's `state.config` and planned or applied with its parent folder's tfvars file. The `dev` modules also take their own tfvars file.

### 1. Bootstrap the state bucket (first time only)

The `globals/s3` module creates the bucket that its own state is stored in. For the first run, apply it with local state and then migrate that state into the bucket:

```sh
cd globals/s3
mv state.tf state.tf.bak                     # temporarily use local state
terraform init
terraform apply -var-file=../global.tfvars
mv state.tf.bak state.tf
terraform init -backend-config=../state.config -migrate-state
```

### 2. Global resources

```sh
cd globals/ecr
terraform init -backend-config=../state.config
terraform apply -var-file=../global.tfvars

cd ../iam
terraform init -backend-config=../state.config
terraform apply -var-file=../global.tfvars
```

### 3. dev environment

Apply `vpc` first, because `eks` reads its outputs:

```sh
cd dev/vpc
terraform init -backend-config=../state.config
terraform apply -var-file=../dev.tfvars -var-file=vpc.tfvars

cd ../eks
terraform init -backend-config=../state.config
terraform apply -var-file=../dev.tfvars -var-file=eks.tfvars
```

Then point `kubectl` at the cluster:

```sh
aws eks update-kubeconfig --region us-east-1 --name dev-main
```

### 4. Set the application secret

Terraform creates the `ticket-triage` secret without a value, so the API key never ends up in Terraform state. Set the value yourself:

```sh
aws secretsmanager put-secret-value \
  --secret-id ticket-triage \
  --secret-string '{"ANTHROPIC_API_KEY":"..."}'
```

## Outputs

| Module | Output | Description |
| --- | --- | --- |
| `globals/s3` | `bucket` | Name of the state bucket. |
| `dev/vpc` | `vpc_id`, `private_subnet_ids`, `public_subnet_ids` | Network IDs. `dev/eks` reads these. |
| `dev/eks` | `cluster_security_group_id` | Security group EKS created for the cluster. |
| `dev/eks` | `flux_ecr_access_role_arn` | Role ARN to put in the `eks.amazonaws.com/role-arn` annotation on Flux's `image-reflector-controller` service account. |

## Adding a GitHub repository

Add the repository to `github_repos` in `globals/global.tfvars`, using its numeric repository ID, then apply `globals/ecr` and `globals/iam`:

```hcl
github_repos = {
  "ticket-triage-agent" = { repo_id = 1376692341 }
  "another-service"     = { repo_id = 1234567890 }
}
```

You can look up a repository's ID with `gh api repos/<owner>/<repo> --jq .id`.

## Tearing down

Destroy the modules in the reverse order you applied them: `dev/eks`, `dev/vpc`, `globals/iam`, `globals/ecr`, then `globals/s3`. Before destroying `globals/s3`, migrate its state back to local, because Terraform can't delete the bucket that holds its own state.
