# Plan only tests against mocked providers, so they run without an Azure
# tenant or credentials.

mock_provider "azuread" {
  mock_data "azuread_client_config" {
    defaults = {
      object_id = "22222222-2222-2222-2222-222222222222"
      tenant_id = "33333333-3333-3333-3333-333333333333"
      client_id = "44444444-4444-4444-4444-444444444444"
    }
  }
}

mock_provider "time" {}

# The azuread resource ID of a service principal is /servicePrincipals/<object
# id>; the module outputs that ID, and the role assignments need the bare
# object ID.
override_resource {
  target          = module.service_principal[0].azuread_service_principal.sp
  override_during = plan
  values = {
    id        = "/servicePrincipals/77777777-7777-7777-7777-777777777777"
    object_id = "77777777-7777-7777-7777-777777777777"
    client_id = "88888888-8888-8888-8888-888888888888"
  }
}

override_resource {
  target          = module.service_principal[0].azuread_application.sp
  override_during = plan
  values = {
    id        = "/applications/99999999-9999-9999-9999-999999999999"
    client_id = "88888888-8888-8888-8888-888888888888"
  }
}

override_resource {
  target          = module.write_service_principal[0].azuread_service_principal.sp
  override_during = plan
  values = {
    id        = "/servicePrincipals/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    object_id = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    client_id = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
  }
}

override_resource {
  target          = module.write_service_principal[0].azuread_application.sp
  override_during = plan
  values = {
    id        = "/applications/cccccccc-cccc-cccc-cccc-cccccccccccc"
    client_id = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
  }
}

mock_provider "azurerm" {
  mock_data "azurerm_role_definition" {
    defaults = {
      role_definition_id = "55555555-5555-5555-5555-555555555555"
    }
  }
}

variables {
  subscription_ids = [
    "00000000-0000-0000-0000-000000000000",
    "11111111-1111-1111-1111-111111111111",
  ]
}

run "customer_principal_default" {
  command = plan

  assert {
    condition     = output.trust_mode == "customer_principal"
    error_message = "The default trust mode must be customer_principal."
  }

  assert {
    condition     = length(module.service_principal) == 1 && length(azuread_service_principal.xplorr) == 0
    error_message = "customer_principal must create the app registration and service principal through the service-principle module."
  }

  assert {
    condition     = length(nonsensitive(module.service_principal[0].service_principal_secrets)) == 0
    error_message = "No client secret may be created by default."
  }

  assert {
    condition     = output.client_id == "88888888-8888-8888-8888-888888888888"
    error_message = "clientId must be the new app registration's client ID."
  }

  assert {
    condition     = output.service_principal_object_id == "77777777-7777-7777-7777-777777777777"
    error_message = "The service principal object ID must be the bare GUID, not the /servicePrincipals/ resource ID."
  }

  assert {
    condition     = alltrue([for a in azurerm_role_assignment.scope : a.principal_id == "77777777-7777-7777-7777-777777777777"])
    error_message = "Role assignments must use the bare service principal object ID."
  }

  assert {
    condition = toset(keys(azurerm_role_assignment.scope)) == toset([
      "Reader on /subscriptions/00000000-0000-0000-0000-000000000000",
      "Cost Management Reader on /subscriptions/00000000-0000-0000-0000-000000000000",
      "Reader on /subscriptions/11111111-1111-1111-1111-111111111111",
      "Cost Management Reader on /subscriptions/11111111-1111-1111-1111-111111111111",
    ])
    error_message = "Reader and Cost Management Reader must be assigned on every subscription."
  }

  assert {
    condition     = length(azurerm_role_assignment.tenant) == 0 && length(azurerm_role_assignment.focus_export) == 0
    error_message = "Tenant scope and FOCUS roles must be opt-in."
  }

  assert {
    condition     = alltrue([for a in azurerm_role_assignment.scope : a.principal_type == "ServicePrincipal"])
    error_message = "Every assignment must target the service principal."
  }

  assert {
    condition     = output.tenant_id == "33333333-3333-3333-3333-333333333333"
    error_message = "tenant_id must come from the signed in tenant."
  }

  assert {
    condition     = toset(keys(output.xplorr_connect_form)) == toset(var.subscription_ids)
    error_message = "There must be one Connect account form per subscription."
  }

  assert {
    condition     = output.credentials_json_with_secret == null
    error_message = "No secret output without create_client_secret."
  }
}

