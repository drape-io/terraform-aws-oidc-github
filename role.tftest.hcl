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
    repo = "drape-io/terraform-aws-account:ref:refs/heads/main"
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
