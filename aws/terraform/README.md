# Xplorr on AWS: Terraform module

Creates the read-only IAM role Xplorr assumes to read your AWS costs,
commitments, credits, invoices and resource inventory. Every permission of
that role is a read.

Optionally, and only if you turn it on, it also creates a separate write role,
`xplorr-write`, so Xplorr can carry out changes a person in your Xplorr
organization has approved. See [Write access (opt in)](#write-access-opt-in).

Built on the CloudDrove modules
[`clouddrove/iam-role/aws`](https://registry.terraform.io/modules/clouddrove/iam-role/aws/1.4.0) 1.4.0 and
[`clouddrove/iam-user/aws`](https://registry.terraform.io/modules/clouddrove/iam-user/aws/1.3.2) 1.3.2.

## What it creates

| Trust mode | Creates | You give Xplorr |
|---|---|---|
| `customer_principal` (default, works today) | A role with the least-privilege read policy; in one account, an IAM user with no password and no access key whose only permission is `sts:AssumeRole` on the Xplorr roles | The user's access key once per Xplorr organization (created by you in the console), then per account: account ID, role name, external ID, region |
| `xplorr_principal` (**requires Xplorr keyless onboarding, coming soon**) | A role that trusts Xplorr's AWS account `732121667940`, only for its roles named `xplorr-*` (`aws:PrincipalArn`), with a required external ID. No user, no key | Per account: account ID, role name, external ID, region |

Terraform never creates an access key, so no AWS secret lands in the Terraform
state. In `xplorr_principal` mode Xplorr will generate the external ID for your
organization and show it on the Connect account form; the product does not do
this yet, which is why the mode is marked coming soon.

### One set of base keys per Xplorr organization

Xplorr stores one AWS access key per Xplorr organization (its "base keys") and
uses it to assume the role in every AWS account you connect with the IAM role
method. So in `customer_principal` mode:

- create the IAM user in **one** account only (your first account, or the
  management account of an AWS Organization), and
- in every other account, create only the role (`create_user = false`) and have
  it trust that user (`trusted_principal_arns`), and
- let the user assume those roles, by listing them in
  `user_assumable_role_arns`, or with `user_assumable_org_id` for every account
  of one AWS Organization.

## Prerequisites

- An account in the AWS commercial partition (`arn:aws:`). Xplorr does not
  support GovCloud or the China regions.
- Terraform 1.10 or later, and the `hashicorp/aws` provider 6.x.
- Credentials for each target account that can manage IAM: create and delete
  roles, users, inline policies and policy attachments, and tag them (for
  example the `IAMFullAccess` managed policy, or administrator access).
- Cost Explorer enabled in the account (open **Billing > Cost Explorer** once;
  the first load takes up to 24 hours).
- Optional: for per-resource costs, turn on resource-level data in
  **Billing and Cost Management > Cost Management preferences**. Without it
  `ce:GetCostAndUsageWithResources` returns no data and per-resource costs stay
  empty, while everything else works.
- In Xplorr, the member or admin role. Saving the organization's base keys
  needs admin.

## Usage

From a clone of this repository:

```bash
git clone https://github.com/Xplorrio/cloud-onboarding.git
cd cloud-onboarding/aws/terraform/examples/basic
cp terraform.tfvars.example terraform.tfvars   # edit the values
terraform init
terraform apply
```

Or call the module from your own code, by local path:

```hcl
module "xplorr" {
  source = "./cloud-onboarding/aws/terraform" # path to your clone

  iam_external_id = var.iam_external_id # optional; generate a value with: openssl rand -hex 16
}
```

or by a git source pinned to a release tag:

```hcl
module "xplorr" {
  source = "git::https://github.com/Xplorrio/cloud-onboarding.git//aws/terraform?ref=v0.2.0"

  iam_external_id = var.iam_external_id
}
```

Examples:

| Example | Use it for |
|---|---|
| [`examples/basic`](examples/basic) | Your first or only account. Creates the user and the role |
| [`examples/additional-account`](examples/additional-account) | Each further standalone account. Creates only the role, trusting the user from `basic` |
| [`examples/organization`](examples/organization) | An AWS Organization managed from one Terraform configuration (management account plus members through provider aliases). For many accounts, or accounts added later, use [`../cloudformation/stackset.yaml`](../cloudformation/stackset.yaml) |
| [`examples/keyless`](examples/keyless) | `xplorr_principal` (coming soon) |

`basic`, `additional-account` and `keyless` also take `enable_write_role`,
`write_actions` and `write_iam_external_id`, all off by default.

The external ID is optional in `customer_principal` mode. If you set one,
generate a random value rather than choosing a word:

```bash
openssl rand -hex 16
```

### A second standalone account

1. Apply `examples/basic` in the first account and note `user_arn`.
2. In the second account, apply `examples/additional-account` with
   `trusted_user_arn` set to that ARN. Note its `role_arn`.
3. Back in the first account, add that `role_arn` to `user_assumable_role_arns` in
   `examples/basic` and apply again, so the user may assume it.
4. Connect the second account in Xplorr with its own account ID; no new keys
   are needed.

## Connect it in Xplorr

1. **Create the access key** (`customer_principal`, only in the account that
   holds the user, and only if your Xplorr organization has no base keys yet).
   In the AWS console open **IAM > Users > xplorr-assumer > Security
   credentials > Create access key** and choose **Third-party service**. Copy
   the secret; it is shown once. Do not create it with Terraform: it would be
   stored in the state.
2. In Xplorr open **Infrastructure > Cloud Accounts > Connect account**, choose
   **AWS**, then **IAM role**.
3. If asked, enter the access key ID and secret access key and click **Save
   base keys**.
4. Fill in the fields. Print them with
   `terraform output -json xplorr_connect_form | jq .`:

   | Xplorr field | Output key |
   |---|---|
   | AWS account ID | `aws_account_id` |
   | Role name | `role_name` (`xplorr-readonly`) |
   | External ID | `iam_external_id` (leave blank when null) |
   | Region | `region` |

5. Click **Test connection**, then **Connect**. Repeat steps 2, 4 and 5 for
   every other account.

## Rotating the access key

1. In the IAM console, create a second access key for `xplorr-assumer` (a user
   may have two).
2. In Xplorr open **Connect account > AWS > IAM role**; the banner shows when
   the base keys last changed. Click **Replace keys** and enter the new key.
3. Wait for the next sync to succeed, then deactivate and delete the old key in
   the IAM console.

Removing the base keys in Xplorr stops every IAM role account in your Xplorr
organization from syncing until new keys are saved.

## Removing everything

1. Delete the accounts in Xplorr (**Infrastructure > Cloud Accounts**, the
   delete button on each row). This also deletes their stored cost history.
2. Run `terraform destroy` in every account where you applied, the additional
   accounts first. The user is created with `force_destroy`, so access keys you
   created in the console are deleted with it.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| "No base AWS credentials configured for this organization" | Save the user's access key under **Connect account > AWS > IAM role** first |
| `not authorized to perform: sts:AssumeRole` on Test connection | The role does not trust the user, the external ID in Xplorr differs from `iam_external_id`, or the user may not assume this role (add its ARN to `user_assumable_role_arns` where the user is created) |
| The role name is rejected by `terraform plan` | Role and user names must be lowercase; the CloudDrove labels module lowercases names, so an uppercase name would not match what you type in Xplorr |
| `EntityAlreadyExists` on apply | A role or user with that name exists already (perhaps created by hand or by CloudFormation). Import it, delete it, or pick another name |
| Costs empty after connecting | Cost Explorer was just enabled and has not populated yet (up to 24 hours) |
| Per-resource costs empty | Resource-level data is off in Cost Management preferences |
| FOCUS or carbon export reads fail with `AccessDenied` on `kms:Decrypt` | The bucket uses SSE-KMS; add its key to `export_kms_key_arns` (and allow the role in the key policy if the key does not delegate to IAM) |
| An approved action fails with `not authorized to perform: sts:AssumeRole` on `xplorr-write` | The write external ID in Xplorr differs from `write_iam_external_id`, or (`customer_principal`) the user may not assume the write role: add its ARN to `user_assumable_role_arns` where the user is created |
| An approved action fails with `UnauthorizedOperation` and an explicit deny | The resource is tagged `xplorr:protect` = `true`, or the region is outside `write_allowed_regions`. Nothing was changed |
| Credits or invoices missing for a member account | They belong to the payer. Connect the management account for organization-wide costs, credits and invoices |

## Permissions

The role gets one inline least-privilege policy with exactly the calls Xplorr
makes (source: `services/cloud-sync-service/src` in the Xplorr app).
`scripts/check-policy-drift.py` checks that CloudFormation grants the same.

| Group | Actions | Used for |
|---|---|---|
| CostAndCommitments | `ce:GetCostAndUsage`, `ce:GetCostAndUsageWithResources`, `ce:GetReservationCoverage`, `ce:GetReservationUtilization`, `ce:GetReservationPurchaseRecommendation`, `ce:GetSavingsPlansCoverage`, `ce:GetSavingsPlansUtilizationDetails`, `ce:GetSavingsPlansPurchaseRecommendation` | Costs, and coverage and utilization for reservations and Savings Plans. `GetCostAndUsageWithResources` needs resource-level data enabled |
| Commitments | `savingsplans:DescribeSavingsPlans`, `ec2:DescribeReservedInstances`, `rds:DescribeReservedDBInstances`, `elasticache:DescribeReservedCacheNodes` | The commitments you own |
| Credits | `billing:GetCredits`, `billing:GetCreditAllocationHistory` | Credit balances and expiry, imported daily |
| Inventory | `ec2:DescribeRegions`, `ec2:DescribeInstances`, `ec2:DescribeVolumes`, `ec2:DescribeVpcs`, `ec2:DescribeSubnets`, `ec2:DescribeSecurityGroups`, `ec2:DescribeNatGateways`, `ec2:DescribeInternetGateways`, `elasticloadbalancing:DescribeLoadBalancers`, `tag:GetResources` | Resource inventory and network costs |
| IdleDetection | `cloudwatch:GetMetricStatistics` | Idle EC2 and unattached EBS findings |
| Pricing | `pricing:GetProducts` | On-demand rates for sizing recommendations |
| Invoices | `invoicing:ListInvoiceSummaries` | Invoice reconciliation |
| AuditLog (`enable_audit_log`) | `cloudtrail:LookupEvents` | Called on each sync to record whether audit log access works; will be used for anomaly root cause analysis |
| Export buckets (`export_bucket_arns`) | `s3:ListBucket`, `s3:GetObject` | Optional FOCUS or carbon footprint exports in S3 |
| Export keys (`export_kms_key_arns`) | `kms:Decrypt` | Only when those buckets use SSE-KMS; not needed for the default SSE-S3 encryption |

`attach_readonly_access = true` also attaches the AWS managed `ReadOnlyAccess`
policy, on top of the least-privilege policy. It is off by default and Xplorr
does not need it. Be aware of how much wider it is: it reads data, not just
metadata, in most services, including S3 objects, DynamoDB items and SQS
messages.

Connect the management (payer) account for organization-wide costs and
credits. A member account only sees its own costs.

## Write access (opt in)

Off by default. With `enable_write_role = true` the module creates a second
role, `xplorr-write`, next to the read-only one:

- **A separate role.** The read-only role never gains a write permission.
  The write role has its own external ID (`write_iam_external_id`), which must
  differ from the read-only role's, so the credentials Xplorr uses for syncing
  cannot make changes.
- **Only the action types you list.** Each entry in `write_actions` adds the
  permissions of one action type and nothing else.
- **Approval first.** Xplorr assumes the write role only to carry out an
  action a person in your Xplorr organization has approved, in the console or
  in Slack. Syncing never uses it.
- **Protected resources are refused.** An explicit Deny refuses every change
  to a resource tagged `xplorr:protect` = `true` (any case), whatever Xplorr
  asks for. Change the key with `write_protect_tag_key`, or set it to `""` to
  turn the guard off.

Approved actions are rolling out in Xplorr. Until the console offers write
access for your account, the role exists but is never assumed.

```hcl
module "xplorr" {
  source = "git::https://github.com/Xplorrio/cloud-onboarding.git//aws/terraform?ref=v0.2.0"

  iam_external_id = var.iam_external_id

  enable_write_role     = true
  write_actions         = ["stop_idle_instance", "release_unassociated_eip"]
  write_iam_external_id = var.write_iam_external_id # not the same as iam_external_id
}
```

`terraform output -json xplorr_write_access_form` prints what Xplorr asks for:
the account ID, `write_role_name`, `write_role_arn`, `write_iam_external_id`
and the action types.

### What each action type allows

| Action type | Allows | On | Guards and limits |
|---|---|---|---|
| `stop_idle_instance` | `ec2:StopInstances`, and `ec2:StartInstances` to undo it; `ec2:DescribeInstances` to check the state first | Instances in this account | Protect tag Deny; `write_allowed_regions`. No terminate |
| `delete_unattached_ebs_volume` | `ec2:CreateSnapshot`, then `ec2:DeleteVolume`; `ec2:CreateTags` only on the new snapshot while it is created (`ec2:CreateAction` = `CreateSnapshot`); `ec2:DescribeVolumes`, `ec2:DescribeSnapshots` | Volumes in this account, and new snapshots | Protect tag Deny; `write_allowed_regions`. EC2 refuses to delete an attached volume (`VolumeInUse`) |
| `release_unassociated_eip` | `ec2:ReleaseAddress`; `ec2:DescribeAddresses` | Elastic IPs in this account | Protect tag Deny; `write_allowed_regions`. No `ec2:DisassociateAddress`, so an address in use cannot be detached |
| `rightsize_instance` | Nothing | | Xplorr proposes it as a Terraform pull request in your repository, so no cloud permission is needed |

The describe calls take no resource ARN, so they are granted on `*`; they
only read. Everything else is limited to resources in the account the role
lives in.

### Limits

- **No condition for "unattached" or "unassociated".** IAM has no condition
  key for a volume's attachment state or an Elastic IP's association. EC2
  itself refuses to delete an attached volume, and without
  `ec2:DisassociateAddress` the role cannot free an address that is in use.
  Xplorr also checks the state with the describe calls right before acting.
- **Deleting a volume and releasing an address cannot be undone by Xplorr.**
  A volume is snapshotted first; restoring it is up to you (the role has no
  `ec2:CreateVolume`). The snapshot is kept, and billed, until you delete it.
  A released Elastic IP may not be recoverable.
- **Undoing a stop can fail for encrypted instances.** Starting an instance
  whose volumes use a customer managed KMS key also needs permissions on that
  key, which the write role does not have. Start it yourself, or allow the
  role in the key policy.
- **Instances IAM cannot tell apart.** A stopped instance in an Auto Scaling
  group may be replaced, and instance store data is lost on stop. Tag
  instances that must never be stopped with `xplorr:protect` = `true`.
- **Service control policies and permission boundaries** still apply;
  `permissions_boundary_arn` is set on the write role too.

### Trust

The write role's trust policy has the same shape as the read-only role's, in
the same `trust_mode`:

- `customer_principal`: it trusts the same principals as the read-only role
  (the user created here, or `trusted_principal_arns`), and the user's policy
  here gains `sts:AssumeRole` on the write role. For a write role in another
  account, add its `write_role_arn` to `user_assumable_role_arns` where the
  user is created; with `user_assumable_org_id`, the user may assume
  `write_role_name` in any account of the organization.
- `xplorr_principal`: it trusts **only Xplorr's dedicated actions role**,
  `arn:aws:iam::732121667940:role/xplorr-actions`, matched exactly
  (`aws:PrincipalArn` with `StringEquals`, set by
  `write_xplorr_principal_arn`), with `write_iam_external_id` required. The
  read-only role keeps trusting Xplorr roles named `xplorr-*`, so Xplorr's
  sync role can read but can never assume the write role. Keep the `xplorr-`
  prefix in `write_role_name`.

To create only the write role in an account whose read-only role is managed
elsewhere, use the [`modules/write-role`](modules/write-role) module on its
own, or [`../cloudformation/write-role.yaml`](../cloudformation/write-role.yaml).

### Removing write access

Set `enable_write_role = false` and apply. That deletes the write role and its
policy, and removes it from the user's assume policy; the read-only role and
the connection keep working. Also turn write access off for the account in
Xplorr, so it stops offering actions there.

## Inputs

| Name | Default | Description |
|---|---|---|
| `trust_mode` | `customer_principal` | `customer_principal` or `xplorr_principal` |
| `role_name` | `xplorr-readonly` | Role name, lowercase |
| `create_user` | `true` | `customer_principal`: create the assuming user. `false` in every account but one |
| `user_name` | `xplorr-assumer` | `customer_principal`: name of the user |
| `trusted_principal_arns` | `[]` | `customer_principal`: principals the role trusts, such as the user in your first account |
| `user_assumable_role_arns` | `[]` | Where the user is created: roles in other accounts it may assume |
| `user_assumable_org_id` | `""` | Where the user is created: an `o-...` id; the user may assume `role_name` in any account of that organization (`aws:ResourceOrgID`) |
| `xplorr_account_id` | `732121667940` | `xplorr_principal`: Xplorr's AWS account |
| `xplorr_principal_role_pattern` | `xplorr-*` | `xplorr_principal`: Xplorr roles allowed to assume the role |
| `iam_external_id` | `""` | The External ID field. Required for `xplorr_principal`, optional for `customer_principal` |
| `region` | `us-east-1` | The Region field in Xplorr |
| `attach_readonly_access` | `false` | Also attach `ReadOnlyAccess` (much wider; see above) |
| `enable_audit_log` | `true` | Grant `cloudtrail:LookupEvents` |
| `export_bucket_arns` | `[]` | S3 buckets with FOCUS or carbon exports |
| `export_kms_key_arns` | `[]` | KMS keys of SSE-KMS encrypted export buckets (grants `kms:Decrypt`) |
| `max_session_duration` | `3600` | At least 3600: Xplorr requests one hour sessions |
| `permissions_boundary_arn` | `""` | Optional permissions boundary for the role and user |
| `tags` | `{}` | Tags for the role (the CloudDrove user module does not apply custom tags to the user) |
| `enable_write_role` | `false` | Create the separate write role (see [Write access](#write-access-opt-in)) |
| `write_actions` | `[]` | With `enable_write_role`: `stop_idle_instance`, `delete_unattached_ebs_volume`, `release_unassociated_eip` |
| `write_role_name` | `xplorr-write` | Name of the write role; must start with `xplorr-` |
| `write_iam_external_id` | `""` | The write role's own external ID. Required for `xplorr_principal`; must differ from `iam_external_id` |
| `write_xplorr_principal_arn` | `arn:aws:iam::732121667940:role/xplorr-actions` | `xplorr_principal`: the one Xplorr role the write role trusts, matched exactly |
| `write_protect_tag_key` | `xplorr:protect` | Resources tagged with it and the value `true` are refused. `""` turns the guard off |
| `write_allowed_regions` | `[]` | Regions the write role may act in. Empty means every region |

## Outputs

| Name | Description |
|---|---|
| `xplorr_connect_form` | `aws_account_id`, `role_name`, `iam_external_id`, `region`: the Xplorr form fields |
| `aws_account_id`, `role_name`, `iam_external_id`, `region` | The same values one by one |
| `role_arn` | The role ARN; add it to `user_assumable_role_arns` where the user is created |
| `user_name`, `user_arn` | `customer_principal`: the user whose key you save in Xplorr, and the ARN other accounts must trust |
| `trust_mode` | The trust mode used |
| `next_steps` | What to do after apply (`terraform output -raw next_steps`) |
| `xplorr_write_access_form` | With `enable_write_role`: `aws_account_id`, `write_role_name`, `write_role_arn`, `write_iam_external_id`, `actions` |
| `write_role_arn`, `write_role_name`, `write_iam_external_id` | The same values one by one |
| `write_trusted_principal` | Who may assume the write role: the read-only role's principals, or the Xplorr actions role ARN |
| `write_granted_permissions` | Every IAM action the write role allows |

## Tests

`tests/module.tftest.hcl` plans the module against a provider with fake
credentials and overridden data sources, so it needs no AWS account:

```bash
terraform init -backend=false
terraform test
```
