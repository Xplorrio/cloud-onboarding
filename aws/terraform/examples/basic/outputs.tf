output "xplorr_connect_form" {
  description = "Values to enter in the Xplorr Connect account form."
  value       = module.xplorr.xplorr_connect_form
}

output "user_arn" {
  description = "The user every other account's role must trust (trusted_user_arn in examples/additional-account)."
  value       = module.xplorr.user_arn
}

output "next_steps" {
  description = "What to do after apply."
  value       = module.xplorr.next_steps
}

output "xplorr_write_access_form" {
  description = "Values Xplorr asks for when you turn on write access. Null unless enable_write_role is true."
  value       = module.xplorr.xplorr_write_access_form
}
