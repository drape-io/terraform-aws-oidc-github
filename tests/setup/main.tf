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
  value = data.aws_iam_policy_document.example.json
}

output "policy_arns" {
  value = [
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/AdministratorAccess",
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/ReadOnlyAccess"
  ]
}

# One more ARN than IAM allows on a role.
output "too_many_policy_arns" {
  value = [for i in range(26) : "arn:${data.aws_partition.current.partition}:iam::123456789012:policy/p${i}"]
}

# An inline policy over IAM's 10,240-character limit per role.
output "oversized_policy" {
  value = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "s3:GetObject"
      Resource = [for i in range(400) : "arn:${data.aws_partition.current.partition}:s3:::bucket-${i}/*"]
    }]
  })
}
