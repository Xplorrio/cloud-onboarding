output "xplorr_connect_form" {
  description = "The values to enter in Xplorr: Infrastructure > Cloud Accounts > Connect account > AWS > IAM role. Print as JSON with: terraform output -json xplorr_connect_form | jq ."
  value = {
    aws_account_id  = data.aws_caller_identity.current.account_id
    role_name       = var.role_name
    iam_external_id = var.iam_external_id != "" ? var.iam_external_id : null
    region          = var.region
  }
}

output "aws_account_id" {
  description = "AWS account ID field in Xplorr."
  value       = data.aws_caller_identity.current.account_id
}

output "role_name" {
  description = "Role name field in Xplorr."
  value       = var.role_name
}

output "role_arn" {
  description = "ARN of the role. Xplorr builds the same ARN from the account ID and role name and shows it under the field, so you can check it. Pass it to user_assumable_role_arns in the account that holds the user."
  value       = module.iam_role.arn
}

output "iam_external_id" {
  description = "External ID field in Xplorr. Null when the trust policy has no external ID."
  value       = var.iam_external_id != "" ? var.iam_external_id : null
}

output "region" {
  description = "Region field in Xplorr."
  value       = var.region
}

output "trust_mode" {
  description = "The trust mode this role was created with."
  value       = var.trust_mode
}

output "user_name" {
  description = "customer_principal only. The IAM user whose access key you save in Xplorr once, as the organization's base keys."
  value       = local.create_user ? var.user_name : null
}

output "user_arn" {
  description = "customer_principal only. ARN of the IAM user. Pass it as trusted_principal_arns when creating the role in every other account."
  value       = local.create_user ? module.iam_user.arn : null
}

output "next_steps" {
  description = "What to do after apply."
  value = join("\n", concat(local.customer_mode ? compact([
    local.create_user ? "1. Create an access key for the IAM user ${var.user_name}: IAM > Users > ${var.user_name} > Security credentials > Create access key > Third-party service. Terraform does not create it, so the secret never lands in the Terraform state. Skip this if your Xplorr organization already has base keys for this user." : "1. No key is needed for this account: Xplorr uses the base keys of the user it trusts (${join(", ", var.trusted_principal_arns)}). Make sure that user may assume ${module.iam_role.arn} (user_assumable_role_arns or user_assumable_org_id where the user is created).",
    "2. In Xplorr go to Infrastructure > Cloud Accounts > Connect account > AWS > IAM role.",
    "3. If your Xplorr organization has no base keys yet, enter that access key ID and secret access key and save them.",
    "4. Enter AWS account ID ${data.aws_caller_identity.current.account_id}, role name ${var.role_name}${var.iam_external_id != "" ? ", external ID ${var.iam_external_id}" : ""} and region ${var.region}, then click Test connection and Connect.",
    ]) : [
    "This role trusts Xplorr's AWS account ${var.xplorr_account_id} (roles matching ${var.xplorr_principal_role_pattern} only) with external ID ${var.iam_external_id}.",
    "It needs Xplorr keyless onboarding, which is coming soon. Until Xplorr can assume roles as its own account, use trust_mode = customer_principal.",
    ], var.enable_write_role ? [
    "Write access (opt in): the separate role ${var.write_role_name} may carry out ${join(", ", var.write_actions)}${var.write_iam_external_id != "" ? ", with its own external ID ${var.write_iam_external_id}" : ""}. Xplorr uses it only after a person in your Xplorr organization approves an action. Print the values Xplorr asks for with: terraform output -json xplorr_write_access_form",
  ] : []))
}

output "xplorr_write_access_form" {
  description = "With enable_write_role. The values Xplorr asks for when you turn on write access for this account: account ID, write role name and ARN, the write external ID and the action types. Null when the write role is off."
  value       = var.enable_write_role ? module.write_role[0].xplorr_write_access_form : null
}

output "write_role_arn" {
  description = "With enable_write_role. ARN of the write role. In customer_principal mode, add it to user_assumable_role_arns where the user is created, when that is another account."
  value       = var.enable_write_role ? module.write_role[0].role_arn : null
}

output "write_role_name" {
  description = "With enable_write_role. Name of the write role."
  value       = var.enable_write_role ? var.write_role_name : null
}

output "write_iam_external_id" {
  description = "With enable_write_role. The write role's external ID. Null when there is none."
  value       = var.enable_write_role ? module.write_role[0].iam_external_id : null
}

output "write_granted_permissions" {
  description = "With enable_write_role. Every IAM action the write role allows."
  value       = var.enable_write_role ? module.write_role[0].granted_permissions : null
}