run "management_group_scope" {
  command = plan

  variables {
    management_group_id = "mg-example"
  }

  assert {
    condition = toset(keys(azurerm_role_assignment.scope)) == toset([
      "Reader on /providers/Microsoft.Management/managementGroups/mg-example",
      "Cost Management Reader on /providers/Microsoft.Management/managementGroups/mg-example",
    ])
    error_message = "With a management group the roles must be assigned once, on it."
  }

  assert {
    condition     = length(output.xplorr_connect_form) == 2
    error_message = "Each subscription still needs its own Connect account form."
  }
}

run "opt_in_roles" {
  command = plan

  variables {
    enable_carbon_optimization_reader = true
    enable_reservations_reader        = true
    enable_savings_plan_reader        = true
    focus_export_scopes = [
      "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Storage/storageAccounts/stexample",
    ]
  }

  assert {
    condition     = contains(keys(azurerm_role_assignment.scope), "Carbon Optimization Reader on /subscriptions/00000000-0000-0000-0000-000000000000")
    error_message = "Carbon Optimization Reader must be added to every scope."
  }

  assert {
    condition     = azurerm_role_assignment.tenant["Reservations Reader"].scope == "/providers/Microsoft.Capacity" && azurerm_role_assignment.tenant["Savings plan reader"].scope == "/providers/Microsoft.BillingBenefits"
    error_message = "Reservations and savings plan roles must be at tenant scope."
  }

  assert {
    condition     = azurerm_role_assignment.tenant["Reservations Reader"].role_definition_id == "/providers/Microsoft.Authorization/roleDefinitions/582fc458-8989-419f-a480-75249bc5db7e"
    error_message = "Reservations Reader must use its published built-in role definition id."
  }

  assert {
    condition = alltrue([
      for a in values(azurerm_role_assignment.tenant) :
      can(regex("^/providers/Microsoft\\.Authorization/roleDefinitions/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", a.role_definition_id))
    ])
    error_message = "Tenant scope role assignments must use a tenant level role definition id."
  }

  assert {
    condition     = length(azurerm_role_assignment.focus_export) == 1
    error_message = "Storage Blob Data Reader must be assigned on each FOCUS export scope."
  }
}

run "opt_in_client_secret" {
  command = plan

  variables {
    create_client_secret = true
  }

  expect_failures = [check.client_secret_in_state]

  assert {
    condition     = contains(keys(nonsensitive(module.service_principal[0].service_principal_secrets)), "xplorr")
    error_message = "create_client_secret must create one secret, named xplorr."
  }
}

run "xplorr_principal" {
  command = plan

  variables {
    trust_mode            = "xplorr_principal"
    xplorr_application_id = "66666666-6666-6666-6666-666666666666"
  }

  expect_failures = [check.xplorr_principal_coming_soon]

  assert {
    condition     = length(module.service_principal) == 0 && length(azuread_service_principal.xplorr) == 1
    error_message = "xplorr_principal must create no app registration, only the service principal of Xplorr's app."
  }

  assert {
    condition     = output.client_id == "66666666-6666-6666-6666-666666666666"
    error_message = "clientId must be Xplorr's application ID."
  }

  assert {
    condition     = one(azuread_service_principal.xplorr[*].use_existing) == true
    error_message = "An existing service principal (after admin consent) must be reused."
  }
}

run "xplorr_principal_needs_app_id" {
  command = plan

  variables {
    trust_mode = "xplorr_principal"
  }

  expect_failures = [var.xplorr_application_id, check.xplorr_principal_coming_soon]
}

run "cost_management_reader_alone_rejected" {
  command = plan

  variables {
    role_names = ["Cost Management Reader"]
  }

  expect_failures = [var.role_names]
}

run "write_role_off_by_default" {
  command = plan

  assert {
    condition     = length(azurerm_role_definition.write) == 0 && length(azurerm_role_assignment.write) == 0 && output.xplorr_write_access == null
    error_message = "The write role must be off by default."
  }
}

