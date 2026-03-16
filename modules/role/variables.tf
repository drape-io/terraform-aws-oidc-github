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

  validation {
    condition     = can(regex("^.+\\/.+", var.repo))
    error_message = "Repo name is not matching the pattern <owner>/<repo>."
  }

  validation {
    condition     = !can(regex("^.*\\*.*$", var.repo))
    error_message = "Wildcards are not allowed, it should be only <owner>/<repo>"
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
  description = "Should pull requests have access to AWS"
  type        = bool
  default     = false
}

variable "allow_all" {
  description = "This allows all branches, tags, and pull requests AWS access"
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
