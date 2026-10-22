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
  source = "github.com/drape-io/terraform-aws-oidc-github//modules/provider"
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
  source = "github.com/drape-io/terraform-aws-oidc-github//modules/provider"
  context = {
    group = "myorg"
    env   = "production"
  }
}

module "github_oidc_roles" {
  for_each = {
    "my-org/api"      = { branches = ["main"] }
    "my-org/frontend" = { branches = ["main", "staging"], git_tags = ["v*"] }
    "my-org/infra"    = { branches = ["main"] }
  }

  source            = "github.com/drape-io/terraform-aws-oidc-github//modules/role"
  context           = { group = "myorg", env = "production" }
  oidc_provider_arn = module.github_oidc_provider.arn
  repo              = each.key
  branches          = each.value.branches
  git_tags          = try(each.value.git_tags, [])
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

Grant `id-token: write` only to the jobs that assume the role:

```yaml
jobs:
  deploy:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
    steps:
      - uses: aws-actions/configure-aws-credentials@v6
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
| allow_pull_requests | Allow workflows triggered by pull requests to assume the role | `bool` | `false` | no |
| allow_all | Trust every subject for the repo (`repo:<owner>/<repo>:*`): all branches, tags, pull requests and environments | `bool` | `false` | no |
| max_session_duration | Maximum session duration in seconds (3600-43200) | `number` | `4200` | no |
| role_policies | Inline IAM policies as key/value pairs | `map(string)` | `{}` | no |
| attach_policies | List of IAM policy ARNs to attach to the role | `list(string)` | `[]` | no |
| permissions_boundary | ARN of the permissions boundary policy | `string` | `null` | no |

| Output | Description |
|--------|-------------|
| role | The IAM role resource |
| policy_document | The assume role policy document |
| policy_attachments | Map of attached policy ARNs to their attachment resources |

## Trust policy notes

The role trusts tokens whose `sub` claim matches `repo:<owner>/<repo>:` followed by one of these:

| Input | Trusted `sub` |
|-------|---------------|
| `branches` | `ref:refs/heads/<branch>` |
| `git_tags` | `ref:refs/tags/<tag>` |
| `allow_pull_requests` | `pull_request` |
| `allow_all` | `*` (any subject) |

Branch and tag values are `StringLike` patterns: `*` matches any sequence of characters, including `/`, and `?` matches one character.

- **Pull requests.** Anyone who can open a pull request that runs workflows can change the workflow it runs. If you set `allow_pull_requests`, give pull requests their own role with read-only policies. Do not share the role that deploys from `main`.
- **Default branch events.** Workflows triggered by `workflow_run` or `issue_comment` run on the default branch and get its `ref:` subject. If you trust that branch, those jobs can assume the role, so they must not run code from a pull request.
- **Environments.** A job that sets `environment:` gets the subject `repo:<owner>/<repo>:environment:<name>`, not a `ref:` subject. Only `allow_all` matches it.
- **Immutable subjects.** GitHub uses the format `repo:<owner>@<owner-id>/<repo>@<repo-id>:...` for repositories created after July 15, 2026, for repositories renamed or transferred after that date, and for repositories that opt in. This module builds subjects from names only, so such a repository cannot assume the role.
- **Custom subject claims.** The module builds subjects for GitHub's default `sub` format. If your organization or repository customizes the `sub` claim, matching depends on the template. A template that starts with `repo` and adds more claims still matches `allow_all`, and a `*` in a branch or tag pattern also matches the claims that follow the ref. Use wildcards only with the default format.
- **AWS China.** The audience is `sts.<partition DNS suffix>`, which is `sts.amazonaws.com.cn` in `aws-cn`. Set `audience: sts.amazonaws.com.cn` on `configure-aws-credentials` there.

## Testing

Tests use [Terraform's native testing framework](https://developer.hashicorp.com/terraform/language/tests). Every run is plan-only, so no AWS account, credentials or emulator is needed:

```bash
terraform init
terraform test
```

## License

Mozilla Public License 2.0
