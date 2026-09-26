using 'main.bicep'

param trustMode = 'customer_principal'
param displayName = 'xplorr-reader'
param appUniqueName = 'xplorr-reader'
param roleNames = [
  'Reader'
  'Cost Management Reader'
]
param enableCarbonOptimizationReader = false

// xplorr_principal (coming soon): Xplorr gives you this ID.
// param trustMode = 'xplorr_principal'
// param xplorrApplicationId = '00000000-0000-0000-0000-000000000000'

// Principal created with the az CLI instead of the Graph extension:
// param existingPrincipalObjectId = '00000000-0000-0000-0000-000000000000'
// param existingClientId = '00000000-0000-0000-0000-000000000000'
