# The xplorr_principal trust mode. REQUIRES XPLORR KEYLESS ONBOARDING (COMING
# SOON): the role trusts Xplorr's own AWS account with an external ID, and no
# IAM user or access key is created. Until Xplorr can assume roles as its own
# account, use the basic example instead.

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
  region = "us-east-1"
}

module "xplorr" {
  source = "../../"

  trust_mode        = "xplorr_principal"
  xplorr_account_id = var.xplorr_account_id
  iam_external_id   = var.iam_external_id

  # Opt-in write access, off by default. A separate role; the read-only role
  # above is not changed.
  enable_write_role     = var.enable_write_role
  write_actions         = var.write_actions
  write_iam_external_id = var.write_iam_external_id
}
