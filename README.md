# terraform-aws-oidc-github

Terraform module for creating an OIDC trust relationship between AWS and GitHub Actions. This allows GitHub Actions workflows to assume an IAM role without storing long-lived AWS credentials as secrets.

## Architecture

This module is split into two submodules:

- **`modules/provider`** — Creates the GitHub OIDC provider (one per AWS account)
- **`modules/role`** — Creates an IAM role trusted by the OIDC provider (one per repo)

AWS enforces a single OIDC provider per URL per account, so the provider is created once and shared across all roles.

## Usage

### Single repo

```hcl
module "github_oidc_provider" {
  source  = "github.com/drape-io/terraform-aws-oidc-github//modules/provider"
  context = {
    group = "myorg"
    env   = "production"
  }
}

module "github_oidc_role" {
  source            = "github.com/drape-io/terraform-aws-oidc-github//modules/role"
  context           = { group = "myorg", env = "production" }
  oidc_provider_arn = module.github_oidc_provider.arn
  repo              = "my-org/my-repo"
  branches          = ["main"]
}
```

### Multiple repos

```hcl
module "github_oidc_provider" {
  source  = "github.com/drape-io/terraform-aws-oidc-github//modules/provider"
  context = {
    group = "myorg"
    env   = "production"
  }
}

module "github_oidc_roles" {
  for_each = {
    "my-org/api"      = { branches = ["main"] }
    "my-org/frontend" = { branches = ["main", "staging"], git_tags = ["v*"] }
    "my-org/infra"    = { branches = ["main"], allow_pull_requests = true }
  }

  source            = "github.com/drape-io/terraform-aws-oidc-github//modules/role"
  context           = { group = "myorg", env = "production" }
  oidc_provider_arn = module.github_oidc_provider.arn
  repo              = each.key
  branches          = each.value.branches
  git_tags          = try(each.value.git_tags, [])
  allow_pull_requests = try(each.value.allow_pull_requests, false)
}
```

### Attach IAM policies

```hcl
module "github_oidc_role" {
  source            = "github.com/drape-io/terraform-aws-oidc-github//modules/role"
  context           = { group = "myorg", env = "production" }
  oidc_provider_arn = module.github_oidc_provider.arn
  repo              = "my-org/my-repo"

  attach_policies = [
    "arn:aws:iam::aws:policy/ReadOnlyAccess",
  ]

  role_policies = {
    deploy = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject"]
        Resource = ["arn:aws:s3:::my-bucket/*"]
      }]
    })
  }
}
```

### Use in GitHub Actions

```yaml
permissions:
  id-token: write
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: us-east-1
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.6 |
| aws | >= 5.82 |

## Submodules

### `modules/provider`

Creates the GitHub Actions OIDC provider in your AWS account.

| Input | Description | Type | Default | Required |
|-------|-------------|------|---------|----------|
| context | Context object for labeling | `any` | n/a | yes |

| Output | Description |
|--------|-------------|
| oidc_provider | The OIDC provider resource |
| arn | The ARN of the OIDC provider |

### `modules/role`

Creates an IAM role that can be assumed by GitHub Actions via OIDC.

| Input | Description | Type | Default | Required |
|-------|-------------|------|---------|----------|
| context | Context object for labeling | `any` | n/a | yes |
| oidc_provider_arn | ARN of the GitHub OIDC provider | `string` | n/a | yes |
| repo | GitHub repository in `owner/repo` format | `string` | n/a | yes |
| branches | Branches that should have access to AWS | `list(string)` | `["main"]` | no |
| git_tags | Git tags that should have access to AWS | `list(string)` | `[]` | no |
| allow_pull_requests | Allow pull requests to assume the role | `bool` | `false` | no |
| allow_all | Allow all branches, tags, and pull requests | `bool` | `false` | no |
| max_session_duration | Maximum session duration in seconds (3600-43200) | `number` | `4200` | no |
| role_policies | Inline IAM policies as key/value pairs | `map(string)` | `{}` | no |
| attach_policies | List of IAM policy ARNs to attach to the role | `list(string)` | `[]` | no |
| permissions_boundary | ARN of the permissions boundary policy | `string` | `null` | no |

| Output | Description |
|--------|-------------|
| role | The IAM role resource |
| policy_document | The assume role policy document |
| policy_attachments | Map of attached policy ARNs |

## Testing

Tests use [Terraform's native testing framework](https://developer.hashicorp.com/terraform/language/tests) with LocalStack:

```bash
# Start LocalStack
docker run -d -p 4566:4566 localstack/localstack

# Run tests
terraform init
terraform test
```

## License

Mozilla Public License 2.0
