output "xplorr_connect_form" {
  description = "Values to enter in Xplorr, one Connect account per AWS account."
  value = {
    management = module.management.xplorr_connect_form
    member_a   = module.member_a.xplorr_connect_form
    member_b   = module.member_b.xplorr_connect_form
  }
}

output "base_keys_user" {
  description = "Create an access key for this user in the console and save it once in Xplorr as the organization's base keys."
  value       = module.management.user_name
}
