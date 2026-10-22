# Plan-only: no AWS account or emulator is needed. The endpoints point at an
# unroutable address so an accidental API call fails instead of reaching AWS.
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

run "test_provider_created" {
  command = plan

  module {
    source = "./modules/provider"
  }

  variables {
    context = {
      group = "drape"
      env   = "dev"
    }
  }

  assert {
    condition     = length(aws_iam_openid_connect_provider.github) == 1
    error_message = "OIDC provider should be created"
  }

  assert {
    condition     = aws_iam_openid_connect_provider.github[0].url == "https://token.actions.githubusercontent.com"
    error_message = "OIDC provider URL should be the GitHub Actions token endpoint"
  }

  assert {
    condition     = aws_iam_openid_connect_provider.github[0].client_id_list == toset(["sts.amazonaws.com"])
    error_message = "OIDC provider client ID should be the STS audience"
  }
}

run "test_provider_disabled" {
  command = plan

  module {
    source = "./modules/provider"
  }

  variables {
    context = {
      enabled = false
      group   = "drape"
      env     = "dev"
    }
  }

  assert {
    condition     = output.oidc_provider == null
    error_message = "OIDC provider should not be created when enabled is false"
  }

  assert {
    condition     = output.arn == null
    error_message = "OIDC provider ARN should be null when disabled"
  }
}
