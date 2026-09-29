# Your first (or only) AWS account, connected today with the
# customer_principal trust mode: an IAM user in this account assumes a
# read-only role.
#
# Xplorr keeps one set of base keys per organization, so this is the only
# account that gets the user. To connect more standalone accounts, create the
# role there with examples/additional-account, then list those role ARNs in
# user_assumable_role_arns here and apply again.

terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0, < 7.0"
    }
  }
}

provider "aws" {
  region = var.region
}

module "xplorr" {
  source = "../../"

  role_name                = var.role_name
  iam_external_id          = var.iam_external_id
  region                   = var.region
  attach_readonly_access   = var.attach_readonly_access
  user_assumable_role_arns = var.user_assumable_role_arns

  # Opt-in write access, off by default. A separate role; the read-only role
  # above is not changed.
  enable_write_role     = var.enable_write_role
  write_actions         = var.write_actions
  write_iam_external_id = var.write_iam_external_id
}
