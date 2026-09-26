# Changelog

All notable changes to this repository are listed here. Versions follow
[Semantic Versioning](https://semver.org/).

## v0.1.1 (2026-09-26)

### Fixed

- Azure: Reservations Reader is assigned by its built-in role id at
  `/providers/Microsoft.Capacity` instead of a name lookup at a subscription,
  where it is not assignable. Savings plan reader, whose id is not published on
  the built-in roles page, is looked up by name at
  `/providers/Microsoft.BillingBenefits`; it stays off by default and the az
  command is the documented path.
- Google Cloud: `gcloud.sh` writes `xplorr-connect-form.json` and
  `xplorr-credentials.json` with mode 600 and reminds you to delete them; both
  are gitignored.
- AWS: the examples no longer ship a fixed external ID. They leave it empty,
  with the `openssl rand -hex 16` command to generate one.
- AWS: `examples/basic` uses `user_assumable_role_arns`, the module's own input
  name.

### Added

- AWS: optional `export_kms_key_arns` (`ExportKmsKeyArn` in CloudFormation)
  grants `kms:Decrypt` for SSE-KMS encrypted export buckets.
- Docs: release policy (tags are immutable), supported partitions, the
  Google Cloud `regions` credential field, fork pull request handling, and a
  checklist for making the repository public.

## v0.1.0 (2026-09-26)

First release.

### AWS

- Terraform module (on `clouddrove/iam-role/aws` 1.4.0 and
  `clouddrove/iam-user/aws` 1.3.2) creating a least-privilege read-only role
  with exactly the calls Xplorr makes, and in `customer_principal` mode an IAM
  user with no password and no access key that may only assume it.
- Examples: `basic` (first account), `additional-account`, `organization`,
  `keyless`.
- Terragrunt examples, defaulting to the module in the cloned repository.
- CloudFormation `role.yaml` (one account) and `stackset.yaml` (every member
  account of an organization).
- `xplorr_principal` mode (coming soon): trusts Xplorr's AWS account
  `732121667940`, limited to its `xplorr-*` roles, with a required external ID.

### Azure

- Terraform module on `terraform-az-modules/service-principle` 1.0.0, with
  subscription and management group examples.
- Bicep templates for subscription and management group scope using the
  Microsoft Graph Bicep extension 1.0.0.

### Google Cloud

- Terraform module creating a service account with the viewer roles Xplorr
  uses, with project and organization examples.
- `gcloud.sh`, an idempotent script doing the same.

### Repository

- CI running Terraform fmt, validate, test and tflint, Terragrunt, cfn-lint,
  Bicep, shellcheck, gitleaks, an AWS policy drift check, a client data scan
  and a style check.
