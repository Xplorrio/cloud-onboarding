# The opt-in write role. It is a separate role from the read-only one, with
# its own external ID, and grants only the actions listed in var.actions.
#
# Xplorr uses it only to carry out an action a person in your Xplorr
# organization has approved. Every statement below belongs to one action type;
# an action type that is not listed grants nothing.

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

locals {
  customer_mode = var.trust_mode == "customer_principal"
  partition     = data.aws_partition.current.partition
  account_id    = data.aws_caller_identity.current.account_id

  stop_instances = contains(var.actions, "stop_idle_instance")
  delete_volumes = contains(var.actions, "delete_unattached_ebs_volume")
  release_eips   = contains(var.actions, "release_unassociated_eip")

  instance_arn = "arn:${local.partition}:ec2:*:${local.account_id}:instance/*"
  volume_arn   = "arn:${local.partition}:ec2:*:${local.account_id}:volume/*"
  # Snapshot ARNs have no account id.
  snapshot_arn = "arn:${local.partition}:ec2:*::snapshot/*"
  eip_arn      = "arn:${local.partition}:ec2:*:${local.account_id}:elastic-ip/*"

  # The calls that change something, per action type. The protect tag Deny
  # covers all of them.
  changing_actions = concat(
    local.stop_instances ? ["ec2:StopInstances", "ec2:StartInstances"] : [],
    local.delete_volumes ? ["ec2:CreateSnapshot", "ec2:DeleteVolume"] : [],
    local.release_eips ? ["ec2:ReleaseAddress"] : [],
  )

  # Reads Xplorr makes with this role right before and after acting, to check
  # the resource is still in the state the recommendation saw. Describe calls
  # take no resource ARN, so they are granted on "*".
  describe_actions = concat(
    local.stop_instances ? ["ec2:DescribeInstances"] : [],
    local.delete_volumes ? ["ec2:DescribeVolumes", "ec2:DescribeSnapshots"] : [],
    local.release_eips ? ["ec2:DescribeAddresses"] : [],
  )

  # xplorr_principal: the account of the one Xplorr role that may assume this
  # role, narrowed to that role by the aws:PrincipalArn condition below.
  xplorr_account_id  = split(":", var.xplorr_principal_arn)[4]
  trusted_principals = local.customer_mode ? var.trusted_principal_arns : ["arn:${local.partition}:iam::${local.xplorr_account_id}:root"]

  repository = "https://github.com/Xplorrio/cloud-onboarding"
}

data "aws_iam_policy_document" "write" {
  # stop_idle_instance: stop an instance Xplorr found idle, and start it again
  # to undo the action.
  dynamic "statement" {
    for_each = local.stop_instances ? [1] : []
    content {
      sid       = "StopIdleInstance"
      effect    = "Allow"
      actions   = ["ec2:StopInstances", "ec2:StartInstances"]
      resources = [local.instance_arn]

      dynamic "condition" {
        for_each = length(var.allowed_regions) > 0 ? [1] : []
        content {
          test     = "StringEquals"
          variable = "aws:RequestedRegion"
          values   = var.allowed_regions
        }
      }
    }
  }

  # delete_unattached_ebs_volume: snapshot the volume first, so it can be
  # restored, then delete it. EC2 refuses DeleteVolume on a volume that is
  # attached (VolumeInUse); IAM has no condition key for the attachment state.
  dynamic "statement" {
    for_each = local.delete_volumes ? [1] : []
    content {
      sid       = "SnapshotBeforeDelete"
      effect    = "Allow"
      actions   = ["ec2:CreateSnapshot"]
      resources = [local.volume_arn, local.snapshot_arn]

      dynamic "condition" {
        for_each = length(var.allowed_regions) > 0 ? [1] : []
        content {
          test     = "StringEquals"
          variable = "aws:RequestedRegion"
          values   = var.allowed_regions
        }
      }
    }
  }

  # Tags on the snapshot, so it records which volume and which Xplorr action
  # it came from. Only while creating the snapshot, never on anything else.
  dynamic "statement" {
    for_each = local.delete_volumes ? [1] : []
    content {
      sid       = "TagSnapshotOnCreate"
      effect    = "Allow"
      actions   = ["ec2:CreateTags"]
      resources = [local.snapshot_arn]

      condition {
        test     = "StringEquals"
        variable = "ec2:CreateAction"
        values   = ["CreateSnapshot"]
      }
    }
  }

  dynamic "statement" {
    for_each = local.delete_volumes ? [1] : []
    content {
      sid       = "DeleteUnattachedVolume"
      effect    = "Allow"
      actions   = ["ec2:DeleteVolume"]
      resources = [local.volume_arn]

      dynamic "condition" {
        for_each = length(var.allowed_regions) > 0 ? [1] : []
        content {
          test     = "StringEquals"
          variable = "aws:RequestedRegion"
          values   = var.allowed_regions
        }
      }
    }
  }

  # release_unassociated_eip: release an Elastic IP that is not associated
  # with anything. The role has no ec2:DisassociateAddress, so it cannot
  # detach an address that is in use.
  dynamic "statement" {
    for_each = local.release_eips ? [1] : []
    content {
      sid       = "ReleaseUnassociatedAddress"
      effect    = "Allow"
      actions   = ["ec2:ReleaseAddress"]
      resources = [local.eip_arn]

      dynamic "condition" {
        for_each = length(var.allowed_regions) > 0 ? [1] : []
        content {
          test     = "StringEquals"
          variable = "aws:RequestedRegion"
          values   = var.allowed_regions
        }
      }
    }
  }

  statement {
    sid       = "CheckStateBeforeActing"
    effect    = "Allow"
    actions   = local.describe_actions
    resources = ["*"]
  }

  # Resources tagged protect_tag_key = true are never changed. An explicit
  # Deny wins over every Allow, including any added to this role later.
  dynamic "statement" {
    for_each = var.protect_tag_key != "" ? [1] : []
    content {
      sid       = "DenyProtectedResources"
      effect    = "Deny"
      actions   = local.changing_actions
      resources = ["*"]

      condition {
        test     = "StringEqualsIgnoreCase"
        variable = "aws:ResourceTag/${var.protect_tag_key}"
        values   = ["true"]
      }
    }
  }
}

# Who may assume the role. customer_principal: the same principals as the
# read-only role. xplorr_principal: only Xplorr's dedicated actions role,
# matched exactly, never the xplorr-* pattern the read-only role trusts, and
# the write role's own external ID.
data "aws_iam_policy_document" "trust" {
  statement {
    sid     = "AllowAssume"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = local.trusted_principals
    }

    dynamic "condition" {
      for_each = var.iam_external_id != "" ? [1] : []
      content {
        test     = "StringEquals"
        variable = "sts:ExternalId"
        values   = [var.iam_external_id]
      }
    }

    dynamic "condition" {
      for_each = local.customer_mode ? [] : [1]
      content {
        test     = "StringEquals"
        variable = "aws:PrincipalArn"
        values   = [var.xplorr_principal_arn]
      }
    }
  }
}

module "iam_role" {
  source  = "clouddrove/iam-role/aws"
  version = "1.4.0"

  name                 = var.role_name
  label_order          = ["name"]
  managedby            = "xplorr"
  repository           = local.repository
  description          = "Opt-in write access for Xplorr approved actions: ${join(", ", var.actions)}"
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  policy_enabled       = true
  policy               = data.aws_iam_policy_document.write.json
  max_session_duration = var.max_session_duration
  permissions_boundary = var.permissions_boundary_arn
  tags                 = var.tags
}
