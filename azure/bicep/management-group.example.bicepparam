using 'management-group.bicep'

param trustMode = 'customer_principal'
param displayName = 'xplorr-reader'
param appUniqueName = 'xplorr-reader'
param roleNames = [
  'Reader'
  'Cost Management Reader'
]
param enableCarbonOptimizationReader = false
param subscriptionIds = [
  '00000000-0000-0000-0000-000000000000'
  '11111111-1111-1111-1111-111111111111'
]

// xplorr_principal (coming soon): Xplorr gives you this ID.
// param trustMode = 'xplorr_principal'
// param xplorrApplicationId = '00000000-0000-0000-0000-000000000000'
