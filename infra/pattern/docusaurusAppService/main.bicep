targetScope = 'subscription'

metadata description = 'Deploys the internal Docusaurus documentation site with App Service and secretless Microsoft Entra authentication.'

extension 'br:mcr.microsoft.com/bicep/extensions/microsoftgraph/v1.0:1.0.0'

// ──────── Parameters ────────

@description('Required: Configuration for the Docusaurus App Service pattern.')
param config DocsWebAppPattern

// ──────── Resource Group ────────

module resourceGroup 'br:pebiceptemplatesprod.azurecr.io/bicep/resource/resourcegroup/rg:v1.0.1' = {
  name: '${uniqueString(deployment().name, config.location)}-resourceGroup-deployment'
  params: {
    config: {
      location: config.location
      resourceGroupName: config.resourceGroup.name
      tags: config.resourceGroup.tags
    }
  }
}

resource docsResourceGroup 'Microsoft.Resources/resourceGroups@2025-04-01' existing = {
  name: config.resourceGroup.name
  dependsOn: [
    resourceGroup
  ]
}

// ──────── Policy Exemption ────────

var enablePolicyExemption = config.?policyExemption != null

var policyAssignmentResourceId = enablePolicyExemption
  ? subscriptionResourceId(
      'Microsoft.Authorization/policyAssignments',
      config.policyExemption!.policyAssignmentName
    )
  : ''

module publicNetworkAccessPolicyExemption 'policy-exemption.bicep' = if (enablePolicyExemption) {
  name: '${uniqueString(deployment().name, config.location)}-policyExemption-deployment'
  scope: docsResourceGroup
  params: {
    config: {
      description: config.policyExemption!.description
      displayName: config.policyExemption!.displayName
      exemptionCategory: config.policyExemption!.exemptionCategory
      name: config.policyExemption!.name
      policyAssignmentId: policyAssignmentResourceId
      policyDefinitionReferenceId: config.policyExemption!.policyDefinitionReferenceId
    }
  }
}

// ──────── App Service Plan ────────

module appServicePlan 'br:pebiceptemplatesprod.azurecr.io/bicep/resource/appserviceplan/appserviceplan:v1.0.1' = {
  name: '${uniqueString(deployment().name, config.location)}-appServicePlan-deployment'
  scope: docsResourceGroup
  params: {
    config: {
      location: config.location
      name: config.appServicePlan.name
      os: config.appServicePlan.os
      skuName: config.appServicePlan.skuName
      skuCapacity: config.appServicePlan.skuCapacity
      tags: config.appServicePlan.tags
    }
  }
}

// ──────── Easy Auth Managed Identity ────────

module authenticationIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.6.0' = {
  name: '${uniqueString(deployment().name, config.location)}-authenticationIdentity-deployment'
  scope: docsResourceGroup
  params: {
    enableTelemetry: config.enableTelemetry
    location: config.location
    name: config.authentication.managedIdentityName
    tags: config.authentication.managedIdentityTags
  }
}

// ──────── GitHub Deployment Managed Identity ────────

var githubFederatedCredentialSubject = 'repo:${config.deploymentIdentity.repository}:environment:${config.deploymentIdentity.environmentName}'

module deploymentIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.6.0' = {
  name: '${uniqueString(deployment().name, config.location)}-deploymentIdentity-deployment'
  scope: docsResourceGroup
  params: {
    enableTelemetry: config.enableTelemetry
    federatedIdentityCredentials: [
      {
        audiences: [
          config.deploymentIdentity.federatedCredentialAudience
        ]
        issuer: config.deploymentIdentity.oidcIssuer
        name: config.deploymentIdentity.federatedCredentialName
        subject: githubFederatedCredentialSubject
      }
    ]
    location: config.location
    name: config.deploymentIdentity.name
    tags: config.deploymentIdentity.tags
  }
}

// ──────── Web App Naming ────────

var webAppName = '${config.webApp.namePrefix}-${uniqueString(subscription().subscriptionId, config.resourceGroup.name)}'
var webAppUrl = 'https://${webAppName}.azurewebsites.net'
var authenticationCallbackUrl = '${webAppUrl}/.auth/login/aad/callback'

// ──────── Entra Application ────────

var authenticationFederatedCredentialIssuer = '${environment().authentication.loginEndpoint}${tenant().tenantId}/v2.0'

resource authenticationApplication 'Microsoft.Graph/applications@v1.0' = {
  uniqueName: config.authentication.applicationUniqueName
  displayName: config.authentication.applicationDisplayName
  signInAudience: config.authentication.signInAudience
  web: {
    homePageUrl: webAppUrl
    redirectUris: [
      authenticationCallbackUrl
    ]
  }

  resource managedIdentityFederatedCredential 'federatedIdentityCredentials@v1.0' = {
    name: '${authenticationApplication.uniqueName}/${config.authentication.federatedCredentialName}'
    audiences: [
      config.authentication.federatedCredentialAudience
    ]
    issuer: authenticationFederatedCredentialIssuer
    subject: authenticationIdentity.outputs.principalId
  }
}

