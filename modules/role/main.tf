module "ctx" {
  source  = "github.com/drape-io/terraform-null-context?ref=v0.0.10"
  context = var.context
}

data "aws_partition" "current" {}

locals {
  tag_refs    = [for tag in var.git_tags : format("repo:%s:ref:refs/tags/%s", var.repo, tag)]
  branch_refs = [for branch in var.branches : format("repo:%s:ref:refs/heads/%s", var.repo, branch)]
  all_refs    = var.allow_all ? [format("repo:%s:*", var.repo)] : []
  pr_refs     = var.allow_pull_requests ? [format("repo:%s:pull_request", var.repo)] : []
  conditions = concat(
    local.all_refs,
    local.branch_refs,
    local.tag_refs,
    local.pr_refs,
  )

  role_suffix = format("github-%s", replace(var.repo, "/", "-"))
  raw_name    = format("%s-%s", module.ctx.id_full, local.role_suffix)
  role_name   = length(local.raw_name) <= 64 ? local.raw_name : format("%s-%s", module.ctx.id_truncated_hash, local.role_suffix)
}

# https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect
data "aws_iam_policy_document" "github" {
  count = module.ctx.enabled ? 1 : 0
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.conditions
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.${data.aws_partition.current.dns_suffix}"]
    }
  }
}

resource "aws_iam_role" "github" {
  count                = module.ctx.enabled ? 1 : 0
  name                 = local.role_name
  assume_role_policy   = data.aws_iam_policy_document.github[0].json
  max_session_duration = var.max_session_duration
  permissions_boundary = var.permissions_boundary

  dynamic "inline_policy" {
    for_each = var.role_policies

    content {
      name   = inline_policy.key
      policy = inline_policy.value
    }
  }
  tags = module.ctx.tags

  lifecycle {
    precondition {
      condition     = length(local.conditions) > 0
      error_message = "At least one condition must be specified: set branches, git_tags, allow_pull_requests, or allow_all."
    }
  }
}

resource "aws_iam_role_policy_attachment" "github" {
  for_each   = module.ctx.enabled ? toset(var.attach_policies) : toset([])
  policy_arn = each.value
  role       = aws_iam_role.github[0].id
}
