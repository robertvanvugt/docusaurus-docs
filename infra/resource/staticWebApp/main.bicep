targetScope = 'subscription'

// ──────── Parameters ────────

@description('Required: Configuration of the Resource Group.')
param resourceGroupConfig ResourceGroupConfig

@description('Required: Configuration of the Azure Static Web App.')
param staticWebAppConfig StaticWebAppConfig

// ──────── Vars ────────

var staticWebAppName = '${staticWebAppConfig.namePrefix}-${uniqueString(subscription().id)}'

// ──────── Resource Group ────────

resource peDocsRg 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: resourceGroupConfig.name
  location: resourceGroupConfig.location
  tags: resourceGroupConfig.tags
}

// ──────── Static Web App ────────

module staticWebApp 'br/public:avm/res/web/static-site:0.9.5' = {
  name: '${uniqueString(deployment().name, staticWebAppConfig.location)}-staticWebApp-deployment'
  scope: resourceGroup(resourceGroupConfig.name)
  params: {
    location: staticWebAppConfig.location
    name: staticWebAppName
    sku: staticWebAppConfig.sku
    tags: staticWebAppConfig.tags
  }
  dependsOn: [
    peDocsRg
  ]
}

// ──────── Outputs ────────

@description('The name of the Resource Group.')
output resourceGroupName string = peDocsRg.name

@description('The resource ID of the Resource Group.')
output resourceGroupResourceId string = peDocsRg.id

@description('The default hostname of the Azure Static Web App.')
output staticWebAppDefaultHostname string = staticWebApp.outputs.defaultHostname

@description('The name of the Azure Static Web App.')
output staticWebAppName string = staticWebApp.outputs.name

@description('The resource ID of the Azure Static Web App.')
output staticWebAppResourceId string = staticWebApp.outputs.resourceId

// ──────── Types ────────

@export()
type ResourceGroupConfig = {
  @description('Required: Azure region of the Resource Group.')
  location: string

  @description('Required: Name of the Resource Group.')
  @minLength(1)
  @maxLength(90)
  name: string

  @description('Required: Resource tags.')
  tags: object
}

@export()
type StaticWebAppConfig = {
  @description('Required: Azure region of the Static Web App.')
  location: string

  @description('Required: Prefix used to construct the Azure Static Web App name.')
  @minLength(1)
  @maxLength(26)
  namePrefix: string

  @description('Required: Hosting plan of the Azure Static Web App.')
  sku: 'Free' | 'Standard'

  @description('Required: Resource tags.')
  tags: object
}
