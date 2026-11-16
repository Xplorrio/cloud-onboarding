# Changelog

All notable changes to this repository are listed here. Versions follow
[Semantic Versioning](https://semver.org/).

## v0.0.7 (2026-11-16)

### AWS

- Terraform: `enable_cost_optimization_hub` turns on AWS Cost Optimization Hub
  in the account (`aws_costoptimizationhub_enrollment_status`), and
  `cost_optimization_hub_include_member_accounts` enrolls every member account
  when run in the management account. Both default to `false`, since this
  changes an account setting rather than creating an Xplorr resource. The
  organization example turns both on. CloudFormation has no resource for it,
  so CloudFormation users still turn it on in the console. New output
  `cost_optimization_hub_status`.

## v0.0.6 (2026-11-16)

### AWS

- New `Recommendations` statement with
  `cost-optimization-hub:ListRecommendations`, `logs:DescribeLogGroups` and
  `s3:GetLifecycleConfiguration`. Xplorr uses them for recommendations beyond
  idle EC2 and unattached EBS: AWS Cost Optimization Hub advice for EC2, EBS,
  Lambda, ECS, RDS and more, CloudWatch log groups with no retention, and
  large S3 buckets without a lifecycle rule. All three are reads. Cost
  Optimization Hub itself must be turned on once in the management account
  (Billing and Cost Management > Cost Optimization Hub); until then it returns
  nothing and Xplorr says so on Data health.

## v0.0.5 (2026-11-11)

### AWS

- `ecs:DescribeClusters` and `ecs:DescribeCapacityProviders` in the
  `Containers` statement. Xplorr uses them to show each ECS capacity provider
  with its EC2 instances, instance types and cost. Both are reads. Without
  them the ECS page groups ECS instances by Auto Scaling group.

## v0.0.4 (2026-11-11)

### AWS

- New `Containers` statement with `ecs:ListTasks` and `ecs:DescribeTasks`.
  Xplorr uses them to count the ECS tasks running now; the tagging API also
  returns stopped tasks. Both are reads. Without them the ECS page counts the
  tasks seen in the last sync and names the missing permission.

## v0.0.3 (2026-11-11)

### AWS

- Lightsail reads in the `Inventory` statement: `lightsail:GetInstances`,
  `GetStaticIps`, `GetInstanceSnapshots`, `GetKeyPairs`, `GetDisks`,
  `GetDiskSnapshots`, `GetLoadBalancers` and `GetRelationalDatabases`. Xplorr
  uses them to replace stale Lightsail ARNs from the tagging API with real
  names and state.
- New `StorageAndTraffic` statement with `cloudwatch:ListMetrics` and
  `rds:DescribeDBInstances`, for the Storage page and network link traffic:
  finding S3 buckets, EFS file systems, Transit Gateway attachments and VPN
  tunnels that have metrics, and reading RDS allocated storage.
- All are reads. Without them those features degrade and the console names
  the missing permission.

## v0.0.1 (2026-09-30)

First release. Infrastructure code that gives Xplorr read only access to your
AWS, Azure and Google Cloud costs, commitments, credits and resource
inventory. Xplorr needs read only access and never changes resources: every
permission these templates grant is a read, and none of them creates a role or
identity that could create, modify or delete anything.

Every template has two trust modes. `customer_principal` (the default, works
today) signs Xplorr in as an identity you create and own, with a credential you
create yourself so it never lands in Terraform state by default.
`xplorr_principal` (coming soon, with Xplorr keyless onboarding) trusts
Xplorr's own identity instead, so nothing of yours is stored. Each template
ends by printing the values the Xplorr **Connect account** form asks for.

### AWS

- Terraform module (on `clouddrove/iam-role/aws` 1.4.0 and
  `clouddrove/iam-user/aws` 1.3.2) creating a least-privilege read-only role
  `xplorr-readonly` with exactly the calls Xplorr makes, and in
  `customer_principal` mode an IAM user with no password and no access key
  whose only permission is assuming the Xplorr roles.
- Optional `export_kms_key_arns` grants `kms:Decrypt` for SSE-KMS encrypted
  export buckets.
- Examples: `basic` (first account), `additional-account`, `organization` and
  `keyless`. They ship no fixed external ID; generate one with
  `openssl rand -hex 16`.
- Terragrunt folders `single-account` and `keyless`, defaulting to the module
  in the cloned repository, or a pinned release through
  `XPLORR_MODULE_SOURCE`.
- CloudFormation `role.yaml` (one account) and `stackset.yaml` (every member
  account of an organization, including accounts added later).
- `xplorr_principal` mode trusts Xplorr's AWS account `732121667940`, limited
  to its `xplorr-*` roles, with a required external ID.

### Azure

- Terraform module on `terraform-az-modules/service-principle` 1.0.0: a single
  tenant app registration and service principal with Reader and Cost
  Management Reader on each subscription, or once on a management group.
  Optional Carbon Optimization Reader, tenant scope Reservations Reader and
  Savings plan reader, and Storage Blob Data Reader for a FOCUS export. No
  client secret unless you opt in. Subscription and management group examples.
- Bicep templates for subscription and management group scope, using the
  Microsoft Graph Bicep extension 1.0.0. They never create a secret.

### Google Cloud

- Terraform module creating a service account with the viewer roles Xplorr
  uses (BigQuery Data Viewer on the billing dataset, BigQuery Job User,
  Recommender, Cloud Asset, Compute, Storage Bucket and Logs Viewer), the APIs
  Xplorr calls, and optional Billing Account Viewer, organization or folder
  grants and billing export dataset. No key unless you opt in. Project and
  organization examples.
- `gcloud.sh`, an idempotent script doing the same. It writes
  `xplorr-connect-form.json` and `xplorr-credentials.json` with mode 600 and
  reminds you to delete them; both are gitignored.

### Repository

- CI running Terraform fmt, validate, test and tflint, Terragrunt, cfn-lint, a
  check that `stackset.yaml` embeds the current `role.yaml`, an AWS policy
  drift check between Terraform and CloudFormation, Bicep, shellcheck,
  gitleaks, a client data scan with its own test, and a style check. Run them
  all locally with `make check`.
- Release policy: releases are annotated tags and a pushed tag is never moved
  or deleted.
