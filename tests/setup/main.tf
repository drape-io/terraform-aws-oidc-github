data "aws_iam_policy_document" "example" {
  statement {
    actions = [
      "sns:*",
      "lambda:*",
      "iam:*",
      "s3:*"
    ]
    effect    = "Allow"
    resources = ["*"]
  }
}

data "aws_partition" "current" {}

output "policy" {
  value       = data.aws_iam_policy_document.example.json
}

output "policy_arns" {
    value = [
        "arn:${data.aws_partition.current.partition}:iam::aws:policy/AdministratorAccess",
        "arn:${data.aws_partition.current.partition}:iam::aws:policy/ReadOnlyAccess"
    ]
}
