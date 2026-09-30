data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

locals {
  customer_mode = var.trust_mode == "customer_principal"
  create_user   = local.customer_mode && var.create_user

  trusted_principals = local.customer_mode ? concat(
    local.create_user ? [module.iam_user.arn] : [],
    var.trusted_principal_arns,
  ) : ["arn:${data.aws_partition.current.partition}:iam::${var.xplorr_account_id}:root"]

  managed_policy_arns = var.attach_readonly_access ? ["arn:${data.aws_partition.current.partition}:iam::aws:policy/ReadOnlyAccess"] : []

  repository = "https://github.com/Xplorrio/cloud-onboarding"
}

# The IAM user that assumes the role in customer_principal mode. It has no
# console password and Terraform creates no access key for it, so no secret
# is ever written to the Terraform state. Create the key in the console.
module "iam_user" {
  source  = "clouddrove/iam-user/aws"
  version = "1.3.2"

  enabled                       = local.create_user
  create_user                   = local.create_user
  name                          = var.user_name
  label_order                   = ["name"]
  managedby                     = "xplorr"
  repository                    = local.repository
  create_access_key             = false
  create_iam_user_login_profile = false
  policy_enabled                = false
  force_destroy                 = true
  permissions_boundary          = var.permissions_boundary_arn
}

resource "aws_iam_user_policy" "assume_role" {
  count = local.create_user ? 1 : 0

  name   = "xplorr-assume-role"
  user   = var.user_name
  policy = data.aws_iam_policy_document.user_assume[0].json

  depends_on = [module.iam_user]
}

# The read-only role Xplorr assumes.
module "iam_role" {
  source  = "clouddrove/iam-role/aws"
  version = "1.4.0"

  name                 = var.role_name
  label_order          = ["name"]
  managedby            = "xplorr"
  repository           = local.repository
  description          = "Read-only access for Xplorr cloud cost management"
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  policy_enabled       = true
  policy               = data.aws_iam_policy_document.read.json
  managed_policy_arns  = local.managed_policy_arns
  max_session_duration = var.max_session_duration
  permissions_boundary = var.permissions_boundary_arn
  tags                 = var.tags
}

