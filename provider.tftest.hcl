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

run "test_provider_created" {
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
    condition     = output.oidc_provider != null
    error_message = "OIDC provider should be created"
  }

  assert {
    condition     = output.oidc_provider.url == "token.actions.githubusercontent.com"
    error_message = "OIDC provider URL should be the GitHub Actions token endpoint"
  }

  assert {
    condition     = output.arn != null
    error_message = "OIDC provider ARN should be output"
  }
}

run "test_provider_disabled" {
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
