output "role" {
  description = "The role that can be assumed for the repo"
  value       = aws_iam_role.github
}