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

output "write_credentials_json_with_secret" {
  description = "Only with enable_write_role and write_create_client_secret. The write Credentials (JSON) per subscription, secret included."
  sensitive   = true
  value = local.create_write_app && var.write_create_client_secret ? {
    for s in var.subscription_ids : s => jsonencode({
      clientId       = local.write_client_id
      tenantId       = local.tenant_id
      clientSecret   = module.write_service_principal[0].service_principal_secrets["xplorr"].value
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
    [for scope in local.write_scopes : "${var.write_role_name} on ${scope}"],
    [for role, r in local.tenant_roles : "${role} on ${r.scope}"],
    [for scope in var.focus_export_scopes : "Storage Blob Data Reader on ${scope}"],
  )
}

output "next_steps" {
  description = "What to do after apply."
  value = join("\n", concat(local.customer_mode ? [
    var.create_client_secret ? "1. Read the secret with: terraform output -json credentials_json_with_secret (it is also in your state)." : "1. Create the client secret: Microsoft Entra ID > App registrations > ${var.display_name} > Certificates & secrets > New client secret. Copy the Value (not the Secret ID); Azure shows it once.",
    "2. In Xplorr go to Infrastructure > Cloud Accounts > Connect account and set Provider to Microsoft Azure.",
    "3. For each entry in xplorr_connect_form, enter subscription_id in Azure subscription ID and paste credentials_json with the secret in place. Test connection, then Connect.",
    "4. Optional: grant a billing role for credits and invoices (see azure/README.md, Billing roles).",
    ] : [
    "Xplorr's multi-tenant app ${var.xplorr_application_id} now has its service principal and read-only roles in this tenant.",
    "Keyless onboarding is coming soon; until it is live the Connect account form needs a client secret, so use trust_mode = customer_principal today.",
    ], var.enable_write_role ? [
    "Write access (opt in): the separate identity ${local.customer_mode ? var.write_display_name : var.xplorr_write_application_id} holds the custom role ${var.write_role_name}, which may carry out ${join(", ", var.write_actions)} on ${join(", ", local.write_scopes)}. ${local.customer_mode && !var.write_create_client_secret ? "Create its client secret in the portal (App registrations > ${var.write_display_name} > Certificates & secrets). " : ""}Xplorr uses it only after a person in your Xplorr organization approves an action. Print the values with: terraform output -json xplorr_write_access",
  ] : []))
}

output "xplorr_write_access" {
  description = "With enable_write_role. What Xplorr asks for when you turn on write access: the separate write identity (client_id, tenant_id, service principal object ID), per subscription the write Credentials (JSON) with a secret placeholder, the custom role's ID and name, the scopes it is assigned on and the action types. Null when the write role is off."
  value = var.enable_write_role ? {
    client_id                   = local.write_client_id
    tenant_id                   = local.tenant_id
    service_principal_object_id = local.write_principal_object_id
    credentials_json = {
      for s in var.subscription_ids : s => jsonencode({
        clientId       = local.write_client_id
        tenantId       = local.tenant_id
        clientSecret   = local.customer_mode ? "PASTE_THE_WRITE_CLIENT_SECRET_VALUE" : null
        subscriptionId = s
      })
    }
    custom_role_id   = azurerm_role_definition.write[0].role_definition_resource_id
    custom_role_name = var.write_role_name
    scopes           = local.write_scopes
    actions          = var.write_actions
    permissions      = local.write_role_actions
  } : null
}
