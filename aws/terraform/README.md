# Xplorr on AWS: Terraform module

Creates the read-only IAM role Xplorr assumes to read your AWS costs,
commitments, credits, invoices and resource inventory. Every permission is a
read. Xplorr never creates, changes or deletes anything in your account.

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
  source = "git::https://github.com/Xplorrio/cloud-onboarding.git//aws/terraform?ref=v0.0.1"

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

## Outputs

| Name | Description |
|---|---|
| `xplorr_connect_form` | `aws_account_id`, `role_name`, `iam_external_id`, `region`: the Xplorr form fields |
| `aws_account_id`, `role_name`, `iam_external_id`, `region` | The same values one by one |
| `role_arn` | The role ARN; add it to `user_assumable_role_arns` where the user is created |
| `user_name`, `user_arn` | `customer_principal`: the user whose key you save in Xplorr, and the ARN other accounts must trust |
| `trust_mode` | The trust mode used |
| `next_steps` | What to do after apply (`terraform output -raw next_steps`) |

## Tests

`tests/module.tftest.hcl` plans the module against a provider with fake
credentials and overridden data sources, so it needs no AWS account:

```bash
terraform init -backend=false
terraform test
```
