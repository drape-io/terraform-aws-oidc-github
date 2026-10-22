variable "context" {
  type        = any
  description = "Context object passed to terraform-null-context for labeling and tagging."
}

variable "oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider created by the provider submodule"
  type        = string
}

variable "repo" {
  description = "GitHub repository, in <owner>/<repo> format, whose workflows can assume the role."
  type        = string

  # GitHub names can't contain IAM StringLike wildcards (* and ?) or the ':'
  # that separates sub claim fields, so this keeps the trust policy to one repo.
  # The optional @<digits> suffixes accept GitHub's immutable subject form.
  validation {
    condition     = can(regex("^[A-Za-z0-9_-]+(@[0-9]+)?/[A-Za-z0-9._-]+(@[0-9]+)?$", var.repo))
    error_message = "repo must be <owner>/<repo> or <owner>@<id>/<repo>@<id>, using only characters GitHub allows in names (no wildcards, ':' or extra '/')."
  }
}

variable "repo_owner_id" {
  description = "Numeric ID of the repository owner. With repo_id, also trusts GitHub's immutable subject format (repo:<owner>@<owner_id>/<repo>@<repo_id>:...)."
  type        = number
  default     = null

  validation {
    condition     = var.repo_owner_id == null ? true : var.repo_owner_id > 0 && floor(var.repo_owner_id) == var.repo_owner_id
    error_message = "repo_owner_id must be a positive integer."
  }
}

variable "repo_id" {
  description = "Numeric ID of the repository. Set it together with repo_owner_id."
  type        = number
  default     = null

  validation {
    condition     = var.repo_id == null ? true : var.repo_id > 0 && floor(var.repo_id) == var.repo_id
    error_message = "repo_id must be a positive integer."
  }
}

variable "git_tags" {
  description = "Git tags whose workflows can assume the role. Values are IAM StringLike patterns."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for tag in var.git_tags : !strcontains(tag, ":")])
    error_message = "git_tags values cannot contain ':', which separates sub claim fields."
  }
}

variable "branches" {
  description = "Branches whose workflows can assume the role. Values are IAM StringLike patterns. When null, the role trusts main only if git_tags, environments, allow_pull_requests and allow_all are all unset."
  type        = list(string)
  default     = null

  validation {
    condition     = var.branches == null ? true : alltrue([for branch in var.branches : !strcontains(branch, ":")])
    error_message = "branches values cannot contain ':', which separates sub claim fields."
  }
}

variable "environments" {
  description = "GitHub environments whose jobs can assume the role (sub repo:<owner>/<repo>:environment:<name>). Values are IAM StringLike patterns."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for environment in var.environments : !strcontains(environment, ":")])
    error_message = "environments values cannot contain ':', which separates sub claim fields."
  }
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
  description = "Maximum session duration for the role, in seconds (3600 to 43200)."
  type        = number
  default     = 4200

  validation {
    condition     = var.max_session_duration >= 3600 && var.max_session_duration <= 43200
    error_message = "Maximum session duration must be between 3600 and 43200 seconds."
  }
}

variable "role_policies" {
  default     = {}
  description = "Inline policies for the role, as a map of policy name to policy JSON."
  type        = map(string)

  validation {
    condition     = sum(concat([0], [for policy in values(var.role_policies) : length(replace(policy, "/\\s/", ""))])) <= 10240
    error_message = "The inline policies exceed IAM's limit of 10,240 characters per role, not counting whitespace."
  }
}

variable "attach_policies" {
  default     = []
  description = "A list of IAM policy ARNs to attach to the role."
  type        = list(string)

  validation {
    condition     = length(var.attach_policies) <= 25
    error_message = "IAM allows at most 25 managed policies per role (the default quota is 20)."
  }
}

variable "permissions_boundary" {
  default     = null
  description = "ARN of the permissions boundary policy to attach to the role."
  type        = string
}
