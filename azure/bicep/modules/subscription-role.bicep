// Assigns one role definition to a service principal on the deployment's
// subscription. A module, so the assignment name can be derived from the
// principal's object ID, which is a parameter here and known when the module
// deployment starts. Used by write-role.bicep.

targetScope = 'subscription'

@description('Object ID of the service principal that gets the role.')
param principalId string

@description('Resource ID of the role definition to assign.')
param roleDefinitionId string

resource assignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, principalId, roleDefinitionId)
  properties: {
    roleDefinitionId: roleDefinitionId
    principalId: principalId
    principalType: 'ServicePrincipal'
    description: 'Xplorr approved actions (opt-in write access)'
  }
}
