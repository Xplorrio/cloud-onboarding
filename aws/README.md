# Xplorr on AWS

Pick one tool. Each creates the same least-privilege read-only role, and, only
if you opt in, a separate write role for approved actions.

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

## Write access (opt in)

Off by default, and never part of the read-only role. Each tool can also
create `xplorr-write`, a separate role with its own external ID that Xplorr
assumes only to carry out an action a person in your Xplorr organization has
approved. You choose the action types; only their permissions are granted.

| Action type | Permissions |
|---|---|
| `stop_idle_instance` | `ec2:StopInstances`, `ec2:StartInstances` (undo), `ec2:DescribeInstances` |
| `delete_unattached_ebs_volume` | `ec2:CreateSnapshot`, `ec2:DeleteVolume`, `ec2:CreateTags` (new snapshot only), `ec2:DescribeVolumes`, `ec2:DescribeSnapshots` |
| `release_unassociated_eip` | `ec2:ReleaseAddress`, `ec2:DescribeAddresses` |
| `rightsize_instance` | None: a Terraform pull request |

Resources tagged `xplorr:protect` = `true` are refused by an explicit Deny.
In keyless mode the write role trusts only Xplorr's dedicated actions role,
`arn:aws:iam::732121667940:role/xplorr-actions`, never the `xplorr-*` roles
the read-only role trusts.

| Tool | How to turn it on |
|---|---|
| Terraform | `enable_write_role = true` and `write_actions` ([details](terraform/README.md#write-access-opt-in)), or [`terraform/modules/write-role`](terraform/modules/write-role) on its own |
| Terragrunt | `enable_write_role` in `single-account` or `keyless`, or the [`write-role`](terragrunt/write-role) folder |
| CloudFormation | Deploy [`write-role.yaml`](cloudformation/write-role.yaml) as its own stack ([details](cloudformation/README.md#write-access-opt-in)) |

