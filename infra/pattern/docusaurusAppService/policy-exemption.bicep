targetScope = 'resourceGroup'

// ──────── Parameters ────────

param config PolicyExemptionConfig

// ──────── Policy Exemption ────────

resource policyExemption 'Microsoft.Authorization/policyExemptions@2026-01-01-preview' = {
  name: config.name
  properties: {
    description: config.description
    displayName: config.displayName
    exemptionCategory: config.exemptionCategory
    policyAssignmentId: config.policyAssignmentId
    policyDefinitionReferenceIds: [
      config.policyDefinitionReferenceId
    ]
    resourceSelectors: [
      {
        name: 'appServiceWebAppsOnly'
        selectors: [
          {
            in: [
              'Microsoft.Web/sites'
            ]
            kind: 'resourceType'
          }
        ]
      }
    ]
  }
}

// ──────── Outputs ────────

@description('Resource ID of the policy exemption.')
output resourceId string = policyExemption.id

@description('Name of the policy exemption.')
output name string = policyExemption.name

// ──────── Types ────────

@export()
type PolicyExemptionConfig = {
  @description('Required: Description of the policy exemption.')
  description: string

  @description('Required: Display name of the policy exemption.')
  displayName: string

  @description('Required: Exemption category.')
  exemptionCategory: 'Mitigated' | 'Waiver'

  @description('Required: Name of the policy exemption.')
  name: string

  @description('Required: Full resource ID of the policy assignment.')
  policyAssignmentId: string

  @description('Required: Reference ID of the policy definition within the assigned initiative.')
  policyDefinitionReferenceId: string
}
