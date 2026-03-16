provider "aws" {
  access_key = "dev-tfstate-backend"
  secret_key = "dev-tfstate-backend"
  region     = "us-east-1"

  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    iam = "http://localhost:4566"
    sts = "http://localhost:4566"
  }
}

run "provider" {
  module {
    source = "./modules/provider"
  }

  variables {
    context = {
      group = "drape"
      env   = "dev"
    }
  }
}

run "setup" {
  module {
    source = "./tests/setup"
  }
}

run "test_branch_ref" {
  module {
    source = "./modules/role"
  }

  variables {
    context           = { group = "drape", env = "dev" }
    oidc_provider_arn = run.provider.arn
    repo              = "drape-io/terraform-aws-account"
  }

  assert {
    condition = contains(
      flatten([jsondecode(output.policy_document.json)["Statement"][0]["Condition"]["StringLike"]["token.actions.githubusercontent.com:sub"]]),
      "repo:drape-io/terraform-aws-account:ref:refs/heads/main"
    )
    error_message = "Default branch ref for main wasn't generated"
  }
}

run "test_complete_refs" {
  module {
    source = "./modules/role"
  }

  variables {
    context             = { group = "drape", env = "dev" }
    oidc_provider_arn   = run.provider.arn
    repo                = "drape-io/terraform-aws-account"
    git_tags            = ["v1.0.0"]
    branches            = ["production"]
    allow_pull_requests = true
  }

  assert {
    condition = contains(
      flatten([jsondecode(output.policy_document.json)["Statement"][0]["Condition"]["StringLike"]["token.actions.githubusercontent.com:sub"]]),
      "repo:drape-io/terraform-aws-account:ref:refs/heads/production"
    )
    error_message = "Branches weren't allowed properly"
  }

  assert {
    condition = contains(
      flatten([jsondecode(output.policy_document.json)["Statement"][0]["Condition"]["StringLike"]["token.actions.githubusercontent.com:sub"]]),
      "repo:drape-io/terraform-aws-account:ref:refs/tags/v1.0.0"
    )
    error_message = "Tags weren't allowed properly"
  }

  assert {
    condition = contains(
      flatten([jsondecode(output.policy_document.json)["Statement"][0]["Condition"]["StringLike"]["token.actions.githubusercontent.com:sub"]]),
      "repo:drape-io/terraform-aws-account:pull_request"
    )
    error_message = "Pull requests weren't allowed properly"
  }
}

run "test_allow_all" {
  module {
    source = "./modules/role"
  }

  variables {
    context           = { group = "drape", env = "dev" }
    oidc_provider_arn = run.provider.arn
    repo              = "drape-io/terraform-aws-account"
    allow_all         = true
    branches          = []
  }

  assert {
    condition = contains(
      flatten([jsondecode(output.policy_document.json)["Statement"][0]["Condition"]["StringLike"]["token.actions.githubusercontent.com:sub"]]),
      "repo:drape-io/terraform-aws-account:*"
    )
    error_message = "allow_all should generate a wildcard condition"
  }
}

run "test_iam_role_name" {
  module {
    source = "./modules/role"
  }

  variables {
    context           = { group = "drape", env = "dev" }
    oidc_provider_arn = run.provider.arn
    repo              = "drape-io/terraform-aws-account"
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
  module {
    source = "./modules/role"
  }

  variables {
    context           = { group = "drape", env = "dev" }
    oidc_provider_arn = run.provider.arn
    repo              = "drape-io/terraform-aws-account"
    attach_policies   = run.setup.policy_arns
  }

  assert {
    condition     = output.policy_attachments[run.setup.policy_arns[0]].policy_arn == run.setup.policy_arns[0]
    error_message = "First custom policy wasn't attached"
  }

  assert {
    condition     = output.policy_attachments[run.setup.policy_arns[1]].policy_arn == run.setup.policy_arns[1]
    error_message = "Second custom policy wasn't attached"
  }
}

run "test_empty_conditions_fails" {
  module {
    source = "./modules/role"
  }

  variables {
    context             = { group = "drape", env = "dev" }
    oidc_provider_arn   = run.provider.arn
    repo                = "drape-io/terraform-aws-account"
    branches            = []
    allow_all           = false
    allow_pull_requests = false
  }

  expect_failures = [
    aws_iam_role.github,
  ]
}

run "test_role_disabled" {
  module {
    source = "./modules/role"
  }

  variables {
    context           = { enabled = false, group = "drape", env = "dev" }
    oidc_provider_arn = run.provider.arn
    repo              = "drape-io/terraform-aws-account"
  }

  assert {
    condition     = output.role == null
    error_message = "IAM role should not be created when enabled is false"
  }
}