resource authenticationServicePrincipal 'Microsoft.Graph/servicePrincipals@v1.0' = {
  appId: authenticationApplication.appId
  displayName: authenticationApplication.displayName
}

// ──────── Web App Configuration ────────

var allowedTenantIds = join(config.authentication.allowedTenantIds, ',')

var webAppSettings = union(
  config.webApp.appSettings,
  {
    '${config.authentication.managedIdentityClientIdSettingName}': authenticationIdentity.outputs.clientId
    WEBSITE_AUTH_AAD_ALLOWED_TENANTS: allowedTenantIds
  }
)

module webApp 'br/public:avm/res/web/site:0.23.1' = {
  name: '${uniqueString(deployment().name, config.location)}-webApp-deployment'
  scope: docsResourceGroup
  dependsOn: [
    publicNetworkAccessPolicyExemption
  ]
  params: {
    basicPublishingCredentialsPolicies: config.webApp.basicPublishingCredentialsPolicies
    clientAffinityEnabled: config.webApp.clientAffinityEnabled
    configs: [
      {
        name: 'appsettings'
        properties: webAppSettings
      }
      {
        name: 'authsettingsV2'
        properties: {
          globalValidation: {
            redirectToProvider: config.authentication.redirectToProvider
            requireAuthentication: config.authentication.requireAuthentication
            unauthenticatedClientAction: config.authentication.unauthenticatedClientAction
          }
          identityProviders: {
            azureActiveDirectory: {
              enabled: config.authentication.enableEasyAuth
              registration: {
                clientId: authenticationApplication.appId
                clientSecretSettingName: config.authentication.managedIdentityClientIdSettingName
                openIdIssuer: config.authentication.openIdIssuer
              }
            }
          }
          platform: {
            enabled: config.authentication.enableEasyAuth
          }
        }
      }
      {
        name: 'slotConfigNames'
        properties: {
          appSettingNames: [
            config.authentication.managedIdentityClientIdSettingName
          ]
        }
      }
    ]
    enableTelemetry: config.enableTelemetry
    kind: config.webApp.kind
    managedIdentities: {
      userAssignedResourceIds: [
        authenticationIdentity.outputs.resourceId
      ]
    }
    name: webAppName
    publicNetworkAccess: config.webApp.publicNetworkAccess
    reserved: config.webApp.reserved
    roleAssignments: [
      {
        principalId: deploymentIdentity.outputs.principalId
        principalType: 'ServicePrincipal'
        roleDefinitionIdOrName: config.deploymentIdentity.webAppRole
      }
    ]
    serverFarmResourceId: appServicePlan.outputs.resourceId
    siteConfig: {
      alwaysOn: config.webApp.siteConfig.alwaysOn
      appCommandLine: config.webApp.siteConfig.appCommandLine
      ftpsState: config.webApp.siteConfig.ftpsState
      linuxFxVersion: config.webApp.siteConfig.linuxFxVersion
      minTlsVersion: config.webApp.siteConfig.minTlsVersion
    }
    tags: config.webApp.tags
  }
}

// ──────── Outputs ────────

@description('Application client ID used by App Service Easy Auth.')
output authenticationApplicationClientId string = authenticationApplication.appId

@description('Client ID of the managed identity used by App Service Easy Auth.')
output authenticationIdentityClientId string = authenticationIdentity.outputs.clientId

@description('Client ID used by GitHub Actions to authenticate to Azure.')
output deploymentIdentityClientId string = deploymentIdentity.outputs.clientId

@description('Tenant ID containing the deployed Azure resources and managed identities.')
output deploymentTenantId string = tenant().tenantId

@description('Name of the Resource Group.')
output resourceGroupName string = resourceGroup.outputs.resourceGroupName

@description('Default hostname of the Web App.')
output webAppDefaultHostname string = webApp.outputs.defaultHostname

@description('Name of the Web App.')
output webAppName string = webApp.outputs.name

@description('Resource ID of the Web App.')
output webAppResourceId string = webApp.outputs.resourceId

@description('URL of the Web App.')
output webAppUrl string = webAppUrl

// ──────── Types ────────

type AppServicePlanConfig = {
  @description('Required: Name of the App Service Plan.')
  name: string

  @description('Required: Operating system of the App Service Plan.')
  os: 'Linux' | 'Windows'

  @description('Required: SKU of the App Service Plan.')
  skuName: 'B1' | 'B2' | 'B3' | 'S1' | 'S2' | 'S3' | 'P0v3' | 'P1v3' | 'P2v3' | 'P3v3'

  @description('Required: Number of workers associated with the App Service Plan. Defaults to 3 to preserve the existing module behavior.')
  @minValue(1)
  skuCapacity: int

  @description('Required: Resource tags.')
  tags: object
}

