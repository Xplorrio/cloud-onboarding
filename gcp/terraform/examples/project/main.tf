# One Google Cloud project, connected today with the customer_principal trust
# mode: a service account in the project that holds the billing export. The
# key is created afterwards with gcloud, so it never lands in Terraform state.

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

  project_id             = var.project_id
  billing_dataset_id     = var.billing_dataset_id
  create_billing_dataset = var.create_billing_dataset
  bigquery_location      = var.bigquery_location
  billing_table          = var.billing_table
  billing_account_id     = var.billing_account_id

  # Opt-in write access, off by default: a separate custom role for the
  # approved actions you list. The viewer roles are not changed.
  enable_write_role = var.enable_write_role
  write_actions     = var.write_actions
  write_protect_tag = var.write_protect_tag
}
