output "xplorr_connect_form" {
  description = "Values to enter in the Xplorr Connect account form for this account."
  value       = module.xplorr.xplorr_connect_form
}

output "role_arn" {
  description = "Add this to user_assumable_role_arns in examples/basic, in your first account."
  value       = module.xplorr.role_arn
}

output "next_steps" {
  description = "What to do after apply."
  value       = module.xplorr.next_steps
}