type AuthenticationConfig = {
  @description('Required: Entra tenant IDs allowed to authenticate to the Web App.')
  allowedTenantIds: string[]

  @description('Required: Display name of the multitenant App Registration.')
  applicationDisplayName: string

  @description('Required: Unique name of the multitenant App Registration.')
  applicationUniqueName: string

  @description('Required: Enables App Service Easy Auth.')
  enableEasyAuth: bool

  @description('Required: Audience used by the managed identity federated credential.')
  federatedCredentialAudience: string

  @description('Required: Name of the managed identity federated credential.')
  federatedCredentialName: string

  @description('Required: App setting name used by App Service for the managed identity client assertion.')
  managedIdentityClientIdSettingName: string

  @description('Required: Name of the managed identity used by App Service Easy Auth.')
  managedIdentityName: string

  @description('Required: Tags for the Easy Auth managed identity.')
  managedIdentityTags: object

  @description('Required: OpenID issuer used by App Service Easy Auth.')
  openIdIssuer: string

  @description('Required: Authentication provider used when redirecting unauthenticated users.')
  redirectToProvider: string

  @description('Required: Whether App Service requires authentication.')
  requireAuthentication: bool

  @description('Required: Sign-in audience for the Entra App Registration.')
  signInAudience: 'AzureADMultipleOrgs'

  @description('Required: Action taken when an unauthenticated request reaches the Web App.')
  unauthenticatedClientAction: 'RedirectToLoginPage' | 'Return401'
}

type BasicPublishingCredentialsPolicy = {
  @description('Required: Whether basic publishing credentials are allowed.')
  allow: bool

  @description('Required: Publishing endpoint.')
  name: 'ftp' | 'scm'
}

type DeploymentIdentityConfig = {
  @description('Required: GitHub Environment used by the deployment workflow.')
  environmentName: string

  @description('Required: Audience of the GitHub federated credential.')
  federatedCredentialAudience: string

  @description('Required: Name of the GitHub federated credential.')
  federatedCredentialName: string

  @description('Required: Name of the GitHub deployment managed identity.')
  name: string

  @description('Required: GitHub Actions OIDC issuer.')
  oidcIssuer: string

  @description('Required: GitHub repository in org/repository format.')
  repository: string

  @description('Required: Tags for the GitHub deployment identity.')
  tags: object

  @description('Required: RBAC role assigned to the deployment identity on the Web App.')
  webAppRole: 'Website Contributor'
}

type PolicyExemptionConfig = {
  @description('Required: Description of the policy exemption.')
  description: string

  @description('Required: Display name of the policy exemption.')
  displayName: string

  @description('Required: Exemption category.')
  exemptionCategory: 'Mitigated' | 'Waiver'

  @description('Required: Name of the policy exemption.')
  name: string

  @description('Required: Name of the subscription-scoped policy assignment.')
  policyAssignmentName: string

  @description('Required: Reference ID of the policy definition within the assigned initiative.')
  policyDefinitionReferenceId: string
}

type ResourceGroupConfig = {
  @description('Required: Name of the Resource Group.')
  @minLength(3)
  @maxLength(90)
  name: string

  @description('Required: Resource tags.')
  tags: object
}

type WebAppSiteConfig = {
  @description('Required: Whether the Web App should remain loaded when idle.')
  alwaysOn: bool

  @description('Required: Startup command for the Web App.')
  appCommandLine: string

  @description('Required: FTP state.')
  ftpsState: 'Disabled' | 'FtpsOnly'

  @description('Required: Linux runtime stack.')
  linuxFxVersion: string

  @description('Required: Minimum TLS version.')
  minTlsVersion: '1.2' | '1.3'
}

type WebAppConfig = {
  @description('Required: Additional Web App application settings.')
  appSettings: object

  @description('Required: Basic publishing credential policies.')
  basicPublishingCredentialsPolicies: BasicPublishingCredentialsPolicy[]

  @description('Required: Whether client affinity is enabled.')
  clientAffinityEnabled: bool

  @description('Required: Kind of Web App.')
  kind: 'app,linux'

  @description('Required: Prefix used to construct the globally unique Web App name.')
  @maxLength(46)
  namePrefix: string

  @description('Required: Whether public network access is enabled.')
  publicNetworkAccess: 'Enabled' | 'Disabled'

  @description('Required: Whether this is a Linux Web App.')
  reserved: bool

  @description('Required: Web App runtime configuration.')
  siteConfig: WebAppSiteConfig

  @description('Required: Resource tags.')
  tags: object
}

@export()
type DocsWebAppPattern = {
  @description('Required: App Service Plan configuration.')
  appServicePlan: AppServicePlanConfig

  @description('Required: Microsoft Entra and Easy Auth configuration.')
  authentication: AuthenticationConfig

  @description('Required: GitHub deployment identity configuration.')
  deploymentIdentity: DeploymentIdentityConfig

  @description('Required: Enable or disable AVM telemetry.')
  enableTelemetry: bool

  @description('Required: Azure deployment region.')
  location: 'westeurope' | 'northeurope' | 'swedencentral'

  @description('Required: Resource Group configuration.')
  resourceGroup: ResourceGroupConfig

  @description('Optional: Policy exemption configuration.')
  policyExemption: PolicyExemptionConfig?

  @description('Required: Web App configuration.')
  webApp: WebAppConfig
}
