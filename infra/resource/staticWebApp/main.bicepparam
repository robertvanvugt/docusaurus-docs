using 'main.bicep'

param resourceGroupConfig = {
  location: 'westeurope'
  name: 'plt-mgmt-p-euwe-rsg-pe-docs'
  tags: {
    application: 'pe-docs'
    costCenter: 'NL.W04723.060'
    environment: 'platform'
    location: 'westeurope'
    project: 'PE'
    AtosManaged: 'true'
  }
}

param staticWebAppConfig = {
  location: 'westeurope'
  namePrefix: 'pe-docs-webapp'
  sku: 'Standard'
  tags: {
    application: 'pe-docs'
    costCenter: 'NL.W04723.060'
    environment: 'platform'
    location: 'westeurope'
    project: 'PE'
    AtosManaged: 'true'
  }
}
