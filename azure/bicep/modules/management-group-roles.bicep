// Role assignments on the deployment's management group. A module, so the
// assignment names can be derived from the principal's object ID: inside the
// module it is a parameter, known when the module deployment starts.

targetScope = 'managementGroup'

@description('Object ID of the service principal that gets the roles.')
param principalId string

@description('Built-in role definition IDs (GUIDs) to assign.')
param roleDefinitionIds array

resource assignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for roleId in roleDefinitionIds: {
    name: guid(managementGroup().id, principalId, roleId)
    properties: {
      roleDefinitionId: tenantResourceId('Microsoft.Authorization/roleDefinitions', roleId)
      principalId: principalId
      principalType: 'ServicePrincipal'
      description: 'Xplorr read-only access'
    }
  }
]
