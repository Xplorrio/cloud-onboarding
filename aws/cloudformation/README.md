# Xplorr on AWS: CloudFormation

| Template | Deploy in | Creates |
|---|---|---|
| [`role.yaml`](role.yaml) | Any single account; the first account of several standalone accounts; the management account of an organization | The read-only role and, in `customer_principal` mode with `CreateUser=true`, an IAM user (no password, no access key) whose only permission is assuming the Xplorr roles |
| [`stackset.yaml`](stackset.yaml) | The management account of an AWS Organization, after `role.yaml` | A service managed StackSet that creates the role from `role.yaml` in every member account of the chosen organizational units, including accounts added later |

The permissions are the least-privilege list documented in
[the Terraform module](../terraform/README.md#permissions);
`scripts/check-policy-drift.py` keeps the two identical. `AttachReadOnlyAccess`
adds the AWS managed `ReadOnlyAccess` policy on top. It is off by default, not
needed, and much wider: it can read data such as S3 objects and DynamoDB items.

## Trust modes

| `TrustMode` | Status | Trust |
|---|---|---|
| `customer_principal` | Default, works today | The IAM user in this account, or `TrustedPrincipalArn` |
| `xplorr_principal` | **Requires Xplorr keyless onboarding (coming soon)** | Xplorr's AWS account `XplorrAccountId` (default `732121667940`), only its roles named `xplorr-*` (`aws:PrincipalArn`), with a required `IamExternalId`. Xplorr will generate the external ID for your organization; the product does not do this yet |

Xplorr keeps **one set of base keys per Xplorr organization** and uses it for
every account connected with the IAM role method. So create the user in one
account only, and have every other account's role trust that user.

## Prerequisites

- An account in the AWS commercial partition (`arn:aws:`); GovCloud and the
  China regions are not supported by Xplorr.
- AWS CLI v2 (or the console), signed in to the target account with
  permission to create IAM roles, users and policies and to create stacks with
  `CAPABILITY_NAMED_IAM` (for example `IAMFullAccess` plus
  `AWSCloudFormationFullAccess`).
- For `stackset.yaml`: the organization's management account, with trusted
  access for CloudFormation StackSets turned on.
- Cost Explorer enabled in the accounts you connect.

## One account

```bash
aws cloudformation deploy \
  --stack-name xplorr-readonly \
  --template-file role.yaml \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides TrustMode=customer_principal \
    IamExternalId="$(openssl rand -hex 16)"

aws cloudformation describe-stacks --stack-name xplorr-readonly \
  --query 'Stacks[0].Outputs' --output table
```

The external ID is optional in `customer_principal` mode; leave out
`IamExternalId` to go without one.

A one click **Launch Stack** link is coming soon, once Xplorr hosts the
template in a public S3 bucket. Until then, deploy with the CLI as above, or
upload `role.yaml` under **CloudFormation > Create stack > Upload a template
file** in the console.

## Several standalone accounts

1. In the first account, deploy `role.yaml` as above. Note the `UserArn`
   output.
2. In each further account, deploy `role.yaml` without a user, trusting that
   user:

   ```bash
   aws cloudformation deploy \
     --stack-name xplorr-readonly \
     --template-file role.yaml \
     --capabilities CAPABILITY_NAMED_IAM \
     --parameter-overrides CreateUser=false \
       TrustedPrincipalArn=arn:aws:iam::111111111111:user/xplorr-assumer \
       IamExternalId="$(openssl rand -hex 16)"
   ```

   Note its `RoleArn` output.
3. Update the first account's stack so the user may assume those roles:

   ```bash
   aws cloudformation deploy \
     --stack-name xplorr-readonly \
     --template-file role.yaml \
     --capabilities CAPABILITY_NAMED_IAM \
     --parameter-overrides \
       AdditionalAssumableRoleArns=arn:aws:iam::222222222222:role/xplorr-readonly,arn:aws:iam::333333333333:role/xplorr-readonly
   ```

   (`aws cloudformation deploy` keeps the other parameters' previous values.)

## A whole organization: StackSet

1. In the management account, turn on trusted access for CloudFormation
   StackSets: **AWS Organizations > Services > CloudFormation StackSets >
   Enable trusted access**, or
   `aws organizations enable-aws-service-access --service-principal member.org.stacksets.cloudformation.amazonaws.com`.
2. Deploy `role.yaml` in the management account with your organization id, so
   the user may assume `xplorr-readonly` in any account of the organization
   (`aws:ResourceOrgID`):

   ```bash
   aws cloudformation deploy \
     --stack-name xplorr-readonly \
     --template-file role.yaml \
     --capabilities CAPABILITY_NAMED_IAM \
     --parameter-overrides AssumableOrganizationId=o-abcd123456
   ```

   A service managed StackSet never deploys to the management account, so this
   step also gives Xplorr the payer's organization-wide costs.
3. Deploy `stackset.yaml` in the management account, with the same
   `TrustMode`, `RoleName`, `IamExternalId` and `UserName`:

   ```bash
   aws cloudformation deploy \
     --stack-name xplorr-readonly-members \
     --template-file stackset.yaml \
     --parameter-overrides OrganizationalUnitIds=r-abcd
   ```

   `r-abcd` stands for your organization's root id (**AWS Organizations > AWS
   accounts**); use `ou-...` ids to cover only some units. The StackSet must be
   created from the management account; this template does not support a
   delegated administrator.
4. Every member account now has `xplorr-readonly`, and new accounts in those
   units get it automatically.

## Connect it in Xplorr

1. `customer_principal` only, and only if your Xplorr organization has no base
   keys yet: in the IAM console of the account holding the user open **Users >
   xplorr-assumer > Security credentials > Create access key**, choose
   **Third-party service** and copy the secret. No template creates a key, so
   it never appears in a stack.
2. In Xplorr open **Infrastructure > Cloud Accounts > Connect account**, choose
   **AWS**, then **IAM role**. Save the key as the base keys if asked.
3. Fill in the fields from the stack outputs, once per AWS account:

   | Xplorr field | Stack output |
   |---|---|
   | AWS account ID | `AwsAccountId` (for member accounts, the member's account ID) |
   | Role name | `RoleName` (`xplorr-readonly`) |
   | External ID | `IamExternalId` (not shown when none is set; leave the field blank) |
   | Region | `Region` |

4. Click **Test connection**, then **Connect**.

## Rotating the access key

Create a second access key for `xplorr-assumer`, click **Replace keys** under
**Connect account > AWS > IAM role** in Xplorr, wait for a successful sync,
then delete the old key in the IAM console.

## Removing everything

1. Delete the accounts in Xplorr (**Infrastructure > Cloud Accounts**). This
   also deletes their stored cost history.
2. Delete the access keys of `xplorr-assumer` in the IAM console. CloudFormation
   cannot delete a user that still has keys it did not create.
3. Delete the stacks, the StackSet stack first:

   ```bash
   aws cloudformation delete-stack --stack-name xplorr-readonly-members
   aws cloudformation delete-stack --stack-name xplorr-readonly
   ```

   Deleting the StackSet stack removes the role from every member account.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `Requires capabilities : [CAPABILITY_NAMED_IAM]` | Add `--capabilities CAPABILITY_NAMED_IAM` |
| Parameter `RoleName` failed to satisfy constraint | Names must be lowercase (`xplorr-readonly`) |
| `IamExternalId is required when TrustMode is xplorr_principal` | Keyless mode needs the external ID Xplorr gives you |
| `not authorized to perform: sts:AssumeRole` on Test connection | The role does not trust the user, the external ID in Xplorr differs, or the user may not assume this role (set `AdditionalAssumableRoleArns` or `AssumableOrganizationId` in the account holding the user) |
| StackSet fails with a trusted access error | Turn on trusted access for CloudFormation StackSets in AWS Organizations |
| Stack deletion fails on the user | Delete the user's access keys first |
| Export reads fail with `AccessDenied` on `kms:Decrypt` | The export bucket uses SSE-KMS; set `ExportKmsKeyArn` to its key |

## Validation

```bash
cfn-lint role.yaml stackset.yaml
python3 ../../scripts/sync-stackset.py --check
python3 ../../scripts/check-policy-drift.py
```

`stackset.yaml` carries a copy of `role.yaml` as its `TemplateBody`. After
changing `role.yaml`, run `python3 scripts/sync-stackset.py` from the
repository root to refresh it; CI fails if the two differ.
