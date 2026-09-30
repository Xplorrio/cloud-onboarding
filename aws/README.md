# Xplorr on AWS

Pick one tool. Each creates the same least-privilege read-only role. Xplorr
needs read only access and never changes resources in your accounts.

| Folder | Tool | Best for |
|---|---|---|
| [`terraform/`](terraform) | Terraform module (CloudDrove modules), with `basic`, `additional-account`, `organization` and `keyless` examples | Teams that manage AWS with Terraform |
| [`terragrunt/`](terragrunt) | Terragrunt wrapper around the same module | Teams that use Terragrunt |
| [`cloudformation/`](cloudformation) | `role.yaml` (one or several accounts) and `stackset.yaml` (every member account of an organization) | Console and CLI users, and AWS Organizations |

Both trust modes are available everywhere:

- `customer_principal` (default, works today): an IAM user, with no password
  and no access key, may only assume the Xplorr roles. You create its access
  key in the IAM console and save it once in Xplorr as your organization's base
  keys. Xplorr keeps one set of base keys per organization, so create the user
  in one account and have every other account's role trust it.
- `xplorr_principal` (**requires Xplorr keyless onboarding, coming soon**): the
  role trusts Xplorr's AWS account `732121667940`, only its roles named
  `xplorr-*`, with an external ID Xplorr will generate for your organization.
  No user and no key.

What to enter in Xplorr (**Connect account > AWS > IAM role**): the AWS account
ID, the role name (`xplorr-readonly` unless you changed it), the external ID if
you set one, and the region. Each folder's README has the details, how to
rotate the key, how to remove everything, and troubleshooting.
