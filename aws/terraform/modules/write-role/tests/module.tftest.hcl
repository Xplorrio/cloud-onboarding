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

variables {
  trusted_principal_arns = ["arn:aws:iam::111111111111:user/xplorr-assumer"]
}

run "stop_only_grants_stop_and_start" {
  command = plan

  variables {
    actions = ["stop_idle_instance"]
  }

  assert {
    condition     = output.granted_permissions == tolist(["ec2:DescribeInstances", "ec2:StartInstances", "ec2:StopInstances"])
    error_message = "stop_idle_instance must grant only StopInstances, StartInstances and DescribeInstances."
  }

  assert {
    condition     = [for s in jsondecode(data.aws_iam_policy_document.write.json).Statement : s.Resource if s.Sid == "StopIdleInstance"][0] == "arn:aws:ec2:*:111111111111:instance/*"
    error_message = "Stop and start must be limited to instances in this account."
  }

  assert {
    condition     = output.role_name == "xplorr-write"
    error_message = "The default role name must be xplorr-write."
  }

  assert {
    condition     = jsondecode(data.aws_iam_policy_document.trust.json).Statement[0].Principal.AWS == "arn:aws:iam::111111111111:user/xplorr-assumer"
    error_message = "customer_principal must trust the listed user."
  }
}

run "every_action_type" {
  command = plan

  variables {
    actions = ["stop_idle_instance", "delete_unattached_ebs_volume", "release_unassociated_eip"]
  }

  assert {
    condition = output.granted_permissions == tolist([
      "ec2:CreateSnapshot", "ec2:CreateTags", "ec2:DeleteVolume", "ec2:DescribeAddresses",
      "ec2:DescribeInstances", "ec2:DescribeSnapshots", "ec2:DescribeVolumes",
      "ec2:ReleaseAddress", "ec2:StartInstances", "ec2:StopInstances",
    ])
    error_message = "The granted permissions differ from the documented matrix."
  }

  assert {
    condition     = [for s in jsondecode(data.aws_iam_policy_document.write.json).Statement : s.Condition.StringEquals["ec2:CreateAction"] if s.Sid == "TagSnapshotOnCreate"][0] == "CreateSnapshot"
    error_message = "CreateTags must be limited to tagging a snapshot while creating it."
  }

  assert {
    condition     = !contains(output.granted_permissions, "ec2:DisassociateAddress") && !contains(output.granted_permissions, "ec2:TerminateInstances")
    error_message = "The role must never detach addresses or terminate instances."
  }
}

run "protect_tag_denies_every_change" {
  command = plan

  variables {
    actions = ["stop_idle_instance", "delete_unattached_ebs_volume", "release_unassociated_eip"]
  }

  assert {
    condition = length(setsubtract(
      ["ec2:StopInstances", "ec2:StartInstances", "ec2:CreateSnapshot", "ec2:DeleteVolume", "ec2:ReleaseAddress"],
      [for s in jsondecode(data.aws_iam_policy_document.write.json).Statement : s.Action if s.Sid == "DenyProtectedResources"][0],
    )) == 0
    error_message = "The protect tag Deny must cover every changing call."
  }

  assert {
    condition     = [for s in jsondecode(data.aws_iam_policy_document.write.json).Statement : s.Effect if s.Sid == "DenyProtectedResources"][0] == "Deny"
    error_message = "The protect tag guard must be an explicit Deny."
  }

  assert {
    condition     = [for s in jsondecode(data.aws_iam_policy_document.write.json).Statement : s.Condition.StringEqualsIgnoreCase["aws:ResourceTag/xplorr:protect"] if s.Sid == "DenyProtectedResources"][0] == "true"
    error_message = "The Deny must match xplorr:protect = true."
  }
}

run "protect_tag_can_be_turned_off" {
  command = plan

  variables {
    actions         = ["release_unassociated_eip"]
    protect_tag_key = ""
  }

  assert {
    condition     = length([for s in jsondecode(data.aws_iam_policy_document.write.json).Statement : s if s.Sid == "DenyProtectedResources"]) == 0
    error_message = "protect_tag_key = \"\" must drop the Deny."
  }
}

run "allowed_regions" {
  command = plan

  variables {
    actions         = ["stop_idle_instance"]
    allowed_regions = ["eu-west-1"]
  }

  assert {
    condition     = [for s in jsondecode(data.aws_iam_policy_document.write.json).Statement : s.Condition.StringEquals["aws:RequestedRegion"] if s.Sid == "StopIdleInstance"][0] == "eu-west-1"
    error_message = "allowed_regions must limit the changing calls to those regions."
  }
}

run "xplorr_principal_trust_matches_the_read_role_shape" {
  command = plan

  variables {
    actions                = ["stop_idle_instance"]
    trust_mode             = "xplorr_principal"
    trusted_principal_arns = []
    iam_external_id        = "example-write-external-id"
  }

  assert {
    condition     = jsondecode(data.aws_iam_policy_document.trust.json).Statement[0].Principal.AWS == "arn:aws:iam::732121667940:root"
    error_message = "xplorr_principal must trust the Xplorr account."
  }

  assert {
    condition     = jsondecode(data.aws_iam_policy_document.trust.json).Statement[0].Condition.StringEquals["sts:ExternalId"] == "example-write-external-id"
    error_message = "xplorr_principal must require the write external ID."
  }

  assert {
    condition     = jsondecode(data.aws_iam_policy_document.trust.json).Statement[0].Condition.ArnLike["aws:PrincipalArn"] == "arn:aws:iam::732121667940:role/xplorr-*"
    error_message = "xplorr_principal must be limited to Xplorr roles named xplorr-*."
  }
}

run "xplorr_principal_requires_external_id" {
  command = plan

  variables {
    actions                = ["stop_idle_instance"]
    trust_mode             = "xplorr_principal"
    trusted_principal_arns = []
  }

  expect_failures = [var.iam_external_id]
}

run "no_actions_rejected" {
  command = plan

  variables {
    actions = []
  }

  expect_failures = [var.actions]
}

run "rightsize_needs_no_cloud_permission" {
  command = plan

  variables {
    actions = ["rightsize_instance"]
  }

  expect_failures = [var.actions]
}

run "role_name_keeps_the_prefix" {
  command = plan

  variables {
    actions   = ["stop_idle_instance"]
    role_name = "write-access"
  }

  expect_failures = [var.role_name]
}

run "customer_principal_needs_a_principal" {
  command = plan

  variables {
    actions                = ["stop_idle_instance"]
    trusted_principal_arns = []
  }

  expect_failures = [var.trusted_principal_arns]
}
