# Plan only tests. The provider has fake credentials and every data source
# that would call AWS is overridden, so these run without an AWS account.

provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

override_data {
  target = data.aws_caller_identity.current
  values = {
    account_id = "111111111111"
  }
}

override_data {
  target = module.iam_role.data.aws_caller_identity.current
  values = {
    account_id = "111111111111"
  }
}

override_data {
  target = module.write_role[0].data.aws_caller_identity.current
  values = {
    account_id = "111111111111"
  }
}

override_data {
  target = module.write_role[0].module.iam_role.data.aws_caller_identity.current
  values = {
    account_id = "111111111111"
  }
}

# Role ARNs are only known after apply; give the plan the ARNs AWS would
# return, so the user's assume policy can be checked.
override_resource {
  target          = module.iam_role.aws_iam_role.default[0]
  override_during = plan
  values = {
    arn = "arn:aws:iam::111111111111:role/xplorr-readonly"
  }
}

override_resource {
  target          = module.write_role[0].module.iam_role.aws_iam_role.default[0]
  override_during = plan
  values = {
    arn = "arn:aws:iam::111111111111:role/xplorr-write"
  }
}

run "customer_principal_default" {
  command = plan

  assert {
    condition     = output.trust_mode == "customer_principal"
    error_message = "The default trust mode must be customer_principal."
  }

  assert {
    condition = length(setsubtract([
      "ce:GetCostAndUsage", "ce:GetCostAndUsageWithResources", "ce:GetReservationCoverage",
      "ce:GetReservationUtilization", "ce:GetReservationPurchaseRecommendation",
      "ce:GetSavingsPlansCoverage", "ce:GetSavingsPlansUtilizationDetails",
      "ce:GetSavingsPlansPurchaseRecommendation", "savingsplans:DescribeSavingsPlans",
      "ec2:DescribeReservedInstances", "rds:DescribeReservedDBInstances",
      "elasticache:DescribeReservedCacheNodes", "billing:GetCredits",
      "billing:GetCreditAllocationHistory", "ec2:DescribeRegions", "ec2:DescribeInstances",
      "ec2:DescribeVolumes", "ec2:DescribeVpcs", "ec2:DescribeSubnets",
      "ec2:DescribeSecurityGroups", "ec2:DescribeNatGateways", "ec2:DescribeInternetGateways",
      "elasticloadbalancing:DescribeLoadBalancers", "tag:GetResources",
      "cloudwatch:GetMetricStatistics", "pricing:GetProducts", "invoicing:ListInvoiceSummaries",
      "cloudtrail:LookupEvents",
    ], flatten([for s in jsondecode(data.aws_iam_policy_document.read.json).Statement : s.Action]))) == 0
    error_message = "The read policy is missing an action Xplorr calls."
  }

  assert {
    condition     = length(local.managed_policy_arns) == 0
    error_message = "ReadOnlyAccess must be opt-in."
  }

  assert {
    condition     = length(aws_iam_user_policy.assume_role) == 1
    error_message = "The user must be allowed to assume the role."
  }

  assert {
    condition     = output.xplorr_connect_form.aws_account_id == "111111111111" && output.xplorr_connect_form.role_name == "xplorr-readonly" && output.xplorr_connect_form.region == "us-east-1"
    error_message = "The connect form output is wrong."
  }

  assert {
    condition     = length(module.write_role) == 0 && output.xplorr_write_access_form == null
    error_message = "The write role must be off by default."
  }

  assert {
    condition     = length([for a in flatten([for s in jsondecode(data.aws_iam_policy_document.read.json).Statement : s.Action]) : a if !can(regex("^[a-z0-9-]+:(Get|Describe|List|Lookup)", a))]) == 0
    error_message = "The read-only role must only hold Get, Describe, List and Lookup calls."
  }
}

run "xplorr_principal_trusts_xplorr_with_external_id" {
  command = plan

  variables {
    trust_mode      = "xplorr_principal"
    iam_external_id = "example-external-id"
  }

  assert {
    condition     = jsondecode(data.aws_iam_policy_document.trust.json).Statement[0].Principal.AWS == "arn:aws:iam::732121667940:root"
    error_message = "xplorr_principal must trust the Xplorr account."
  }

  assert {
    condition     = jsondecode(data.aws_iam_policy_document.trust.json).Statement[0].Condition.StringEquals["sts:ExternalId"] == "example-external-id"
    error_message = "xplorr_principal must require the external ID."
  }

  assert {
    condition     = jsondecode(data.aws_iam_policy_document.trust.json).Statement[0].Condition.ArnLike["aws:PrincipalArn"] == "arn:aws:iam::732121667940:role/xplorr-*"
    error_message = "xplorr_principal must be limited to Xplorr roles named xplorr-*."
  }

  assert {
    condition     = output.user_name == null && length(aws_iam_user_policy.assume_role) == 0
    error_message = "xplorr_principal must not create a user."
  }
}

run "xplorr_principal_requires_external_id" {
  command = plan

  variables {
    trust_mode = "xplorr_principal"
  }

  expect_failures = [var.iam_external_id]
}

run "member_account_needs_a_principal" {
  command = plan

  variables {
    create_user = false
  }

  expect_failures = [var.trusted_principal_arns]
}

run "member_account_trusts_management_user" {
  command = plan

  variables {
    create_user            = false
    trusted_principal_arns = ["arn:aws:iam::222222222222:user/xplorr-assumer"]
    iam_external_id        = "example-external-id"
  }

  assert {
    condition     = jsondecode(data.aws_iam_policy_document.trust.json).Statement[0].Principal.AWS == "arn:aws:iam::222222222222:user/xplorr-assumer"
    error_message = "A member role must trust the listed principal."
  }
}

