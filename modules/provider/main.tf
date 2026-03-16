module "ctx" {
  source  = "github.com/drape-io/terraform-null-context?ref=v0.0.10"
  context = var.context
}

resource "aws_iam_openid_connect_provider" "github" {
  count          = module.ctx.enabled ? 1 : 0
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.${data.aws_partition.current.dns_suffix}"]

  tags = module.ctx.tags
}

data "aws_partition" "current" {}
