variable "context" {
  type        = any
  description = "Context object passed to terraform-null-context for labeling and tagging."
}

variable "oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider created by the provider submodule"
  type        = string
}

variable "repo" {
  description = "GitHub repository to grant access to assume a role via OIDC"
  type        = string

  # GitHub owner and repo names never contain IAM StringLike wildcards (* and ?)
  # or the ':' that separates sub claim fields, so rejecting anything outside
  # GitHub's character set keeps the trust policy scoped to exactly one repo.
  validation {
    condition     = can(regex("^[A-Za-z0-9_-]+/[A-Za-z0-9._-]+$", var.repo))
    error_message = "repo must be <owner>/<repo> using only characters GitHub allows in names (no wildcards, ':' or extra '/')."
  }
}

variable "git_tags" {
  description = "Git tags on the repo that should have access to AWS"
  type        = list(string)
  default     = []
}

variable "branches" {
  description = "Branches on the repo that should have access to AWS"
  type        = list(string)
  default     = ["main"]
}

variable "allow_pull_requests" {
  description = "Allow workflows triggered by pull requests (sub repo:<owner>/<repo>:pull_request) to assume the role."
  type        = bool
  default     = false
}

variable "allow_all" {
  description = "Trust every subject for the repo (repo:<owner>/<repo>:*): all branches, tags, pull requests and environments."
  type        = bool
  default     = false
}

variable "max_session_duration" {
  description = "Maximum session duration (in seconds) that you want for the github session."
  type        = number
  default     = 4200

  validation {
    condition     = var.max_session_duration >= 3600 && var.max_session_duration <= 43200
    error_message = "Maximum session duration must be between 3600 and 43200 seconds."
  }
}

variable "role_policies" {
  default     = {}
  description = "Inline policies to attach to the role as a key/value pair"
  type        = map(string)
}

variable "attach_policies" {
  default     = []
  description = "A list of IAM policy ARNs to attach to the role."
  type        = list(string)
}

variable "permissions_boundary" {
  default     = null
  description = "ARN of the permissions boundary policy to attach to the role."
  type        = string
}
