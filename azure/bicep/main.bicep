// Xplorr read-only access to one Azure subscription.
//
// Deploy at subscription scope:
//   az deployment sub create --location <region> --template-file main.bicep --parameters main.example.bicepparam
//
// customer_principal (default, works today) creates a single tenant app
// registration and its service principal with the Microsoft Graph Bicep
// extension, then assigns the roles. No client secret is created: Bicep
// cannot create one, and it should not live in a deployment anyway. Create it
// afterwards in the portal or with az ad app credential reset (see README).
//
// xplorr_principal (coming soon) provisions the service principal of Xplorr's
// multi-tenant app instead, by its application (client) ID.
//
// To skip the Graph resources entirely (for example when the deploying
// identity cannot create app registrations), create the principal with the
// az CLI and pass its object ID in existingPrincipalObjectId.

targetScope = 'subscription'

extension microsoftGraphV1

@description('customer_principal (default, works today) or xplorr_principal (coming soon, needs Xplorr keyless onboarding).')
@allowed([
  'customer_principal'
  'xplorr_principal'
])
param trustMode string = 'customer_principal'

@description('customer_principal only. Display name of the app registration.')
param displayName string = 'xplorr-reader'

@description('customer_principal only. Immutable key the Graph extension uses to find the app registration again on a redeploy.')
param appUniqueName string = 'xplorr-reader'

@description('xplorr_principal only, and required there. Application (client) ID of Xplorr\'s multi-tenant app, which Xplorr gives you.')
param xplorrApplicationId string = ''

@description('Optional. Object ID of an existing service principal (Enterprise application object ID). When set, no Graph resources are deployed and the roles go to this principal.')
param existingPrincipalObjectId string = ''

@description('customer_principal with existingPrincipalObjectId only. Its application (client) ID, so the outputs are complete.')
param existingClientId string = ''

@description('Read-only built-in roles to assign on the subscription. Reader covers every call Xplorr makes, the Activity Log included. Monitoring Reader is the alternative for the Activity Log when Reader is not allowed.')
@allowed([
  'Reader'
  'Cost Management Reader'
  'Monitoring Reader'
])
param roleNames array = [
  'Reader'
  'Cost Management Reader'
]

@description('Also assign Carbon Optimization Reader, for carbon emissions reports.')
param enableCarbonOptimizationReader bool = false

// Built-in role definition IDs, the same in every tenant:
// https://learn.microsoft.com/azure/role-based-access-control/built-in-roles
var roleIds = {
  Reader: 'acdd72a7-3385-48ef-bd42-f606fba81ae7'
  'Cost Management Reader': '72fafb9e-0641-4937-9268-a91bfd8191a3'
  'Monitoring Reader': '43d0d8ad-25c7-4714-9337-8ba259a9fe05'
  'Carbon Optimization Reader': 'fa0d39e6-28e5-40cf-8521-1eb320653a4c'
}

var customerMode = trustMode == 'customer_principal'
var useExisting = !empty(existingPrincipalObjectId)
var roles = union(roleNames, enableCarbonOptimizationReader ? ['Carbon Optimization Reader'] : [])

resource app 'Microsoft.Graph/applications@v1.0' = if (customerMode && !useExisting) {
  uniqueName: appUniqueName
  displayName: displayName
  signInAudience: 'AzureADMyOrg'
  notes: 'Read-only access for Xplorr cloud cost management. Created by https://github.com/Xplorrio/cloud-onboarding'
}

resource customerSp 'Microsoft.Graph/servicePrincipals@v1.0' = if (customerMode && !useExisting) {
  appId: app!.appId
}

// Provisions (or reuses, after admin consent) the service principal of
// Xplorr's multi-tenant app in this tenant. It carries no Graph permissions;
// the role assignments below are all the access it gets.
resource xplorrSp 'Microsoft.Graph/servicePrincipals@v1.0' = if (!customerMode && !useExisting) {
  appId: xplorrAppIdChecked
}

// Fail fast on inputs that cannot work, before anything is created.
var xplorrAppIdChecked = (!customerMode && empty(xplorrApplicationId)) ? fail('xplorrApplicationId is required when trustMode is xplorr_principal.') : xplorrApplicationId
var existingClientIdChecked = (useExisting && customerMode && empty(existingClientId)) ? fail('existingClientId is required when existingPrincipalObjectId is set.') : existingClientId

var principalId = useExisting ? existingPrincipalObjectId : (customerMode ? customerSp!.id : xplorrSp!.id)
var clientId = useExisting ? (customerMode ? existingClientIdChecked : xplorrAppIdChecked) : (customerMode ? app!.appId : xplorrAppIdChecked)

module roleAssignments 'modules/subscription-roles.bicep' = {
  name: 'xplorr-role-assignments'
  params: {
    principalId: principalId
    roleDefinitionIds: [for role in roles: roleIds[role]]
  }
}

@description('Directory (tenant) ID, the tenantId key.')
output tenantId string = tenant().tenantId

@description('Application (client) ID, the clientId key.')
output clientId string = clientId

@description('Subscription ID, for the Azure subscription ID field and the subscriptionId key.')
output subscriptionId string = subscription().subscriptionId

@description('Service principal object ID, for billing and tenant scope role assignments.')
output servicePrincipalObjectId string = principalId

@description('The Credentials (JSON) to paste in Xplorr. Replace the clientSecret placeholder with the secret Value you create after the deployment.')
output credentialsJson string = string({
  clientId: clientId
  tenantId: tenant().tenantId
  clientSecret: 'PASTE_THE_CLIENT_SECRET_VALUE'
  subscriptionId: subscription().subscriptionId
})

@description('The roles assigned on the subscription.')
output assignedRoles array = roles
