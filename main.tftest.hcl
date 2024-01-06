provider "aws" {
  access_key = "dev-tfstate-backend"
  secret_key = "dev-tfstate-backend"
  region     = "us-east-1"

  # https://registry.terraform.io/providers/hashicorp/aws/latest/docs#s3_use_path_style
  # s3_use_path_style           = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    iam            = "http://localhost:4566"
  }
}

variables {
  context = {
    group = "drape"
    env   = "dev"
  }
  email = "group-sre@test.com"
  name  = "security"
}


run "setup" {
  module {
    source = "./tests/setup"
  }
}

run "test_branch_ref" {
  variables {
    repo = "drape-io/terraform-aws-account"
  }

  assert {
    condition     = jsondecode(data.aws_iam_policy_document.github[0].json)["Statement"][0]["Condition"]["StringLike"]["token.actions.githubusercontent.com:sub"] == "repo:drape-io/terraform-aws-account:ref:refs/heads/main"
    error_message = "Policy wasn't generated correctly"
  }
}

run "test_complete_refs" {
  variables {
    repo = "drape-io/terraform-aws-account"
    tags = ["v1.0.0"]
    branches = ["production"]
    allow_pull_requests = true
  }

  assert {
    condition     = jsondecode(
        data.aws_iam_policy_document.github[0].json
    )["Statement"][0]["Condition"]["StringLike"]["token.actions.githubusercontent.com:sub"][0] == "repo:drape-io/terraform-aws-account:ref:refs/heads/production" 
    error_message = "Branches weren't allowed properly"
  }

  assert {
    condition     = jsondecode(
        data.aws_iam_policy_document.github[0].json
    )["Statement"][0]["Condition"]["StringLike"]["token.actions.githubusercontent.com:sub"][1] == "repo:drape-io/terraform-aws-account:ref:refs/tags/v1.0.0" 
    error_message = "Tags weren't allowed properly"
  }

  assert {
    condition     = jsondecode(
        data.aws_iam_policy_document.github[0].json
    )["Statement"][0]["Condition"]["StringLike"]["token.actions.githubusercontent.com:sub"][2] == "repo:drape-io/terraform-aws-account:pull_request" 
    error_message = "Pull requests weren't allowed properly"
  }
}

run "test_iam_role" {
  variables {
    repo = "drape-io/terraform-aws-account"
    role_policies = {
        "default": run.setup.policy
    }
  }

  assert {
    condition     = aws_iam_role.github[0].name == "drape-dev-github-drape-io-terraform-aws-account"
    error_message = "Policy wasn't generated correctly"
  }
}

run "test_iam_role_attach_policies" {
  variables {
    repo = "drape-io/terraform-aws-account"
    attach_policies = run.setup.policy_arns
  }

  assert {
    condition     = aws_iam_role_policy_attachment.github[0].policy_arn == "arn:aws:iam::aws:policy/AdministratorAccess"
    error_message = "First Custom policy wasn't attached"
  }

  assert {
    condition     = aws_iam_role_policy_attachment.github[1].policy_arn == "arn:aws:iam::aws:policy/ReadOnlyAccess"
    error_message = "Second Custom policy wasn't attached"
  }
}