run "readonly_access_opt_in" {
  command = plan

  variables {
    attach_readonly_access = true
  }

  assert {
    condition     = length(local.managed_policy_arns) == 1 && contains(local.managed_policy_arns, "arn:aws:iam::aws:policy/ReadOnlyAccess")
    error_message = "attach_readonly_access must attach ReadOnlyAccess."
  }
}

run "audit_log_and_exports" {
  command = plan

  variables {
    enable_audit_log   = false
    export_bucket_arns = ["arn:aws:s3:::example-focus-exports"]
  }

  assert {
    condition     = !contains(flatten([for s in jsondecode(data.aws_iam_policy_document.read.json).Statement : s.Action]), "cloudtrail:LookupEvents")
    error_message = "enable_audit_log = false must drop cloudtrail:LookupEvents."
  }

  assert {
    condition     = contains(flatten([for s in jsondecode(data.aws_iam_policy_document.read.json).Statement : s.Resource]), "arn:aws:s3:::example-focus-exports/*")
    error_message = "Export buckets must be readable."
  }
}

run "uppercase_role_name_rejected" {
  command = plan

  variables {
    role_name = "XplorrReadOnly"
  }

  expect_failures = [var.role_name]
}

run "customer_principal_has_no_principal_arn_condition" {
  command = plan

  variables {
    create_user            = false
    trusted_principal_arns = ["arn:aws:iam::222222222222:user/xplorr-assumer"]
  }

  assert {
    condition     = !can(jsondecode(data.aws_iam_policy_document.trust.json).Statement[0].Condition)
    error_message = "Without an external ID the customer_principal trust policy has no condition."
  }
}

run "user_may_assume_roles_in_one_organization" {
  command = plan

  variables {
    user_assumable_org_id    = "o-abcd123456"
    user_assumable_role_arns = ["arn:aws:iam::222222222222:role/xplorr-readonly"]
  }

  assert {
    condition     = length(data.aws_iam_policy_document.user_assume) == 1
    error_message = "The user assume policy must exist."
  }
}

run "bad_org_id_rejected" {
  command = plan

  variables {
    user_assumable_org_id = "not-an-org"
  }

  expect_failures = [var.user_assumable_org_id]
}

run "export_kms_keys" {
  command = plan

  variables {
    export_bucket_arns  = ["arn:aws:s3:::example-focus-exports"]
    export_kms_key_arns = ["arn:aws:kms:us-east-1:111111111111:key/00000000-0000-0000-0000-000000000000"]
  }

  assert {
    condition     = contains(flatten([for s in jsondecode(data.aws_iam_policy_document.read.json).Statement : s.Action]), "kms:Decrypt")
    error_message = "export_kms_key_arns must grant kms:Decrypt."
  }
}

run "write_role_is_separate_and_opt_in" {
  command = plan

  variables {
    iam_external_id       = "example-read-external-id"
    enable_write_role     = true
    write_actions         = ["stop_idle_instance"]
    write_iam_external_id = "example-write-external-id"
  }

  assert {
    condition     = length(module.write_role) == 1 && output.write_role_name == "xplorr-write"
    error_message = "enable_write_role must create the xplorr-write role."
  }

  assert {
    condition     = output.write_granted_permissions == tolist(["ec2:DescribeInstances", "ec2:StartInstances", "ec2:StopInstances"])
    error_message = "Only the listed action type may be granted."
  }

  assert {
    condition     = length([for a in flatten([for s in jsondecode(data.aws_iam_policy_document.read.json).Statement : s.Action]) : a if startswith(a, "ec2:Stop") || startswith(a, "ec2:Start")]) == 0
    error_message = "The read-only role must never gain a write permission."
  }

  assert {
    condition     = contains(flatten([for s in jsondecode(data.aws_iam_policy_document.user_assume[0].json).Statement : s.Resource]), "arn:aws:iam::111111111111:role/xplorr-write")
    error_message = "The customer_principal user must be allowed to assume the write role."
  }

  assert {
    condition     = output.xplorr_write_access_form.write_iam_external_id == "example-write-external-id" && output.iam_external_id == "example-read-external-id"
    error_message = "The write role must carry its own external ID."
  }
}

run "write_role_needs_actions" {
  command = plan

  variables {
    enable_write_role = true
  }

  expect_failures = [var.write_actions]
}

run "write_external_id_must_differ" {
  command = plan

  variables {
    iam_external_id       = "example-external-id"
    enable_write_role     = true
    write_actions         = ["stop_idle_instance"]
    write_iam_external_id = "example-external-id"
  }

  expect_failures = [var.write_iam_external_id]
}

run "keyless_write_role_needs_its_external_id" {
  command = plan

  variables {
    trust_mode        = "xplorr_principal"
    iam_external_id   = "example-read-external-id"
    enable_write_role = true
    write_actions     = ["release_unassociated_eip"]
  }

  expect_failures = [var.write_iam_external_id]
}

run "write_role_in_organization" {
  command = plan

  variables {
    user_assumable_org_id = "o-abcd123456"
    enable_write_role     = true
    write_actions         = ["delete_unattached_ebs_volume"]
  }

  assert {
    condition     = contains(flatten([for s in jsondecode(data.aws_iam_policy_document.user_assume[0].json).Statement : s.Resource if s.Sid == "AssumeXplorrRoleInOrganization"]), "arn:aws:iam::*:role/xplorr-write")
    error_message = "With an organization id the user may assume the write role in any account of it."
  }
}
