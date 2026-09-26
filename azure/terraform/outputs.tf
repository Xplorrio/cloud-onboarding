output "xplorr_connect_form" {
  description = "One entry per subscription: what to type in the Azure subscription ID field and paste in the Credentials (JSON) field of Xplorr's Connect account form. Replace PASTE_THE_CLIENT_SECRET_VALUE with the secret Value you created in the portal."
  value = {
    for s in var.subscription_ids : s => {
      subscription_id = s
      credentials_json = jsonencode({
        clientId       = local.client_id
        tenantId       = local.tenant_id
        clientSecret   = local.customer_mode ? "PASTE_THE_CLIENT_SECRET_VALUE" : null
        subscriptionId = s
      })
    }
  }
}

output "credentials_json_with_secret" {
  description = "Only with create_client_secret = true. The complete Credentials (JSON) per subscription, secret included. Read it with: terraform output -json credentials_json_with_secret"
  sensitive   = true
  value = local.customer_mode && var.create_client_secret ? {
    for s in var.subscription_ids : s => jsonencode({
      clientId       = local.client_id
      tenantId       = local.tenant_id
      clientSecret   = module.service_principal[0].service_principal_secrets["xplorr"].value
      subscriptionId = s
    })
  } : null
}

output "tenant_id" {
  description = "Directory (tenant) ID, the tenantId key."
  value       = local.tenant_id
}

output "client_id" {
  description = "Application (client) ID, the clientId key."
  value       = local.client_id
}

output "subscription_ids" {
  description = "The subscriptions to add in Xplorr, one cloud account each (the subscriptionId key)."
  value       = var.subscription_ids
}

output "service_principal_object_id" {
  description = "Object ID of the service principal (the Enterprise application object ID). Use it for the billing role assignments described in the README."
  value       = local.principal_object_id
}

output "trust_mode" {
  description = "The trust mode the roles were granted with."
  value       = var.trust_mode
}

output "role_assignments" {
  description = "Every role assignment this module made, as role on scope."
  value = concat(
    keys(local.scope_roles),
    [for role, r in local.tenant_roles : "${role} on ${r.scope}"],
    [for scope in var.focus_export_scopes : "Storage Blob Data Reader on ${scope}"],
  )
}

output "next_steps" {
  description = "What to do after apply."
  value = local.customer_mode ? join("\n", [
    var.create_client_secret ? "1. Read the secret with: terraform output -json credentials_json_with_secret (it is also in your state)." : "1. Create the client secret: Microsoft Entra ID > App registrations > ${var.display_name} > Certificates & secrets > New client secret. Copy the Value (not the Secret ID); Azure shows it once.",
    "2. In Xplorr go to Infrastructure > Cloud Accounts > Connect account and set Provider to Microsoft Azure.",
    "3. For each entry in xplorr_connect_form, enter subscription_id in Azure subscription ID and paste credentials_json with the secret in place. Test connection, then Connect.",
    "4. Optional: grant a billing role for credits and invoices (see azure/README.md, Billing roles).",
    ]) : join("\n", [
    "Xplorr's multi-tenant app ${var.xplorr_application_id} now has its service principal and read-only roles in this tenant.",
    "Keyless onboarding is coming soon; until it is live the Connect account form needs a client secret, so use trust_mode = customer_principal today.",
  ])
}
