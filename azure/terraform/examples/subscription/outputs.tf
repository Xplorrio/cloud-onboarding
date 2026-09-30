output "xplorr_connect_form" {
  description = "Per subscription: the Azure subscription ID field and the Credentials (JSON) to paste in Xplorr."
  value       = module.xplorr.xplorr_connect_form
}

output "credentials_json_with_secret" {
  description = "Only with create_client_secret = true. Credentials (JSON) with the secret."
  value       = module.xplorr.credentials_json_with_secret
  sensitive   = true
}

output "tenant_id" {
  description = "Directory (tenant) ID."
  value       = module.xplorr.tenant_id
}

output "client_id" {
  description = "Application (client) ID."
  value       = module.xplorr.client_id
}

output "service_principal_object_id" {
  description = "Service principal object ID, for billing role assignments."
  value       = module.xplorr.service_principal_object_id
}

output "role_assignments" {
  description = "Role assignments made."
  value       = module.xplorr.role_assignments
}

output "next_steps" {
  description = "What to do after apply."
  value       = module.xplorr.next_steps
}
