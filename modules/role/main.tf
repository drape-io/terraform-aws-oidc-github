module "ctx" {
  source  = "github.com/drape-io/terraform-null-context?ref=v1.0.0"
  context = var.context
}

data "aws_partition" "current" {}

locals {
  # Only the old branches default applies when no other selector is set, so
  # adding git_tags, pull requests or environments does not also trust main.
  other_selectors = length(var.git_tags) > 0 || var.allow_pull_requests || length(var.environments) > 0 || var.allow_all
  branches        = var.branches != null ? var.branches : (local.other_selectors ? [] : ["main"])

  # GitHub's immutable subject format embeds the owner and repository IDs.
  # When repo already carries them (owner@id/repo@id) the name form is the
  # immutable form, so no second prefix is added.
  repo_parts = split("/", var.repo)
  with_ids   = var.repo_owner_id != null && var.repo_id != null && !strcontains(var.repo, "@")
  sub_prefixes = concat(
    ["repo:${var.repo}"],
    local.with_ids ? [format("repo:%s@%d/%s@%d", local.repo_parts[0], var.repo_owner_id, local.repo_parts[1], var.repo_id)] : [],
  )
  sub_suffixes = concat(
    var.allow_all ? ["*"] : [],
    [for branch in local.branches : "ref:refs/heads/${branch}"],
    [for tag in var.git_tags : "ref:refs/tags/${tag}"],
    var.allow_pull_requests ? ["pull_request"] : [],
    [for environment in var.environments : "environment:${environment}"],
  )
  conditions = flatten([for prefix in local.sub_prefixes : [for suffix in local.sub_suffixes : "${prefix}:${suffix}"]])

  # IAM role names are limited to 64 characters. Longer names keep a prefix
  # and end in a hash of the full name so they stay unique.
  raw_name  = format("%s-github-%s", module.ctx.id_full, replace(var.repo, "/", "-"))
  role_name = length(local.raw_name) <= 64 ? local.raw_name : format("%s-%s", substr(local.raw_name, 0, 55), substr(sha1(local.raw_name), 0, 8))
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
  tags                 = module.ctx.tags

  lifecycle {
    precondition {
      condition     = length(local.conditions) > 0
      error_message = "At least one subject must be trusted: set branches, git_tags, environments, allow_pull_requests or allow_all."
    }
    precondition {
      condition     = (var.repo_owner_id == null) == (var.repo_id == null)
      error_message = "Set both repo_owner_id and repo_id, or neither."
    }
  }
}

resource "aws_iam_role_policy" "github" {
  for_each = module.ctx.enabled ? var.role_policies : {}
  name     = each.key
  role     = aws_iam_role.github[0].id
  policy   = each.value
}

# Removes inline policies that are not in role_policies, including the last
# one when role_policies becomes empty.
resource "aws_iam_role_policies_exclusive" "github" {
  count        = module.ctx.enabled ? 1 : 0
  role_name    = aws_iam_role.github[0].name
  policy_names = keys(var.role_policies)

  depends_on = [aws_iam_role_policy.github]
}

resource "aws_iam_role_policy_attachment" "github" {
  for_each   = toset(module.ctx.enabled ? var.attach_policies : [])
  policy_arn = each.value
  role       = aws_iam_role.github[0].id
}
