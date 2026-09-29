output "service_account_email" {
  description = "The service account Xplorr signs in as."
  value       = module.xplorr.service_account_email
}

output "xplorr_connect_form" {
  description = "Fields for the Xplorr Connect account form."
  value       = module.xplorr.xplorr_connect_form
}

output "key_create_command" {
  description = "Run this to create the key outside Terraform."
  value       = module.xplorr.key_create_command
}

output "credentials_json_command" {
  description = "Run after key_create_command: writes the complete Credentials (JSON) to xplorr-credentials.json."
  value       = module.xplorr.credentials_json_command
}

output "next_steps" {
  description = "What is left to do by hand."
  value       = module.xplorr.next_steps
}

output "xplorr_write_access" {
  description = "Values Xplorr asks for when you turn on write access. Null unless enable_write_role is true."
  value       = module.xplorr.xplorr_write_access
}
