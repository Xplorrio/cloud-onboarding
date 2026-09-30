# Xplorr on AWS: Terragrunt

Runs the [Terraform module](../terraform) with Terragrunt. It creates the same
read-only role and, in the default trust mode, the same IAM user with no
access key.

```
aws/terragrunt/
  root.hcl                        provider, optional S3 state, module source
  single-account/terragrunt.hcl   customer_principal (works today)
  keyless/terragrunt.hcl          xplorr_principal (requires Xplorr keyless onboarding, coming soon)
```

## Prerequisites

- Terragrunt 1.x (tested with 1.1.6) and Terraform 1.10 or later.
- AWS credentials for the target account that can manage IAM roles, users and
  their policies (for example `IAMFullAccess`).
- Cost Explorer enabled in the account.
- A clone of this repository: by default `root.hcl` uses the module next to it
  (`aws/terraform`).

## Steps

```bash
git clone https://github.com/Xplorrio/cloud-onboarding.git
cd cloud-onboarding/aws/terragrunt/single-account
# edit inputs in terragrunt.hcl; generate an external ID with: openssl rand -hex 16
terragrunt apply
terragrunt output -json xplorr_connect_form | jq .
terragrunt output -raw next_steps
```

To use a pinned release instead of the local module:

```bash
export XPLORR_MODULE_SOURCE="git::https://github.com/Xplorrio/cloud-onboarding.git//aws/terraform?ref=v0.0.1"
```

The state holds no secret, so a local backend is fine for a one off role. To
keep state in S3, uncomment `remote_state` in `root.hcl` and set your own
bucket.

For more accounts, copy `single-account` to a new folder per account and set
`create_user = false` and `trusted_principal_arns` to the first account's user
ARN; then add each new role ARN to `user_assumable_role_arns` in the first
account. Xplorr keeps one set of base keys per organization, so every account
must trust the same user. The
[Terraform README](../terraform/README.md#one-set-of-base-keys-per-xplorr-organization)
explains why.

## Connect it in Xplorr

The steps and field mapping are the same as for the Terraform module; see
[Connect it in Xplorr](../terraform/README.md#connect-it-in-xplorr). In short:
create an access key for `xplorr-assumer` in the IAM console (only if your
Xplorr organization has no base keys yet), then enter the AWS account ID, the
role name `xplorr-readonly`, the external ID and the region under **Connect
account > AWS > IAM role**.

For the `keyless` example, `xplorr_account_id` defaults to Xplorr's AWS account
`732121667940`, the trust is limited to Xplorr roles named `xplorr-*`, and
`iam_external_id` is the value Xplorr will generate for your organization once
keyless onboarding is live.

## Rotating the key and removing everything

- Rotate the access key as described in
  [the Terraform README](../terraform/README.md#rotating-the-access-key).
- Remove everything with `terragrunt destroy` in each folder, after deleting
  the accounts in Xplorr.

## Troubleshooting

See [the Terraform README](../terraform/README.md#troubleshooting). One
Terragrunt specific error: `find_in_parent_folders` fails when a folder is
copied outside `aws/terragrunt`; keep account folders next to `root.hcl`.
