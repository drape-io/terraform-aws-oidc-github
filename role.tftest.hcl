# Plan-only: no AWS account or emulator is needed. The endpoints point at a
# closed local port so an accidental API call fails instead of reaching AWS.
provider "aws" {
  access_key = "test"
  secret_key = "test"
  region     = "us-east-1"

  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    iam = "http://127.0.0.1:1"
    sts = "http://127.0.0.1:1"
  }
}

variables {
  context           = { group = "drape", env = "dev" }
  oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
  repo              = "drape-io/terraform-aws-account"
}

run "setup" {
  command = plan

  module {
    source = "./tests/setup"
  }
}

run "test_branch_ref" {
  command = plan

  module {
    source = "./modules/role"
  }

  assert {
    condition     = toset(flatten([jsondecode(output.policy_document.json)["Statement"][0]["Condition"]["StringLike"]["token.actions.githubusercontent.com:sub"]])) == toset(["repo:drape-io/terraform-aws-account:ref:refs/heads/main"])
    error_message = "Only the default main branch should be trusted"
  }

  assert {
    condition     = jsondecode(output.policy_document.json)["Statement"][0]["Condition"]["StringEquals"]["token.actions.githubusercontent.com:aud"] == "sts.amazonaws.com"
    error_message = "Audience should be the STS client ID"
  }
}

run "test_complete_refs" {
  command = plan

  module {
    source = "./modules/role"
  }

  variables {
    git_tags            = ["v1.0.0"]
    branches            = ["production"]
    allow_pull_requests = true
  }

  assert {
    condition = toset(flatten([jsondecode(output.policy_document.json)["Statement"][0]["Condition"]["StringLike"]["token.actions.githubusercontent.com:sub"]])) == toset([
      "repo:drape-io/terraform-aws-account:ref:refs/heads/production",
      "repo:drape-io/terraform-aws-account:ref:refs/tags/v1.0.0",
      "repo:drape-io/terraform-aws-account:pull_request",
    ])
    error_message = "Branches, tags and pull requests should be trusted, and nothing else"
  }
}

run "test_allow_all" {
  command = plan

  module {
    source = "./modules/role"
  }

  variables {
    allow_all = true
    branches  = []
  }

  assert {
    condition     = toset(flatten([jsondecode(output.policy_document.json)["Statement"][0]["Condition"]["StringLike"]["token.actions.githubusercontent.com:sub"]])) == toset(["repo:drape-io/terraform-aws-account:*"])
    error_message = "allow_all should generate a single wildcard condition"
  }
}

run "test_iam_role_name" {
  command = plan

  module {
    source = "./modules/role"
  }

  variables {
    role_policies = {
      "default" : run.setup.policy
    }
  }

  assert {
    condition     = output.role.name == "drape-dev-github-drape-io-terraform-aws-account"
    error_message = "Role name wasn't generated correctly"
  }
}

run "test_iam_role_attach_policies" {
  command = plan

  module {
    source = "./modules/role"
  }

  variables {
    attach_policies = run.setup.policy_arns
  }

  assert {
    condition     = toset([for a in output.policy_attachments : a.policy_arn]) == toset(run.setup.policy_arns)
    error_message = "Exactly the given policies should be attached"
  }
}

run "test_empty_conditions_fails" {
  command = plan

  module {
    source = "./modules/role"
  }

  variables {
    branches = []
  }

  expect_failures = [
    aws_iam_role.github,
  ]
}

run "test_default_branch_only_without_other_selectors" {
  command = plan

  module {
    source = "./modules/role"
  }

  variables {
    git_tags = ["v*"]
  }

  assert {
    condition     = toset(flatten([jsondecode(output.policy_document.json)["Statement"][0]["Condition"]["StringLike"]["token.actions.githubusercontent.com:sub"]])) == toset(["repo:drape-io/terraform-aws-account:ref:refs/tags/v*"])
    error_message = "The main default should not apply when git_tags is set"
  }
}

run "test_environments" {
  command = plan

  module {
    source = "./modules/role"
  }

  variables {
    environments = ["production"]
  }

  assert {
    condition     = toset(flatten([jsondecode(output.policy_document.json)["Statement"][0]["Condition"]["StringLike"]["token.actions.githubusercontent.com:sub"]])) == toset(["repo:drape-io/terraform-aws-account:environment:production"])
    error_message = "Only the environment subject should be trusted"
  }
}

run "test_immutable_ids" {
  command = plan

  module {
    source = "./modules/role"
  }

  variables {
    repo_owner_id = 123456
    repo_id       = 456789
    environments  = ["production"]
    branches      = ["main"]
  }

  assert {
    condition = toset(flatten([jsondecode(output.policy_document.json)["Statement"][0]["Condition"]["StringLike"]["token.actions.githubusercontent.com:sub"]])) == toset([
      "repo:drape-io/terraform-aws-account:ref:refs/heads/main",
      "repo:drape-io/terraform-aws-account:environment:production",
      "repo:drape-io@123456/terraform-aws-account@456789:ref:refs/heads/main",
      "repo:drape-io@123456/terraform-aws-account@456789:environment:production",
    ])
    error_message = "Name and ID subjects should both be trusted"
  }
}

run "test_immutable_ids_skipped_for_immutable_repo" {
  command = plan

  module {
    source = "./modules/role"
  }

  variables {
    repo          = "octo-org@123456/octo-repo@456789"
    repo_owner_id = 123456
    repo_id       = 456789
  }

  assert {
    condition     = toset(flatten([jsondecode(output.policy_document.json)["Statement"][0]["Condition"]["StringLike"]["token.actions.githubusercontent.com:sub"]])) == toset(["repo:octo-org@123456/octo-repo@456789:ref:refs/heads/main"])
    error_message = "No second prefix should be added when repo is already in the immutable form"
  }
}

