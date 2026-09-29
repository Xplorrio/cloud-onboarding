// Assigns one role definition to a service principal on the deployment's
// resource group. Used by write-role.bicep to narrow write access to chosen
// resource groups.

targetScope = 'resourceGroup'

@description('Object ID of the service principal that gets the role.')
param principalId string

@description('Resource ID of the role definition to assign.')
param roleDefinitionId string

resource assignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, principalId, roleDefinitionId)
  properties: {
    roleDefinitionId: roleDefinitionId
    principalId: principalId
    principalType: 'ServicePrincipal'
    description: 'Xplorr approved actions (opt-in write access)'
  }
}
