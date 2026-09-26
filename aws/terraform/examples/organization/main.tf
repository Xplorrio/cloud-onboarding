# An AWS Organization, connected today with the customer_principal trust mode.
#
# The management (payer) account gets the IAM user and a role; each member
# account gets only the role, trusting that one user. In Xplorr you save the
# user's access key once as the organization's base keys, then connect each
# account by its ID and the role name.
#
# Terraform needs one provider block per account, so this example lists two
# members. For many accounts, or to cover accounts created later, use
# aws/cloudformation/stackset.yaml instead.

terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0, < 7.0"
    }
  }
}

# Credentials for the management account.
provider "aws" {
  region = var.region
}

# Member accounts, reached through the role AWS Organizations creates in every
# account it creates. Change the role name if yours differs.
provider "aws" {
  alias  = "member_a"
  region = var.region

  assume_role {
    role_arn = "arn:aws:iam::${var.member_a_account_id}:role/${var.member_access_role_name}"
  }
}

provider "aws" {
  alias  = "member_b"
  region = var.region

  assume_role {
    role_arn = "arn:aws:iam::${var.member_b_account_id}:role/${var.member_access_role_name}"
  }
}

locals {
  member_role_arns = [
    "arn:aws:iam::${var.member_a_account_id}:role/${var.role_name}",
    "arn:aws:iam::${var.member_b_account_id}:role/${var.role_name}",
  ]
}

module "management" {
  source = "../../"

  role_name                = var.role_name
  iam_external_id          = var.iam_external_id
  region                   = var.region
  user_assumable_role_arns = local.member_role_arns
}

module "member_a" {
  source    = "../../"
  providers = { aws = aws.member_a }

  role_name              = var.role_name
  iam_external_id        = var.iam_external_id
  region                 = var.region
  create_user            = false
  trusted_principal_arns = [module.management.user_arn]
}

module "member_b" {
  source    = "../../"
  providers = { aws = aws.member_b }

  role_name              = var.role_name
  iam_external_id        = var.iam_external_id
  region                 = var.region
  create_user            = false
  trusted_principal_arns = [module.management.user_arn]
}
