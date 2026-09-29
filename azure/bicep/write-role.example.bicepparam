using 'write-role.bicep'

// The servicePrincipalObjectId output of main.bicep.
param principalId = '00000000-0000-0000-0000-000000000000'

// Only the listed action types are granted.
param actions = [
  'deallocate_idle_vm'
]

param roleName = 'xplorr-write'

// Empty: the whole subscription. Or narrow it to resource groups:
param resourceGroupNames = []
// param resourceGroupNames = [
//   'rg-example'
// ]
