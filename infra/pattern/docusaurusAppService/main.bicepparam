using 'main.bicep'

param config = {
  appServicePlan: {
    name: 'pe-docs-app-service-plan-dev'
    os: 'Linux'
    skuName: 'B1'
    skuCapacity: 1
    tags: {
      application: 'platform-docs'
      costCenter: 'NL.W04723.060'
      environment: 'dev'
      location: 'westeurope'
      part: 'compute'
      resourceType: 'app-service-plan'
      AtosManaged: 'true'
    }
  }
  authentication: {
    allowedTenantIds: [
      '1db3a288-07b3-419c-b55d-76cda356c7e3'
    ]
    applicationDisplayName: 'Platform Engineering Documentation'
    applicationUniqueName: 'pe-docs-appservice-auth'
    enableEasyAuth: true
    federatedCredentialAudience: 'api://AzureADTokenExchange'
    federatedCredentialName: 'appservice-easyauth'
    managedIdentityClientIdSettingName: 'OVERRIDE_USE_MI_FIC_ASSERTION_CLIENTID'
    managedIdentityName: 'id-pe-docs-auth-dev'
    managedIdentityTags: {
      application: 'platform-docs'
      costCenter: 'NL.W04723.060'
      environment: 'dev'
      location: 'westeurope'
      part: 'identity'
      resourceType: 'managed-identity'
      AtosManaged: 'true'
    }
    openIdIssuer: 'https://login.microsoftonline.com/common/v2.0'
    redirectToProvider: 'azureActiveDirectory'
    requireAuthentication: true
    signInAudience: 'AzureADMultipleOrgs'
    unauthenticatedClientAction: 'RedirectToLoginPage'
  }
  deploymentIdentity: {
    environmentName: 'dev'
    federatedCredentialAudience: 'api://AzureADTokenExchange'
    federatedCredentialName: 'github-dev'
    name: 'id-pe-docs-github-dev'
    oidcIssuer: 'https://token.actions.githubusercontent.com'
    repository: 'NL-AMS-PLATFORM-ENGINEER/documentation'
    tags: {
      application: 'platform-docs'
      costCenter: 'NL.W04723.060'
      environment: 'dev'
      location: 'westeurope'
      part: 'deployment'
      resourceType: 'managed-identity'
      AtosManaged: 'true'
    }
    webAppRole: 'Website Contributor'
  }
  enableTelemetry: false
  location: 'westeurope'
  policyExemption: {
    description: 'Allows the internal documentation Web App to expose its public endpoint. Application access is protected by Microsoft Entra Easy Auth and tenant restrictions.'
    displayName: 'Platform documentation public App Service endpoint'
    exemptionCategory: 'Waiver'
    name: 'pe-docs-public-network-access'
    policyAssignmentName: 'lz01-d-appservice-change-policy-set-assignment'
    policyDefinitionReferenceId: '8739958994701639919'
  }
  resourceGroup: {
    name: 'rg-platform-docs-dev'
    tags: {
      application: 'platform-docs'
      costCenter: 'NL.W04723.060'
      environment: 'dev'
      location: 'westeurope'
      part: 'infrastructure'
      resourceType: 'resource-group'
      AtosManaged: 'true'
    }
  }
  webApp: {
    appSettings: {
      SCM_DO_BUILD_DURING_DEPLOYMENT: 'false'
    }
    basicPublishingCredentialsPolicies: [
      {
        allow: false
        name: 'ftp'
      }
      {
        allow: false
        name: 'scm'
      }
    ]
    clientAffinityEnabled: false
    kind: 'app,linux'
    namePrefix: 'pe-docs-webapp'
    publicNetworkAccess: 'Enabled'
    reserved: true
    siteConfig: {
      alwaysOn: true
      appCommandLine: 'pm2 serve /home/site/wwwroot 8080 --spa --no-daemon'
      ftpsState: 'Disabled'
      linuxFxVersion: 'NODE|24-lts'
      minTlsVersion: '1.2'
    }
    tags: {
      application: 'platform-docs'
      costCenter: 'NL.W04723.060'
      environment: 'dev'
      location: 'westeurope'
      part: 'frontend'
      resourceType: 'web-app'
      AtosManaged: 'true'
    }
  }
}
