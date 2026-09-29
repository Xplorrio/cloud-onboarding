# Xplorr on AWS: the opt-in write role

Creates `xplorr-write`, a role Xplorr assumes only to carry out an action a
person in your Xplorr organization has approved. It is separate from the
read-only role, has its own external ID, and grants only the action types you
list.

The parent module creates it for you with `enable_write_role = true` (see
[Write access](../../README.md#write-access-opt-in)). Use this module on its
own when the read-only role already exists and is managed somewhere else, for
example by CloudFormation or by hand.

Built on [`clouddrove/iam-role/aws`](https://registry.terraform.io/modules/clouddrove/iam-role/aws/1.4.0)
1.4.0, like the read-only role.

## Usage

`customer_principal`, trusting the user that assumes your read-only role:

```hcl
module "xplorr_write" {
  source = "git::https://github.com/Xplorrio/cloud-onboarding.git//aws/terraform/modules/write-role?ref=v0.2.0"

  actions                = ["stop_idle_instance"]
  trusted_principal_arns = ["arn:aws:iam::111111111111:user/xplorr-assumer"]
  iam_external_id        = var.write_iam_external_id # optional here; openssl rand -hex 16
}
```

That user also needs `sts:AssumeRole` on the new role: add `role_arn` to
`user_assumable_role_arns` (Terraform) or `AdditionalAssumableRoleArns`
(CloudFormation) where the user is created.

`xplorr_principal`, trusting Xplorr's account like a keyless read-only role:

```hcl
module "xplorr_write" {
  source = "git::https://github.com/Xplorrio/cloud-onboarding.git//aws/terraform/modules/write-role?ref=v0.2.0"

  actions         = ["stop_idle_instance", "delete_unattached_ebs_volume"]
  trust_mode      = "xplorr_principal"
  iam_external_id = var.write_iam_external_id # the write access external ID Xplorr shows you
}

output "xplorr_write_access_form" {
  value = module.xplorr_write.xplorr_write_access_form
}
```

## What each action type allows

| Action type | Allows | Guards and limits |
|---|---|---|
| `stop_idle_instance` | `ec2:StopInstances`, `ec2:StartInstances` (undo), `ec2:DescribeInstances` | Instances in this account only; protect tag Deny; `allowed_regions` |
| `delete_unattached_ebs_volume` | `ec2:CreateSnapshot`, `ec2:DeleteVolume`, `ec2:CreateTags` on the new snapshot while it is created, `ec2:DescribeVolumes`, `ec2:DescribeSnapshots` | Volumes in this account only; protect tag Deny; `allowed_regions`; EC2 refuses to delete an attached volume |
| `release_unassociated_eip` | `ec2:ReleaseAddress`, `ec2:DescribeAddresses` | Elastic IPs in this account only; protect tag Deny; `allowed_regions`; no `ec2:DisassociateAddress` |
| `rightsize_instance` | Nothing: a Terraform pull request | |

The limits are listed in the parent README under
[Limits](../../README.md#limits).

## Inputs

| Name | Default | Description |
|---|---|---|
| `actions` | required | Action types to grant: `stop_idle_instance`, `delete_unattached_ebs_volume`, `release_unassociated_eip` |
| `trust_mode` | `customer_principal` | The same mode as your read-only role |
| `role_name` | `xplorr-write` | Must start with `xplorr-` |
| `trusted_principal_arns` | `[]` | `customer_principal`, required there: the user that assumes the read-only role |
| `xplorr_account_id` | `732121667940` | `xplorr_principal`: Xplorr's AWS account |
| `xplorr_principal_role_pattern` | `xplorr-*` | `xplorr_principal`: Xplorr roles allowed to assume the role |
| `iam_external_id` | `""` | The write role's own external ID. Required for `xplorr_principal` |
| `protect_tag_key` | `xplorr:protect` | Resources tagged with it and the value `true` are refused. `""` turns the guard off |
| `allowed_regions` | `[]` | Regions the role may act in. Empty means every region |
| `max_session_duration` | `3600` | At least 3600 |
| `permissions_boundary_arn` | `""` | Optional permissions boundary |
| `tags` | `{}` | Tags for the role |

## Outputs

| Name | Description |
|---|---|
| `xplorr_write_access_form` | `aws_account_id`, `write_role_name`, `write_role_arn`, `write_iam_external_id`, `actions` |
| `role_arn`, `role_name`, `iam_external_id`, `actions` | The same values one by one |
| `granted_permissions` | Every IAM action the role allows |
| `protect_tag_key` | The protect tag key, or null |
| `trust_mode` | The trust mode used |

## Removing it

`terraform destroy` here (or remove the module block and apply). Remove the
role's ARN from the user's assumable roles too, and turn write access off for
the account in Xplorr.

## Tests

`tests/module.tftest.hcl` plans the module against fake credentials:

```bash
terraform init -backend=false
terraform test
```