run "test_immutable_ids_need_both" {
  command = plan

  module {
    source = "./modules/role"
  }

  variables {
    repo_owner_id = 123456
  }

  expect_failures = [
    aws_iam_role.github,
  ]
}

run "test_long_role_name" {
  command = plan

  module {
    source = "./modules/role"
  }

  variables {
    context = { group = "myorganization", tenant = "platform", env = "production", scope = "deploy" }
    repo    = "my-org/my-quite-long-repository-name"
  }

  assert {
    condition     = output.role.name == "myorganization-platform-production-deploy-github-my-org-${substr(sha1("myorganization-platform-production-deploy-github-my-org-my-quite-long-repository-name"), 0, 8)}"
    error_message = "Names over 64 characters should be a 55-character prefix plus a hash"
  }

  assert {
    condition     = length(output.role.name) == 64
    error_message = "The shortened name should be 64 characters"
  }
}

run "test_branches_reject_colon" {
  command = plan

  module {
    source = "./modules/role"
  }

  variables {
    branches = ["main:environment:prod"]
  }

  expect_failures = [
    var.branches,
  ]
}

run "test_git_tags_reject_colon" {
  command = plan

  module {
    source = "./modules/role"
  }

  variables {
    git_tags = ["v1:pull_request"]
  }

  expect_failures = [
    var.git_tags,
  ]
}

run "test_environments_reject_colon" {
  command = plan

  module {
    source = "./modules/role"
  }

  variables {
    environments = ["prod:x"]
  }

  expect_failures = [
    var.environments,
  ]
}

run "test_attach_policies_quota" {
  command = plan

  module {
    source = "./modules/role"
  }

  variables {
    attach_policies = run.setup.too_many_policy_arns
  }

  expect_failures = [
    var.attach_policies,
  ]
}

run "test_role_policies_size" {
  command = plan

  module {
    source = "./modules/role"
  }

  variables {
    role_policies = { big = run.setup.oversized_policy }
  }

  expect_failures = [
    var.role_policies,
  ]
}

run "test_inline_policies_managed_exclusively" {
  command = plan

  module {
    source = "./modules/role"
  }

  variables {
    role_policies = { "default" : run.setup.policy }
  }

  assert {
    condition     = keys(aws_iam_role_policy.github) == ["default"]
    error_message = "Each role_policies entry should be an aws_iam_role_policy"
  }

  assert {
    condition     = aws_iam_role_policies_exclusive.github[0].policy_names == toset(["default"])
    error_message = "Exclusive management should list the configured policy names"
  }
}

run "test_no_inline_policies_removes_all" {
  command = plan

  module {
    source = "./modules/role"
  }

  variables {
    role_policies = {}
  }

  assert {
    condition     = length(aws_iam_role_policies_exclusive.github[0].policy_names) == 0
    error_message = "An empty role_policies should remove every inline policy"
  }
}

run "test_repo_accepts_valid_names" {
  command = plan

  module {
    source = "./modules/role"
  }

  variables {
    repo = "octocat_acme/my.repo_name"
  }

  assert {
    condition     = toset(flatten([jsondecode(output.policy_document.json)["Statement"][0]["Condition"]["StringLike"]["token.actions.githubusercontent.com:sub"]])) == toset(["repo:octocat_acme/my.repo_name:ref:refs/heads/main"])
    error_message = "Underscore owners (Enterprise Managed Users) and repo names with . and _ should be accepted"
  }
}

run "test_repo_accepts_immutable_form" {
  command = plan

  module {
    source = "./modules/role"
  }

  variables {
    context = { group = "prd", tenant = "ci", env = "publish" }
    repo    = "octo-org@123456/octo-repo@456789"
  }

  assert {
    condition     = output.role.name == "prd-ci-publish-github-octo-org@123456-octo-repo@456789"
    error_message = "Role name for an immutable-form repo changed"
  }

  assert {
    condition     = toset(flatten([jsondecode(output.policy_document.json)["Statement"][0]["Condition"]["StringLike"]["token.actions.githubusercontent.com:sub"]])) == toset(["repo:octo-org@123456/octo-repo@456789:ref:refs/heads/main"])
    error_message = "Trust policy for an immutable-form repo changed"
  }
}

run "test_repo_rejects_star" {
  command = plan

  module {
    source = "./modules/role"
  }

  variables {
    repo = "drape-io/*"
  }

  expect_failures = [
    var.repo,
  ]
}

run "test_repo_rejects_question_mark" {
  command = plan

  module {
    source = "./modules/role"
  }

  variables {
    repo = "drape-io/terraform-aws-accoun?"
  }

  expect_failures = [
    var.repo,
  ]
}

run "test_repo_rejects_extra_slash" {
  command = plan

  module {
    source = "./modules/role"
  }

  variables {
    repo = "drape-io/terraform/aws"
  }

  expect_failures = [
    var.repo,
  ]
}

run "test_repo_rejects_colon" {
  command = plan

  module {
    source = "./modules/role"
  }

  variables {
    repo = "drape-io/terraform-aws-account:pull_request"
  }

  expect_failures = [
    var.repo,
  ]
}

run "test_role_disabled" {
  command = plan

  module {
    source = "./modules/role"
  }

  variables {
    context = { enabled = false, group = "drape", env = "dev" }
  }

  assert {
    condition     = output.role == null
    error_message = "IAM role should not be created when enabled is false"
  }
}
