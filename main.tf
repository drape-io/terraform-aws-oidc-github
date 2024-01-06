data "aws_partition" "current" {}

data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

# Create the OIDC Provider in the AWS Account
resource "aws_iam_openid_connect_provider" "github" {
  count          = module.ctx.enabled ? 1 : 0
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  thumbprint_list = [
    data.tls_certificate.github.certificates[0].sha1_fingerprint
  ]

  tags = module.ctx.tags
}

locals {
  tag_refs    = [for tag in var.tags : format("repo:%s:ref:refs/tags/%s", var.repo, tag)]
  branch_refs = [for tag in var.branches : format("repo:%s:ref:refs/heads/%s", var.repo, tag)]
  all_refs    = var.allow_all ? [format("repo:%s/*", var.repo)] : []
  pr_refs     = var.allow_pull_requests ? [format("repo:%s:pull_request", var.repo)] : []
  conditions = concat(
    local.all_refs,
    local.branch_refs,
    local.tag_refs,
    local.pr_refs,
  )
}

# https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect
data "aws_iam_policy_document" "github" {
  count = module.ctx.enabled ? 1 : 0
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github[0].arn]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.conditions
    }
  }
}

resource "aws_iam_role" "github" {
  count                = module.ctx.enabled ? 1 : 0
  name                 = format("%s-%s-%s", module.ctx.id_full, "github", replace(var.repo, "/", "-"))
  assume_role_policy   = data.aws_iam_policy_document.github[0].json
  max_session_duration = var.max_session_duration

  dynamic "inline_policy" {
    for_each = var.role_policies

    content {
      name   = inline_policy.key
      policy = inline_policy.value
    }
  }
  tags = module.ctx.tags
}

resource "aws_iam_role_policy_attachment" "github" {
  count      = module.ctx.enabled ? length(var.attach_policies) : 0
  policy_arn = var.attach_policies[count.index]
  role       = aws_iam_role.github[0].id
}