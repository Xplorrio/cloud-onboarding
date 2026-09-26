# One service account in the billing export project, with the option to grant
# its read roles on the organization or on folders as well.
#
# Those wider grants are OFF by default (enable_org_level_grants = false).
# Xplorr currently reads only the connected project: recommendations,
# inventory and audit logs are read with projects/<project_id> scope, so
# organization or folder grants give Xplorr nothing today. Turn them on only
# to prepare one service account for several projects, each connected to
# Xplorr as its own cloud account. See the README.

terraform {
  required_version = ">= 1.10.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 8.0, < 9.0"
    }
  }
}

provider "google" {
  project = var.project_id
}

module "xplorr" {
  source = "../../"

  project_id              = var.project_id
  billing_dataset_id      = var.billing_dataset_id
  bigquery_location       = var.bigquery_location
  billing_account_id      = var.billing_account_id
  enable_org_level_grants = var.enable_org_level_grants
  organization_id         = var.organization_id
  folder_ids              = var.folder_ids
}
