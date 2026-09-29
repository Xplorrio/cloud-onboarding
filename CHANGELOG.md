# Changelog

All notable changes to this repository are listed here. Versions follow
[Semantic Versioning](https://semver.org/).

## v0.2.0 (2026-09-29)

Minor version: it adds new, opt-in templates and inputs. Nothing changes for
existing users until they turn write access on.

### Added

- Opt-in write access for Xplorr approved actions, off by default in every
  template and never merged into the read-only role. Each action type is
  granted on its own:
  - AWS: `stop_idle_instance`, `delete_unattached_ebs_volume` and
    `release_unassociated_eip`. A separate `xplorr-write` role with its own
    external ID. In `customer_principal` mode it trusts the same
    `xplorr-assumer` user as the read-only role. In `xplorr_principal` mode it
    trusts only Xplorr's dedicated actions role,
    `arn:aws:iam::732121667940:role/xplorr-actions`, matched exactly
    (`aws:PrincipalArn` `StringEquals`; `write_xplorr_principal_arn`,
    `XplorrPrincipalArn`), not the `xplorr-*` roles the read-only role trusts. An explicit Deny refuses resources tagged
    `xplorr:protect` = `true`; optional region limit. Terraform
    (`enable_write_role`, `write_actions`, `write_iam_external_id`, and the
    standalone `aws/terraform/modules/write-role`), Terragrunt (`write-role`
    folder, or the same inputs in `single-account` and `keyless`) and
    CloudFormation (`write-role.yaml`, a separate stack).
  - Azure: `deallocate_idle_vm`, a custom role `xplorr-write` assigned to a
    separate identity: its own app registration and service principal
    `xplorr-write` (no secret unless you opt in), or Xplorr's separate write
    app in `xplorr_principal` mode. On the subscriptions, the management group
    or chosen resource groups. Terraform (`enable_write_role`) and Bicep
    (`write-role.bicep`), both outputting the write client ID and tenant ID.
  - Google Cloud: `stop_idle_instance`, a custom role `xplorrWrite` granted to
    a separate service account, `xplorr-write@<project>`, with its own key or,
    keyless, impersonated by Xplorr's separate actions service account. An
    optional IAM condition on a Resource Manager tag. Terraform
    (`enable_write_role`) and `gcloud.sh` (`--enable-write-action`).
  - `rightsize_instance` needs no cloud permission: it is a Terraform pull
    request.
- Outputs for the values Xplorr asks for when you turn on write access:
  `xplorr_write_access_form` (AWS), `xplorr_write_access` (Azure, Google
  Cloud), and the matching stack and deployment outputs.
- `scripts/check-policy-drift.py` also compares the AWS write policy between
  Terraform and CloudFormation, and the Xplorr actions role the write role
  trusts. CI validates the Terragrunt `write-role` folder.

### Changed

- `scripts/check-client-data.py` skips the message of one reviewed commit
  on main (`653ceb1`, the owner's own Co-authored-by trailer), listed by full
  sha with its reason in `ALLOWED_COMMIT_MESSAGES`. Its files are still
  scanned, and any other match still fails; `scripts/test-check-client-data.py`
  proves both and runs in CI.

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
