output "xplorr_write_access_form" {
  description = "The values Xplorr asks for when you turn on write access for this AWS account. Print as JSON with: terraform output -json xplorr_write_access_form | jq ."
  value = {
    aws_account_id        = local.account_id
    write_role_name       = var.role_name
    write_role_arn        = module.iam_role.arn
    write_iam_external_id = var.iam_external_id != "" ? var.iam_external_id : null
    actions               = var.actions
  }
}

output "role_arn" {
  description = "ARN of the write role. In customer_principal mode, add it to user_assumable_role_arns where the xplorr-assumer user is created."
  value       = module.iam_role.arn
}

output "role_name" {
  description = "Name of the write role."
  value       = var.role_name
}

output "iam_external_id" {
  description = "The write role's external ID. Null when the trust policy has none."
  value       = var.iam_external_id != "" ? var.iam_external_id : null
}

output "actions" {
  description = "The action types this role may carry out."
  value       = var.actions
}

output "granted_permissions" {
  description = "Every IAM action the role allows, for your review."
  value       = sort(distinct(concat(local.changing_actions, local.describe_actions, local.delete_volumes ? ["ec2:CreateTags"] : [])))
}

output "protect_tag_key" {
  description = "Resources with this tag set to true are refused. Null when the guard is off."
  value       = var.protect_tag_key != "" ? var.protect_tag_key : null
}

output "trust_mode" {
  description = "The trust mode this role was created with."
  value       = var.trust_mode
}
