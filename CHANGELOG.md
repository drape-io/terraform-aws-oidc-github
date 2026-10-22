# Changelog

## 1.0.0

### Breaking changes

- **`branches` defaults to `null`.** The role trusts `main` by default only
  when `git_tags`, `environments`, `allow_pull_requests` and `allow_all` are
  all unset. Before, the `["main"]` default applied together with every other
  selector. A caller that sets `git_tags`, `allow_pull_requests` or
  `allow_all` without setting `branches` no longer trusts `main`. To keep the
  old trust policy, set `branches = ["main"]`. Callers that set `branches`, or
  that set no other selector, get the same trust policy as before.
- **`repo` validation is stricter.** `repo` must be `owner/repo` or
  `owner@id/repo@id`, using only the characters GitHub allows in names. Values
  with wildcards (`*`, `?`), `:` or an extra `/` now fail at plan. GitHub
  repositories cannot have such names, so a role that a workflow can assume
  keeps working.
- **Inline policies move to separate resources.** `role_policies` now creates
  one `aws_iam_role_policy` for each entry and an
  `aws_iam_role_policies_exclusive` for the role. The deprecated
  `inline_policy` block is gone. See "Upgrading" below.
- **New validation.** `branches`, `git_tags` and `environments` values cannot
  contain `:`. `attach_policies` accepts at most 25 ARNs. The inline policies
  of one role cannot exceed 10,240 characters, not counting whitespace.
- **Terraform 1.6.6 or later is required.** Terraform 1.6.0 to 1.6.5 cannot
  verify the signatures of current provider releases.
- **terraform-null-context is pinned to v1.0.0.** Role names and trust
  policies do not change. Tags change only for a caller that sets a generated
  tag key, such as `environment`, through `context.tags`: the generated value
  now wins. See the terraform-null-context 1.0.0 changelog.

### Added

- `environments`: trust jobs that run in the named GitHub environments
  (`repo:<owner>/<repo>:environment:<name>`).
- `repo_owner_id` and `repo_id`: also trust GitHub's immutable subject format
  (`repo:<owner>@<owner-id>/<repo>@<repo-id>:...`) for every selector. The
  module does not add these subjects when `repo` is already in that form.
- A role name longer than 64 characters becomes a 55-character prefix plus an
  8-character hash of the full name. Before, such names failed at plan.
  Shorter names do not change.

### Fixes

- Removing the last entry from `role_policies` now removes that policy from
  the role. Before, the policy stayed attached.
- `repo` values in the immutable form (`owner@id/repo@id`) pass validation.
- Underscores are allowed in the owner (Enterprise Managed Users accounts).

### Upgrading

1. Set `branches = ["main"]` on every role that sets `git_tags`,
   `allow_pull_requests` or `allow_all` and relies on the old default.
2. Run `terraform plan`. For each role, expect these changes and nothing
   else:
   - one `aws_iam_role_policy` to create for each `role_policies` entry
   - one `aws_iam_role_policies_exclusive` to create
   - no change to `aws_iam_role`

   No `moved` blocks or imports are needed. Creating an `aws_iam_role_policy`
   calls `PutRolePolicy`, which replaces the existing inline policy of the same
   name in place, so the role keeps its permissions during the apply.
3. Before you apply, check for inline policies that were added outside
   Terraform. `aws_iam_role_policies_exclusive` removes every inline policy
   that is not in `role_policies`.

If you prefer the plan to show imports instead of creates, add an `import`
block for each policy before you apply:

```hcl
import {
  to = module.github_oidc_role.aws_iam_role_policy.github["deploy"]
  id = "<role name>:deploy"
}
```
