output "role" {
  description = "The IAM role that can be assumed by GitHub Actions for the repo"
  value       = one(aws_iam_role.github)
}

output "policy_document" {
  description = "The assume role policy document"
  value       = one(data.aws_iam_policy_document.github)
}

output "policy_attachments" {
  description = "Map of attached policy ARNs to their attachment resources"
  value       = aws_iam_role_policy_attachment.github
}
