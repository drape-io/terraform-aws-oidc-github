output "oidc_provider" {
  description = "The OIDC provider resource"
  value       = one(aws_iam_openid_connect_provider.github)
}

output "arn" {
  description = "The ARN of the OIDC provider"
  value       = one(aws_iam_openid_connect_provider.github[*].arn)
}
