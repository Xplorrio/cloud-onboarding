// Opt-in write access for Xplorr approved actions, on one subscription.
//
// Deploy at subscription scope, after main.bicep (or the Terraform module):
//   az deployment sub create --name xplorr-write --location <region> \
//     --template-file write-role.bicep --parameters write-role.example.bicepparam
//
// Creates a custom role holding only the actions of the action types you
// list, and assigns it to the same service principal as the read-only roles
// (the servicePrincipalObjectId output of main.bicep). The read-only roles
// are not changed. Xplorr uses this role only after a person in your Xplorr
// organization approves an action.
//
// Azure RBAC conditions do not cover virtual machine actions, so no tag guard
// can be set in the role. A ReadOnly resource lock blocks start and deallocate
// for everyone, Xplorr included; see the README.

targetScope = 'subscription'

@description('Object ID of the service principal that has the read-only roles (servicePrincipalObjectId output of main.bicep).')
param principalId string

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

resource subscriptionAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (empty(resourceGroupNames)) {
  name: guid(subscription().id, principalId, writeRole.id)
  properties: {
    roleDefinitionId: writeRole.id
    principalId: principalId
    principalType: 'ServicePrincipal'
    description: 'Xplorr approved actions (opt-in write access)'
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
