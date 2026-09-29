// Opt-in write access for Xplorr approved actions, on one subscription.
//
// Deploy at subscription scope, after main.bicep (or the Terraform module),
// from azure/bicep where bicepconfig.json pins the Microsoft Graph extension:
//   az deployment sub create --name xplorr-write --location <region> \
//     --template-file write-role.bicep --parameters write-role.example.bicepparam
//
// Creates a separate identity for write access and a custom role holding only
// the actions of the action types you list, assigned to that identity only.
// customer_principal: its own app registration and service principal
// (xplorr-write), set up like the read-only one; no client secret is created,
// create it afterwards as for the read-only app. xplorr_principal: the service
// principal of Xplorr's separate multi-tenant write app. The read-only
// identity and roles are not changed. Xplorr uses this role only after a
// person in your Xplorr organization approves an action.
//
// Azure RBAC conditions do not cover virtual machine actions, so no tag guard
// can be set in the role. A ReadOnly resource lock blocks start and deallocate
// for everyone, Xplorr included; see the README.

targetScope = 'subscription'

extension microsoftGraphV1

@description('The same trust mode as your read-only deployment. customer_principal creates a separate app registration and service principal for write access; xplorr_principal uses Xplorr\'s separate write app.')
@allowed([
  'customer_principal'
  'xplorr_principal'
])
param trustMode string = 'customer_principal'

@description('customer_principal only. Display name of the write app registration. Not the read-only app\'s name.')
param displayName string = 'xplorr-write'

@description('customer_principal only. Immutable key the Graph extension uses to find the write app registration again on a redeploy.')
param appUniqueName string = 'xplorr-write'

@description('xplorr_principal only, and required there. Application (client) ID of Xplorr\'s separate write app, which Xplorr shows you when you turn on write access. Not the read-only app\'s ID.')
param xplorrWriteApplicationId string = ''

@description('Optional. Object ID of an existing service principal to hold the write role, created for write access only (never the read-only principal). When set, no Graph resources are deployed.')
param existingPrincipalObjectId string = ''

@description('With existingPrincipalObjectId and customer_principal. Its application (client) ID, so the outputs are complete.')
param existingClientId string = ''

@description('Action types the custom role may carry out. deallocate_idle_vm grants Microsoft.Compute/virtualMachines/deallocate/action, and start/action to undo it.')
@allowed([
  'deallocate_idle_vm'
])
@minLength(1)
param actions array

@description('Name of the custom role. It must be unique in the tenant.')
param roleName string = 'xplorr-write'

@description('Optional. Resource group names in this subscription to assign the role on. Empty assigns it on the whole subscription.')
param resourceGroupNames array = []

var permissionsByAction = {
  deallocate_idle_vm: [
    'Microsoft.Compute/virtualMachines/deallocate/action'
    'Microsoft.Compute/virtualMachines/start/action'
  ]
}

var roleActions = union(flatten(map(actions, a => permissionsByAction[a])), [])

var customerMode = trustMode == 'customer_principal'
var useExisting = !empty(existingPrincipalObjectId)

// Fail fast on inputs that cannot work, before anything is created.
var xplorrAppIdChecked = (!customerMode && empty(xplorrWriteApplicationId)) ? fail('xplorrWriteApplicationId is required when trustMode is xplorr_principal.') : xplorrWriteApplicationId
var existingClientIdChecked = (useExisting && customerMode && empty(existingClientId)) ? fail('existingClientId is required when existingPrincipalObjectId is set.') : existingClientId

resource app 'Microsoft.Graph/applications@v1.0' = if (customerMode && !useExisting) {
  uniqueName: appUniqueName
  displayName: displayName
  signInAudience: 'AzureADMyOrg'
  notes: 'Opt-in write access for Xplorr approved actions, separate from the read-only app. Created by https://github.com/Xplorrio/cloud-onboarding'
}

resource customerSp 'Microsoft.Graph/servicePrincipals@v1.0' = if (customerMode && !useExisting) {
  appId: app!.appId
}

// Xplorr's separate write app. It carries no Graph permissions; the custom
// role below is all the access it gets.
resource xplorrSp 'Microsoft.Graph/servicePrincipals@v1.0' = if (!customerMode && !useExisting) {
  appId: xplorrAppIdChecked
}

var principalId = useExisting ? existingPrincipalObjectId : (customerMode ? customerSp!.id : xplorrSp!.id)
var clientId = useExisting ? (customerMode ? existingClientIdChecked : xplorrAppIdChecked) : (customerMode ? app!.appId : xplorrAppIdChecked)

resource writeRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' = {
  name: guid(subscription().id, roleName)
  properties: {
    roleName: roleName
    description: 'Opt-in write access for Xplorr approved actions: ${join(actions, ', ')}. Created by https://github.com/Xplorrio/cloud-onboarding'
    type: 'CustomRole'
    assignableScopes: [
      subscription().id
    ]
    permissions: [
      {
        actions: roleActions
        notActions: []
        dataActions: []
        notDataActions: []
      }
    ]
  }
}

module subscriptionAssignment 'modules/subscription-role.bicep' = if (empty(resourceGroupNames)) {
  name: 'xplorr-write-subscription'
  params: {
    principalId: principalId
    roleDefinitionId: writeRole.id
  }
}

module resourceGroupAssignments 'modules/resource-group-role.bicep' = [
  for rg in resourceGroupNames: {
    name: 'xplorr-write-${uniqueString(rg)}'
    scope: resourceGroup(rg)
    params: {
      principalId: principalId
      roleDefinitionId: writeRole.id
    }
  }
]

@description('Directory (tenant) ID of the write identity.')
output tenantId string = tenant().tenantId

@description('Application (client) ID of the separate write identity.')
output clientId string = clientId

@description('Object ID of the write service principal, which holds the custom role.')
output servicePrincipalObjectId string = principalId

@description('The write Credentials (JSON) Xplorr asks for. Replace the placeholder with the write app\'s secret Value (customer_principal).')
output credentialsJson string = string({
  clientId: clientId
  tenantId: tenant().tenantId
  clientSecret: customerMode ? 'PASTE_THE_WRITE_CLIENT_SECRET_VALUE' : null
  subscriptionId: subscription().subscriptionId
})

@description('Resource ID of the custom role, which Xplorr asks for when you turn on write access.')
output customRoleId string = writeRole.id

@description('Name of the custom role.')
output customRoleName string = roleName

@description('Where the role is assigned.')
output scopes array = empty(resourceGroupNames) ? [subscription().id] : map(resourceGroupNames, rg => '${subscription().id}/resourceGroups/${rg}')

@description('The action types the role may carry out.')
output actionTypes array = actions

@description('Every Azure action the role allows.')
output permissions array = roleActions
