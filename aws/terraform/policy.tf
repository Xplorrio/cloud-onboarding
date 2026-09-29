# The least-privilege policy. Every action below is one Xplorr calls, taken
# from services/cloud-sync-service/src in the Xplorr app. All are reads.

data "aws_iam_policy_document" "read" {
  # Cost figures, and coverage and utilization for reservations and Savings Plans.
  statement {
    sid    = "CostAndCommitments"
    effect = "Allow"
    actions = [
      "ce:GetCostAndUsage",
      "ce:GetCostAndUsageWithResources",
      "ce:GetReservationCoverage",
      "ce:GetReservationUtilization",
      "ce:GetReservationPurchaseRecommendation",
      "ce:GetSavingsPlansCoverage",
      "ce:GetSavingsPlansUtilizationDetails",
      "ce:GetSavingsPlansPurchaseRecommendation",
    ]
    resources = ["*"]
  }

  # The commitments you own, which Cost Explorer does not list in full.
  statement {
    sid    = "Commitments"
    effect = "Allow"
    actions = [
      "savingsplans:DescribeSavingsPlans",
      "ec2:DescribeReservedInstances",
      "rds:DescribeReservedDBInstances",
      "elasticache:DescribeReservedCacheNodes",
    ]
    resources = ["*"]
  }

  # Credit balances and expiry dates, read automatically every day.
  statement {
    sid    = "Credits"
    effect = "Allow"
    actions = [
      "billing:GetCredits",
      "billing:GetCreditAllocationHistory",
    ]
    resources = ["*"]
  }

  # The resource inventory and network costs by VPC, NAT gateway and load
  # balancer. tag:GetResources finds resources in every service.
  statement {
    sid    = "Inventory"
    effect = "Allow"
    actions = [
      "ec2:DescribeRegions",
      "ec2:DescribeInstances",
      "ec2:DescribeVolumes",
      "ec2:DescribeVpcs",
      "ec2:DescribeSubnets",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeNatGateways",
      "ec2:DescribeInternetGateways",
      "elasticloadbalancing:DescribeLoadBalancers",
      "tag:GetResources",
    ]
    resources = ["*"]
  }

  # CPU and attachment metrics behind idle EC2 and unattached EBS findings.
  statement {
    sid       = "IdleDetection"
    effect    = "Allow"
    actions   = ["cloudwatch:GetMetricStatistics"]
    resources = ["*"]
  }

  # On-demand rates for sizing recommendations.
  statement {
    sid       = "Pricing"
    effect    = "Allow"
    actions   = ["pricing:GetProducts"]
    resources = ["*"]
  }

  # Reconciling Xplorr's totals against your invoices.
  statement {
    sid       = "Invoices"
    effect    = "Allow"
    actions   = ["invoicing:ListInvoiceSummaries"]
    resources = ["*"]
  }

  # CloudTrail management events, for anomaly root cause analysis.
  dynamic "statement" {
    for_each = var.enable_audit_log ? [1] : []
    content {
      sid       = "AuditLog"
      effect    = "Allow"
      actions   = ["cloudtrail:LookupEvents"]
      resources = ["*"]
    }
  }

  # Optional FOCUS and carbon footprint exports in S3.
  dynamic "statement" {
    for_each = length(var.export_bucket_arns) > 0 ? [1] : []
    content {
      sid       = "ExportBucketList"
      effect    = "Allow"
      actions   = ["s3:ListBucket"]
      resources = var.export_bucket_arns
    }
  }

  dynamic "statement" {
    for_each = length(var.export_bucket_arns) > 0 ? [1] : []
    content {
      sid       = "ExportObjectRead"
      effect    = "Allow"
      actions   = ["s3:GetObject"]
      resources = [for arn in var.export_bucket_arns : "${arn}/*"]
    }
  }

  # Optional KMS keys that encrypt those exports (SSE-KMS).
  dynamic "statement" {
    for_each = length(var.export_kms_key_arns) > 0 ? [1] : []
    content {
      sid       = "ExportKmsDecrypt"
      effect    = "Allow"
      actions   = ["kms:Decrypt"]
      resources = var.export_kms_key_arns
    }
  }
}

# Who may assume the role.
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

    # xplorr_principal: only Xplorr's own onboarding roles, not every principal
    # in the Xplorr account.
    dynamic "condition" {
      for_each = local.customer_mode ? [] : [1]
      content {
        test     = "ArnLike"
        variable = "aws:PrincipalArn"
        values   = ["arn:${data.aws_partition.current.partition}:iam::${var.xplorr_account_id}:role/${var.xplorr_principal_role_pattern}"]
      }
    }
  }
}

# The only permission the customer_principal user has: assuming the Xplorr
# role here (and the write role, when enabled), the listed roles elsewhere,
# and optionally the roles of the same names anywhere in one AWS Organization.
data "aws_iam_policy_document" "user_assume" {
  count = local.create_user ? 1 : 0

  statement {
    sid     = "AssumeXplorrRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    resources = concat(
      [module.iam_role.arn],
      var.enable_write_role ? [module.write_role[0].role_arn] : [],
      var.user_assumable_role_arns,
    )
  }

  dynamic "statement" {
    for_each = var.user_assumable_org_id != "" ? [1] : []
    content {
      sid     = "AssumeXplorrRoleInOrganization"
      effect  = "Allow"
      actions = ["sts:AssumeRole"]
      resources = concat(
        ["arn:${data.aws_partition.current.partition}:iam::*:role/${var.role_name}"],
        var.enable_write_role ? ["arn:${data.aws_partition.current.partition}:iam::*:role/${var.write_role_name}"] : [],
      )

      condition {
        test     = "StringEquals"
        variable = "aws:ResourceOrgID"
        values   = [var.user_assumable_org_id]
      }
    }
  }
}
