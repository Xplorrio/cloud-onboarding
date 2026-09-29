# Xplorr cloud onboarding

Ready-to-use infrastructure code that creates the read-only roles and
permissions [Xplorr](https://xplorr.io) needs to read your cloud costs,
commitments, credits and resource inventory. Every permission of those roles
is a read.

Separately, and only if you opt in, each template can also create a write
role so Xplorr can carry out changes a person in your organization has
approved, limited to the action types you choose. See
[Write access (opt in)](#write-access-opt-in).

The permissions match exactly what Xplorr calls, and each template ends by
printing the values the Xplorr **Connect account** form asks for
(**Infrastructure > Cloud Accounts > Connect account**).

## Pick your cloud and tool

| Cloud | Tool | What it creates | What to paste into Xplorr |
|---|---|---|---|
| AWS | [Terraform](aws/terraform) | Least-privilege IAM role; in `customer_principal` mode, in one account, an IAM user (no password, no key) that may only assume the Xplorr roles. Examples for a first account, additional accounts, an organization, and keyless | AWS account ID, Role name, External ID, Region; plus the user's access key once per Xplorr organization, created by you in the IAM console |
| AWS | [Terragrunt](aws/terragrunt) | The same, through the Terraform module | The same |
| AWS | [CloudFormation](aws/cloudformation) | `role.yaml`: the same role and user in one account, or the role alone in further accounts. `stackset.yaml`: the role in every member account of an organization | The same, from the stack outputs |
| Azure | [Terraform](azure/terraform) | Single tenant app registration and service principal; Reader (and Cost Management Reader) on each subscription or once on a management group; optional Carbon Optimization Reader, tenant scope Reservations Reader and Savings plan reader, and Storage Blob Data Reader for a FOCUS export. No client secret unless you opt in | Azure subscription ID, and Credentials (JSON) with `tenantId`, `clientId`, `subscriptionId` and the `clientSecret` you create in the portal |
| Azure | [Bicep](azure/bicep) | The same app registration, service principal and roles (Microsoft Graph Bicep extension), at subscription or management group scope. Never creates a secret | The same, from the deployment outputs |
| Google Cloud | [Terraform](gcp/terraform) | Service account with BigQuery Data Viewer (on the billing dataset), BigQuery Job User, Recommender, Cloud Asset, Compute, Storage Bucket and Logs Viewer; the APIs Xplorr calls; optional Billing Account Viewer, organization or folder grants, and the billing export dataset. No key unless you opt in | GCP project ID, and Credentials (JSON) with `projectId`, `billingDataset`, `billingTable`, `bigqueryLocation` and `keyfileJson`, the key you create with gcloud |
| Google Cloud | [gcloud.sh](gcp/gcloud.sh) | The same, with an idempotent gcloud script | The same, printed at the end of the run |

## Trust modes

Every template has a trust mode setting.

| Mode | Status | How Xplorr signs in |
|---|---|---|
| `customer_principal` | **Default. Works today.** | As an identity you create and own: an IAM user (AWS), an app registration and service principal (Azure), a service account (Google Cloud). You create the credential yourself (access key, client secret, key file) and give it to Xplorr, so by default it never lands in Terraform state |
| `xplorr_principal` | **Requires Xplorr keyless onboarding (coming soon), in all three clouds** | As Xplorr's own identity, trusted by yours: Xplorr's AWS account `732121667940` with an external ID (AWS); the service principal of Xplorr's multi-tenant app, by its application ID (Azure); an Xplorr service account allowed to impersonate yours (Google Cloud). Nothing of yours is stored |

Keyless onboarding is not live yet. Today the Connect account form still asks
for an access key on AWS, a client secret on Azure and a key file on Google
Cloud, so `xplorr_principal` roles cannot be connected until Xplorr announces
it. The Azure application ID and the Google Cloud service account are
required inputs with no default; Xplorr will show them on the form.

Use `customer_principal` until Xplorr announces keyless onboarding.

## Write access (opt in)

Off by default everywhere. When you turn it on:

- It is a **separate role for a separate identity**, never merged into the
  read-only one: an IAM role `xplorr-write` with its own external ID that
  only Xplorr's dedicated actions role may assume (AWS); a custom role
  `xplorr-write` held by its own app registration and service principal
  (Azure); a custom role `xplorrWrite` held by its own service account,
  `xplorr-write@<project>` (Google Cloud). The identities Xplorr syncs with
  can never make a change.
- It grants **only the action types you list**, one permission set per type.
- Xplorr uses it **only to carry out an action someone approved** in your
  Xplorr organization. Syncing never uses it.
- Where the cloud supports it, resources you mark as protected are refused by
  the cloud itself.

| Cloud | Action type | Permissions | Protected resources |
|---|---|---|---|
| AWS | `stop_idle_instance` | `ec2:StopInstances`, `ec2:StartInstances` (undo), `ec2:DescribeInstances` | Explicit Deny on tag `xplorr:protect` = `true` |
| AWS | `delete_unattached_ebs_volume` | `ec2:CreateSnapshot`, `ec2:DeleteVolume`, `ec2:CreateTags` (new snapshot only), `ec2:DescribeVolumes`, `ec2:DescribeSnapshots` | The same Deny; EC2 refuses to delete an attached volume |
| AWS | `release_unassociated_eip` | `ec2:ReleaseAddress`, `ec2:DescribeAddresses` | The same Deny; no `ec2:DisassociateAddress` |
| AWS | `rightsize_instance` | None: a Terraform pull request | |
| Azure | `deallocate_idle_vm` | `Microsoft.Compute/virtualMachines/deallocate/action`, `.../start/action` (undo) | No RBAC condition exists for VM actions; narrow the scope to resource groups, or use a `ReadOnly` lock |
| Google Cloud | `stop_idle_instance` | `compute.instances.stop`, `compute.instances.start` (undo) | Optional IAM condition on a Resource Manager tag |

Each cloud's README has the details, the limits and how to remove it:
[AWS](aws/terraform/README.md#write-access-opt-in),
[Azure](azure/README.md#write-access-opt-in),
[Google Cloud](gcp/README.md#write-access-opt-in).

## Getting started

```bash
git clone https://github.com/Xplorrio/cloud-onboarding.git
cd cloud-onboarding
```

Then follow the README of your cloud and tool. Each one covers the
prerequisites, the exact steps, what to paste into Xplorr, how to rotate the
credential, how to remove everything, and troubleshooting.

## Using the modules from your own code

Reference a module by the path of your clone:

```hcl
module "xplorr" {
  source = "./cloud-onboarding/aws/terraform"
}
```

or by a git source pinned to a release tag:

```hcl
module "xplorr" {
  source = "git::https://github.com/Xplorrio/cloud-onboarding.git//aws/terraform?ref=v0.2.0"
}
```

Always pin `ref` to a tag
(see [CHANGELOG.md](CHANGELOG.md)), never to a branch.

## Releases

Releases are annotated tags (`v0.2.0`, ...), listed in
[CHANGELOG.md](CHANGELOG.md). A tag is never moved or deleted once pushed, so a
module source pinned to a tag always gets the same code. Fixes ship as a new
tag. See [CONTRIBUTING.md](CONTRIBUTING.md#releases).

## Supported clouds and partitions

- **AWS:** the commercial partition only (`arn:aws:`). Xplorr builds role ARNs
  as `arn:aws:iam::<account>:role/<name>` and does not support GovCloud or the
  China regions.
- **Azure:** the global Azure cloud (`management.azure.com`).
- **Google Cloud:** the public Google Cloud.

## Repository checks

Every pull request runs:

- `terraform fmt -check`, `terraform validate`, `terraform test` (plan only,
  against fake credentials) and `tflint` for every module and example
- `terragrunt hcl fmt --check`, `terragrunt hcl validate` and a Terragrunt
  `validate` of each example
- `cfn-lint` on every CloudFormation template, and a check that
  `stackset.yaml` embeds the current `role.yaml`
- [`scripts/check-policy-drift.py`](scripts/check-policy-drift.py), which fails
  if the AWS read or write policy differs between Terraform and CloudFormation
- `bicep build`, `bicep build-params` and the Bicep linter on the Azure Bicep
  files, and `shellcheck` on the shell scripts
- `gitleaks` over the whole git history
- [`scripts/check-client-data.py`](scripts/check-client-data.py), which fails
  on any real looking AWS account ID, GUID, email address, Google Cloud billing
  account ID or known customer name
- [`scripts/check-style.py`](scripts/check-style.py)

Run them all locally with `make check`; see [CONTRIBUTING.md](CONTRIBUTING.md).

## Security

Report vulnerabilities privately to security@xplorr.io; see
[SECURITY.md](SECURITY.md).

## License

[Apache License 2.0](LICENSE)