run "write_role_deallocate_on_each_subscription" {
  command = plan

  variables {
    enable_write_role = true
    write_actions     = ["deallocate_idle_vm"]
  }

  assert {
    condition = azurerm_role_definition.write[0].permissions[0].actions == tolist([
      "Microsoft.Compute/virtualMachines/deallocate/action",
      "Microsoft.Compute/virtualMachines/start/action",
    ])
    error_message = "deallocate_idle_vm must grant only deallocate and start."
  }

  assert {
    condition     = length(coalesce(azurerm_role_definition.write[0].permissions[0].data_actions, [])) == 0 && length(coalesce(azurerm_role_definition.write[0].permissions[0].not_actions, [])) == 0
    error_message = "The custom role must hold nothing but the listed actions."
  }

  assert {
    condition     = toset(keys(azurerm_role_assignment.write)) == toset(["/subscriptions/00000000-0000-0000-0000-000000000000", "/subscriptions/11111111-1111-1111-1111-111111111111"])
    error_message = "Without write_scopes the role is assigned on every subscription."
  }

  assert {
    condition     = alltrue([for k, v in azurerm_role_assignment.scope : v.role_definition_name != "xplorr-write"])
    error_message = "The read-only assignments must not change."
  }

  assert {
    condition     = length(module.write_service_principal) == 1 && output.xplorr_write_access.client_id == "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb" && output.client_id == "88888888-8888-8888-8888-888888888888"
    error_message = "Write access must use its own app registration, not the read-only one."
  }

  assert {
    condition     = alltrue([for k, v in azurerm_role_assignment.write : v.principal_id == "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"])
    error_message = "The write role must be assigned to the write service principal only."
  }

  assert {
    condition     = alltrue([for k, v in azurerm_role_assignment.scope : v.principal_id == "77777777-7777-7777-7777-777777777777"])
    error_message = "The read-only roles must stay on the read-only service principal."
  }

  assert {
    condition     = length(nonsensitive(module.write_service_principal[0].service_principal_secrets)) == 0 && output.xplorr_write_access.tenant_id == "33333333-3333-3333-3333-333333333333"
    error_message = "No write secret by default, and the tenant ID must be output."
  }
}

run "write_role_keyless_uses_xplorr_write_app" {
  command = plan

  variables {
    trust_mode                  = "xplorr_principal"
    xplorr_application_id       = "dddddddd-dddd-dddd-dddd-dddddddddddd"
    enable_write_role           = true
    write_actions               = ["deallocate_idle_vm"]
    xplorr_write_application_id = "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee"
  }

  expect_failures = [check.xplorr_principal_coming_soon]

  assert {
    condition     = length(module.write_service_principal) == 0 && length(azuread_service_principal.xplorr_write) == 1 && azuread_service_principal.xplorr_write[0].client_id == "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee"
    error_message = "Keyless write access must use Xplorr's separate write app."
  }
}

run "write_role_keyless_needs_write_app_id" {
  command = plan

  variables {
    trust_mode            = "xplorr_principal"
    xplorr_application_id = "dddddddd-dddd-dddd-dddd-dddddddddddd"
    enable_write_role     = true
    write_actions         = ["deallocate_idle_vm"]
  }

  expect_failures = [var.xplorr_write_application_id, check.xplorr_principal_coming_soon]
}

run "write_app_id_must_differ" {
  command = plan

  variables {
    trust_mode                  = "xplorr_principal"
    xplorr_application_id       = "dddddddd-dddd-dddd-dddd-dddddddddddd"
    enable_write_role           = true
    write_actions               = ["deallocate_idle_vm"]
    xplorr_write_application_id = "dddddddd-dddd-dddd-dddd-dddddddddddd"
  }

  expect_failures = [var.xplorr_write_application_id, check.xplorr_principal_coming_soon]
}

run "write_role_on_resource_groups_only" {
  command = plan

  variables {
    enable_write_role = true
    write_actions     = ["deallocate_idle_vm"]
    write_scopes      = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example"]
  }

  assert {
    condition     = keys(azurerm_role_assignment.write) == ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example"]
    error_message = "write_scopes must narrow the assignment to those resource groups."
  }

  assert {
    condition     = azurerm_role_definition.write[0].assignable_scopes == tolist(["/subscriptions/00000000-0000-0000-0000-000000000000", "/subscriptions/11111111-1111-1111-1111-111111111111"])
    error_message = "The definition must be assignable under the connected subscriptions."
  }
}

run "write_role_needs_actions" {
  command = plan

  variables {
    enable_write_role = true
  }

  expect_failures = [var.write_actions]
}

run "unknown_write_action_rejected" {
  command = plan

  variables {
    enable_write_role = true
    write_actions     = ["delete_vm"]
  }

  expect_failures = [var.write_actions]
}

