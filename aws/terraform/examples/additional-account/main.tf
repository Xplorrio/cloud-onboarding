# A further standalone AWS account (not in the same AWS Organization, or you
# prefer not to use a StackSet).
#
# Xplorr keeps one set of base keys per organization, so this account gets no
# user. Its role trusts the user created by examples/basic in your first
# account. After applying here, add this role's ARN (output role_arn) to
# user_assumable_role_arns in examples/basic and apply there too, so that user may
# assume it.

terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0, < 7.0"
    }
  }
}

# Credentials for this additional account.
provider "aws" {
  region = var.region
}

module "xplorr" {
  source = "../../"

  create_user            = false
  trusted_principal_arns = [var.trusted_user_arn]
  role_name              = var.role_name
  iam_external_id        = var.iam_external_id
  region                 = var.region

  # Opt-in write access, off by default. A separate role; the read-only role
  # above is not changed.
  enable_write_role     = var.enable_write_role
  write_actions         = var.write_actions
  write_iam_external_id = var.write_iam_external_id
}
