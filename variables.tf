# This was copied from `drape-io/terraform-null-context` since it'll be passed
# along to it.
variable "context" {
  type = object({
    enabled    = optional(bool)
    group      = optional(string)
    tenant     = optional(string)
    env        = optional(string)
    scope      = optional(string)
    attributes = optional(list(string))
    tags       = optional(map(string))
  })
  description = <<-EOT
    Used to pass an object of any of the variables used to this module.  It is
    used to seed the module with labels from another context.
  EOT
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

variable "tags" {
  description = "Tags on the repo that should have access to AWS"
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
  # Default to 70minutes.
  default = 4200

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
  description = "A list of arns to attach to the iam role."
  type        = list(string)
}
