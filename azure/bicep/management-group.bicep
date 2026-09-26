// Xplorr read-only access to many subscriptions through one management group.
//
// Deploy at management group scope:
//   az deployment mg create --management-group-id <management-group> --location <region> \
//     --template-file management-group.bicep --parameters management-group.example.bicepparam
//
// The roles are assigned once on the management group and every subscription
// below it inherits them. Each subscription is still its own cloud account in
// Xplorr, so list the ones to connect in subscriptionIds; the outputs hold
// one Credentials (JSON) per subscription.
//
// Trust modes, the missing client secret and existingPrincipalObjectId work
// exactly as in main.bicep.

targetScope = 'managementGroup'

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

@description('Read-only built-in roles to assign on the management group. Reader covers every call Xplorr makes, the Activity Log included. Monitoring Reader is the alternative for the Activity Log when Reader is not allowed.')
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

@description('The subscriptions under this management group to connect to Xplorr, one cloud account each. Used only for the outputs.')
@minLength(1)
param subscriptionIds array

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

module roleAssignments 'modules/management-group-roles.bicep' = {
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

@description('Service principal object ID, for billing and tenant scope role assignments.')
output servicePrincipalObjectId string = principalId

@description('One entry per subscription: the Azure subscription ID field and the Credentials (JSON) to paste in Xplorr. Replace the clientSecret placeholder with the secret Value you create after the deployment.')
output connectForms array = [
  for id in subscriptionIds: {
    subscriptionId: id
    credentialsJson: string({
      clientId: clientId
      tenantId: tenant().tenantId
      clientSecret: 'PASTE_THE_CLIENT_SECRET_VALUE'
      subscriptionId: id
    })
  }
]

@description('The roles assigned on the management group.')
output assignedRoles array = roles
