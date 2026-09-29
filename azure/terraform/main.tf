data "azuread_client_config" "current" {}

locals {
  customer_mode = var.trust_mode == "customer_principal"

  owner_object_id = var.owner_object_id != "" ? var.owner_object_id : data.azuread_client_config.current.object_id

  # The module's service_principal_id output is the azuread resource ID,
  # /servicePrincipals/<object id>, not the bare object ID that Azure RBAC
  # needs, so the prefix is removed.
  customer_sp_object_id = local.customer_mode ? trimprefix(module.service_principal[0].service_principal_id, "/servicePrincipals/") : null

  principal_object_id = local.customer_mode ? local.customer_sp_object_id : azuread_service_principal.xplorr[0].object_id
  client_id           = local.customer_mode ? module.service_principal[0].service_principal_client_id : var.xplorr_application_id
  tenant_id           = data.azuread_client_config.current.tenant_id

  # Roles go on the management group when one is given, otherwise on each subscription.
  scopes = var.management_group_id != "" ? ["/providers/Microsoft.Management/managementGroups/${var.management_group_id}"] : [for s in var.subscription_ids : "/subscriptions/${s}"]

  # The opt-in write role: its permissions per action type, and where it is
  # assigned. The definition may be assigned anywhere under local.scopes.
  write_permissions = {
    deallocate_idle_vm = [
      "Microsoft.Compute/virtualMachines/deallocate/action",
      "Microsoft.Compute/virtualMachines/start/action",
    ]
  }

  write_role_actions = sort(distinct(flatten([for a in var.write_actions : local.write_permissions[a]])))
  write_scopes       = var.enable_write_role ? (length(var.write_scopes) > 0 ? var.write_scopes : local.scopes) : []

  roles = concat(var.role_names, var.enable_carbon_optimization_reader ? ["Carbon Optimization Reader"] : [])

  scope_roles = {
    for pair in setproduct(local.scopes, local.roles) : "${pair[1]} on ${pair[0]}" => {
      scope = pair[0]
      role  = pair[1]
    }
  }

  # Reservations and savings plans are tenant level resources with their own
  # RBAC scopes, so these roles cannot be inherited from a subscription.
  # Reservations Reader is assignable only at /providers/Microsoft.Capacity,
  # so it is referenced by its published built-in id rather than looked up.
  reservations_reader_role_id = "582fc458-8989-419f-a480-75249bc5db7e"

  tenant_roles = merge(
    var.enable_reservations_reader ? {
      "Reservations Reader" = {
        scope   = "/providers/Microsoft.Capacity"
        role_id = local.reservations_reader_role_id
      }
    } : {},
    var.enable_savings_plan_reader ? {
      "Savings plan reader" = {
        scope   = "/providers/Microsoft.BillingBenefits"
        role_id = data.azurerm_role_definition.savings_plan_reader[0].role_definition_id
      }
    } : {},
  )
}

# customer_principal: a single tenant app registration and its service
# principal, through the CloudDrove terraform-az-modules service-principle
# module. Everything Xplorr does not need is switched off: no Microsoft Graph
# API permissions, no app roles, no redirect or logout URLs, and no role
# assignment (the module supports one role at one scope; Xplorr's roles are
# assigned below). A secret is created only when create_client_secret is set.
module "service_principal" {
  source  = "terraform-az-modules/service-principle/azurerm"
  version = "1.0.0"
  count   = local.customer_mode ? 1 : 0

  name                      = var.display_name
  owner_object_id           = local.owner_object_id
  secret_map                = var.create_client_secret ? { xplorr = var.client_secret_duration } : {}
  enable_api_permission     = false
  application_roles         = []
  redirect_uris             = []
  front_channel_logout_urls = []
  enable_role_assignment    = false
}

check "client_secret_in_state" {
  assert {
    condition     = !(local.customer_mode && var.create_client_secret)
    error_message = "WARNING: create_client_secret is true, so the client secret value is stored in plain text in the Terraform state. Anyone who can read the state can sign in as this service principal. The module also rotates the secret every 180 days: the first apply after that replaces it, and Xplorr keeps the old one until you update the account. Prefer creating the secret in the portal (Certificates & secrets) and set create_client_secret = false."
  }
}

# xplorr_principal: provision the service principal of Xplorr's multi-tenant
# app in this tenant (the same as an administrator consenting to it), or reuse
# it if consent was already given. Xplorr requests no Microsoft Graph
# permissions, so the only access it gets is the Azure roles below.
resource "azuread_service_principal" "xplorr" {
  count = local.customer_mode ? 0 : 1

  client_id    = var.xplorr_application_id
  use_existing = true
}

check "xplorr_principal_coming_soon" {
  assert {
    condition     = local.customer_mode
    error_message = "trust_mode = xplorr_principal needs Xplorr keyless onboarding, which is coming soon. The roles are granted, but the Xplorr Connect account form still asks for a client secret today. Use customer_principal until keyless onboarding is live."
  }
}

resource "azurerm_role_assignment" "scope" {
  for_each = local.scope_roles

  scope                            = each.value.scope
  role_definition_name             = each.value.role
  principal_id                     = local.principal_object_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
  description                      = "Xplorr read-only access"
}

# "Savings plan reader" is not on the Azure built-in roles page, so its id is
# not pinned. It is looked up by name at the scope where it is assignable.
# Off by default; the README gives the az command as the preferred path.
data "azurerm_role_definition" "savings_plan_reader" {
  count = var.enable_savings_plan_reader ? 1 : 0

  name  = "Savings plan reader"
  scope = "/providers/Microsoft.BillingBenefits"
}

resource "azurerm_role_assignment" "tenant" {
  for_each = local.tenant_roles

  scope                            = each.value.scope
  role_definition_id               = "/providers/Microsoft.Authorization/roleDefinitions/${each.value.role_id}"
  principal_id                     = local.principal_object_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
  description                      = "Xplorr read-only access"
}

resource "azurerm_role_assignment" "focus_export" {
  for_each = toset(var.focus_export_scopes)

  scope                            = each.value
  role_definition_name             = "Storage Blob Data Reader"
  principal_id                     = local.principal_object_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
  description                      = "Xplorr reads the FOCUS cost export"
}

# Opt-in write access: a custom role holding only the actions of the listed
# action types, assigned to the same principal as the read-only roles. Azure
# RBAC conditions do not cover virtual machine actions, so no tag guard can be
# set here; see the README for the resource lock that blocks an action.
resource "azurerm_role_definition" "write" {
  count = var.enable_write_role ? 1 : 0

  name              = var.write_role_name
  scope             = local.scopes[0]
  description       = "Opt-in write access for Xplorr approved actions: ${join(", ", var.write_actions)}. Created by https://github.com/Xplorrio/cloud-onboarding"
  assignable_scopes = local.scopes

  permissions {
    actions = local.write_role_actions
  }
}

resource "azurerm_role_assignment" "write" {
  for_each = toset(local.write_scopes)

  scope                            = each.value
  role_definition_id               = azurerm_role_definition.write[0].role_definition_resource_id
  principal_id                     = local.principal_object_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
  description                      = "Xplorr approved actions (opt-in write access)"
}
