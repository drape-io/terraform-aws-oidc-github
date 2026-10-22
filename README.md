# terraform-aws-oidc-github

This Terraform module creates OpenID Connect (OIDC) trust between AWS and GitHub Actions. Your workflows assume an IAM role directly, so you do not keep long-lived AWS credentials in repository secrets.

## Architecture

The module has two submodules:

- **`modules/provider`** creates the GitHub OIDC provider. Use one per AWS account.
- **`modules/role`** creates an IAM role that trusts the OIDC provider. Use one per repository.

AWS allows one OIDC provider for each URL in an account. Create the provider once and pass its ARN to every role.

## Usage

### Single repo

```hcl
module "github_oidc_provider" {
  source = "github.com/drape-io/terraform-aws-oidc-github//modules/provider?ref=v1.0.0"
  context = {
    group = "myorg"
    env   = "production"
  }
}

module "github_oidc_role" {
  source            = "github.com/drape-io/terraform-aws-oidc-github//modules/role?ref=v1.0.0"
  context           = { group = "myorg", env = "production" }
  oidc_provider_arn = module.github_oidc_provider.arn
  repo              = "my-org/my-repo"
  branches          = ["main"]
}
```

### Multiple repos

```hcl
module "github_oidc_provider" {
  source = "github.com/drape-io/terraform-aws-oidc-github//modules/provider?ref=v1.0.0"
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

  source            = "github.com/drape-io/terraform-aws-oidc-github//modules/role?ref=v1.0.0"
  context           = { group = "myorg", env = "production" }
  oidc_provider_arn = module.github_oidc_provider.arn
  repo              = each.key
  branches          = each.value.branches
  git_tags          = try(each.value.git_tags, [])
}
```

### Deploy from an environment

A job that sets `environment:` gets an environment subject, not a branch subject. When you set `environments` and leave `branches` unset, the role does not trust `main`:

```hcl
module "github_oidc_deploy_role" {
  source            = "github.com/drape-io/terraform-aws-oidc-github//modules/role?ref=v1.0.0"
  context           = { group = "myorg", env = "production" }
  oidc_provider_arn = module.github_oidc_provider.arn
  repo              = "my-org/my-repo"
  environments      = ["production"]
}
```

Protect the environment with required reviewers or deployment branch rules. GitHub creates an environment when a workflow first uses its name, so an unprotected environment adds no control.

### Repositories with immutable subjects

Set `repo_owner_id` and `repo_id` to also trust GitHub's immutable subject format. This command prints the owner ID and the repository ID:

```bash
gh api repos/<owner>/<repo> --jq '.owner.id, .id'
```

```hcl
module "github_oidc_role" {
  source            = "github.com/drape-io/terraform-aws-oidc-github//modules/role?ref=v1.0.0"
  context           = { group = "myorg", env = "production" }
  oidc_provider_arn = module.github_oidc_provider.arn
  repo              = "my-org/my-repo"
  repo_owner_id     = 123456
  repo_id           = 456789
  branches          = ["main"]
}
```

### Attach IAM policies

```hcl
module "github_oidc_role" {
  source            = "github.com/drape-io/terraform-aws-oidc-github//modules/role?ref=v1.0.0"
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
| terraform | >= 1.6.6 |
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

Creates an IAM role that GitHub Actions workflows assume through OIDC.

| Input | Description | Type | Default | Required |
|-------|-------------|------|---------|----------|
| context | Context object for labeling | `any` | n/a | yes |
| oidc_provider_arn | ARN of the GitHub OIDC provider | `string` | n/a | yes |
| repo | GitHub repository as `owner/repo`, or `owner@id/repo@id` | `string` | n/a | yes |
| repo_owner_id | Numeric owner ID. With `repo_id`, also trusts the immutable subject format | `number` | `null` | no |
| repo_id | Numeric repository ID. Set it together with `repo_owner_id` | `number` | `null` | no |
| branches | Branches whose workflows can assume the role. When `null`, the role trusts `main` only if no other selector is set | `list(string)` | `null` | no |
| environments | Environments whose jobs can assume the role | `list(string)` | `[]` | no |
| git_tags | Git tags whose workflows can assume the role | `list(string)` | `[]` | no |
| allow_pull_requests | Allow workflows triggered by pull requests to assume the role | `bool` | `false` | no |
| allow_all | Trust every subject for the repo (`repo:<owner>/<repo>:*`): all branches, tags, pull requests and environments | `bool` | `false` | no |
| max_session_duration | Maximum session duration in seconds (3600 to 43200) | `number` | `4200` | no |
| role_policies | Inline IAM policies, as a map of policy name to policy JSON | `map(string)` | `{}` | no |
| attach_policies | List of IAM policy ARNs to attach to the role | `list(string)` | `[]` | no |
| permissions_boundary | ARN of the permissions boundary policy | `string` | `null` | no |

| Output | Description |
|--------|-------------|
| role | The IAM role resource |
| policy_document | The assume role policy document |
| policy_attachments | Map of attached policy ARNs to their attachment resources |

## Trust policy notes

The role trusts tokens whose `sub` claim is `repo:<owner>/<repo>:` plus one of these suffixes:

| Input | Trusted `sub` |
|-------|---------------|
| `branches` | `ref:refs/heads/<branch>` |
| `git_tags` | `ref:refs/tags/<tag>` |
| `allow_pull_requests` | `pull_request` |
| `environments` | `environment:<name>` |
| `allow_all` | `*` (any subject) |

When you set `repo_owner_id` and `repo_id`, the role also trusts each suffix after `repo:<owner>@<owner-id>/<repo>@<repo-id>:`.

Branch, tag and environment values are `StringLike` patterns. They cannot contain `:`. `*` matches any sequence of characters, including `/`. `?` matches one character.

- **Pull requests.** A pull request can change the workflow that it runs. If you set `allow_pull_requests`, give pull requests their own role with read-only policies. Do not share the role that deploys from `main`.
- **Default branch events.** `workflow_run` and `issue_comment` workflows run on the default branch and get its `ref:` subject. If you trust that branch, those jobs can assume the role. Do not let them run code from a pull request.
- **Environments.** A job that sets `environment:` gets an `environment:` subject, not a `ref:` subject. Branch and tag patterns do not match it. Use `environments` or `allow_all`.
- **Immutable subjects.** GitHub uses the format `repo:<owner>@<owner-id>/<repo>@<repo-id>:...` for some repositories:
  - repositories created after July 15, 2026
  - repositories renamed or transferred after that date
  - repositories that opt in

  Set `repo_owner_id` and `repo_id` to trust these subjects. You can also pass the immutable form as `repo` directly.
- **Custom subject claims.** The module builds subjects for GitHub's default `sub` format. If you customize the `sub` claim, matching depends on the template. A template that starts with `repo` and adds more claims still matches `allow_all`. A `*` in a branch or tag pattern also matches the claims after the ref. Use wildcards only with the default format.
- **AWS China.** The audience is `sts.<partition DNS suffix>`, which is `sts.amazonaws.com.cn` in `aws-cn`. Set `audience: sts.amazonaws.com.cn` on `configure-aws-credentials` there.

## Testing

Tests use [Terraform's native testing framework](https://developer.hashicorp.com/terraform/language/tests). Every run is plan-only, so you do not need an AWS account, credentials or an emulator:

```bash
terraform init
terraform test
```

## License

Mozilla Public License 2.0
