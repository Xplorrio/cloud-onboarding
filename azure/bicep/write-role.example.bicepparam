using 'write-role.bicep'

// The same trust mode as your read-only deployment. customer_principal
// creates a separate app registration, xplorr-write, for write access.
param trustMode = 'customer_principal'
param displayName = 'xplorr-write'
param appUniqueName = 'xplorr-write'

// xplorr_principal: Xplorr's separate write app, which Xplorr gives you.
// param trustMode = 'xplorr_principal'
// param xplorrWriteApplicationId = '00000000-0000-0000-0000-000000000000'

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
