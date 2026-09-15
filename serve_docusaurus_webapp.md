# Docusaurus on Azure App Service with Secretless Cross-Tenant Entra Authentication

## 1. Target architecture

This guide replaces the previous Azure Static Web Apps approach.

The new architecture is:

```text
GitHub Enterprise
Internal Docusaurus repository
        │
        │ GitHub Actions
        │ OIDC
        ▼
Deployment UAMI
        │
        │ Website Contributor
        ▼
DEV Azure tenant
┌─────────────────────────────────────────────────────┐
│ DEV subscription                                    │
│                                                     │
│ Resource Group                                      │
│ ├── App Service Plan                                │
│ ├── Easy Auth UAMI                                  │
│ ├── GitHub Deployment UAMI                          │
│ └── Linux Web App                                   │
│     ├── Docusaurus static content                   │
│     └── Easy Auth                                   │
│                                                     │
│ Multitenant Entra App Registration                  │
│ └── FIC trusts Easy Auth UAMI                       │
└────────────────────────┬────────────────────────────┘
                         │
                         │ OIDC
                         ▼
                   DEV2 Entra tenant
                   ┌───────────────┐
                   │ DEV2 users    │
                   │ MFA / CA      │
                   └───────────────┘
```

There are **two different user-assigned managed identities**:

```text
Easy Auth UAMI
    │
    └── Used by App Service Authentication
        to authenticate as the Entra application
        through a federated identity credential.

GitHub Deployment UAMI
    │
    └── Used by GitHub Actions through OIDC
        to deploy Docusaurus to the Web App.
```

Keeping these identities separate limits each identity to one purpose.

The result contains **no client secret, publish-profile secret, certificate or GitHub deployment token**.

Microsoft explicitly supports the Easy Auth pattern where a Web App uses a UAMI plus a federated identity credential (FIC) instead of a client secret. The required App Service setting is `OVERRIDE_USE_MI_FIC_ASSERTION_CLIENTID`.

## 2. Module selection

Based on the internal modules provided, use:

| Resource               | Implementation                  |
| ---------------------- | ------------------------------- |
| Resource Group         | Internal registry               |
| App Service Plan       | Internal registry               |
| Easy Auth UAMI         | AVM                             |
| GitHub Deployment UAMI | AVM                             |
| Web App                | AVM                             |
| Entra App Registration | Microsoft Graph Bicep extension |
| Easy Auth FIC          | Microsoft Graph Bicep extension |
| GitHub FIC             | UAMI AVM                        |
| Web App RBAC           | Web App AVM                     |

### Internal Resource Group module

The internal Resource Group module supports subscription scope, tags and the current resource-group API.

We will use the same registry module already used by the Foundry pattern:

```text
br:pebiceptemplatesprod.azurecr.io/bicep/resource/resourcegroup/rg:v1.0.1
```

The Foundry pattern also demonstrates the preferred structure:

```text
subscription pattern
    │
    ├── private Resource Group module
    │
    ├── existing RG reference
    │
    └── resource-scoped modules
```

### Internal App Service Plan module

The internal App Service Plan module already wraps the AVM serverfarm module and supports:

* Linux.
* SKU selection.
* Location.
* Tags.
* Resource ID output.

It therefore meets our requirements and should be preferred over calling the serverfarm AVM directly.

### Internal Entra application module

We will **not** use the existing `entraidapplication` module for this solution.

It already supports:

* App Registration creation.
* Service Principal creation.
* Federated Identity Credentials.
* Graph Bicep.

However, its current application resource only supplies:

```bicep
uniqueName
displayName
```

and its contract does not expose:

```text
signInAudience
web.redirectUris
web.homePageUrl
```

Those properties are required for our multitenant Easy Auth application.

Rather than create another local wrapper, we will use the **Microsoft Graph Bicep extension directly**, using the same Graph resource model your internal module already uses.

This is also a useful future enhancement for `entraidapplication.bicep`: adding generic `signInAudience` and Web redirect configuration would allow this solution to use the internal module later.

### AVM versions

Use:

```text
br/public:avm/res/managed-identity/user-assigned-identity:0.6.0

br/public:avm/res/web/site:0.23.1
```

At the time of this guide, `0.6.0` is the latest UAMI AVM release and `0.23.1` is the latest Web Site AVM release.

The UAMI module exposes `clientId`, `principalId` and `resourceId`, and supports federated identity credentials directly.

The Web Site AVM supports Linux Web Apps, UAMIs, configuration resources, basic publishing credential policies and Web App scoped role assignments.

## 3. Cleanup and reuse from the previous SWA approach

You ended the previous guide at Step 13.

### Keep for now

Keep:

* The DEV tenant.
* The DEV subscription.
* The DEV2 tenant.
* Your existing Docusaurus repository.
* Any Docusaurus `url` / `baseUrl` environment-variable changes if you already made them.
* The existing Resource Group if you want to reuse its name.

Also keep the Static Web App temporarily if it already exists. It gives us a fallback while the new implementation is being validated.

### Do not reuse the old App Registration

I recommend creating a **new App Registration through Bicep** rather than adopting the previous manually-created SWA App Registration.

The new application will be:

```text
pe-docs-appservice-auth
```

and will be completely secretless from the start.

The old App Registration probably contains:

```text
SWA callback URI
possibly a client secret
DEV2 consent
```

Trying to adopt that manually created object into the new IaC design provides little value.

### Clean up after the App Service version works

After the new solution has been validated:

1. Delete the old Static Web App.
2. Delete the old SWA App Registration from DEV.
3. Delete its corresponding Enterprise Application from DEV2.
4. Remove its client secret if the App Registration is temporarily retained.
5. Remove any `AZURE_STATIC_WEB_APPS_API_TOKEN` GitHub secret if you created one.
6. Remove `static/staticwebapp.config.json` if it exists.
7. Remove the old SWA deployment workflow.
8. Replace the old SWA-oriented `infra/main.bicep` and `main.bicepparam` with the files from this guide.

Do the cleanup **after** the new site has passed the end-to-end tests.

## 4. Resolve the internal App Service Plan module version

The uploaded `appserviceplan.bicep` did not include its accompanying `appserviceplan.version.txt`, so we should not guess the registry version.

From the internal module repository, check:

```text
modules/resource/appserviceplan/appserviceplan.version.txt
```

Alternatively:

```powershell
az acr repository show-tags `
    --name pebiceptemplatesprod `
    --repository bicep/resource/appserviceplan/appserviceplan `
    --orderby time_desc `
    --output table
```

Pick the latest approved version and pin it explicitly.

In the Bicep below I use:

```text
<APP_SERVICE_PLAN_MODULE_VERSION>
```

Replace that once before building the template.

## 5. Repository structure

The relevant repository structure will become:

```text
repository/
│
├── .github/
│   └── workflows/
│       └── deploy-docs-appservice.yml
│
├── infra/
│   ├── main.bicep
│   └── main.bicepparam
│
├── docs/
├── src/
├── static/
├── docusaurus.config.ts
├── package.json
└── ...
```

We no longer need:

```text
static/staticwebapp.config.json
```

because Easy Auth is configured on the App Service resource rather than through an application file.

## 6. Create `infra/main.bicep`

Use:

```bicep
targetScope = 'subscription'

metadata description = 'Deploys the internal Docusaurus documentation site with App Service and secretless Microsoft Entra authentication.'

extension microsoftGraphV1_0

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

// ──────── App Service Plan ────────

module appServicePlan 'br:pebiceptemplatesprod.azurecr.io/bicep/resource/appserviceplan/appserviceplan:<APP_SERVICE_PLAN_MODULE_VERSION>' = {
  name: '${uniqueString(deployment().name, config.location)}-appServicePlan-deployment'
  scope: docsResourceGroup
  params: {
    config: {
      location: config.location
      name: config.appServicePlan.name
      os: config.appServicePlan.os
      skuName: config.appServicePlan.skuName
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

  @description('Required: Web App configuration.')
  webApp: WebAppConfig
}
```

### Why the Web App name is generated in `main.bicep`

Do not use:

```bicep
uniqueString(subscription().id)
```

inside `main.bicepparam`.

We already established that deployment-context functions such as `subscription()` are unavailable there.

Instead:

```bicep
var webAppName = '${config.webApp.namePrefix}-${uniqueString(subscription().subscriptionId, config.resourceGroup.name)}'
```

creates a deterministic globally unique name inside the subscription deployment.

## 7. Create `infra/main.bicepparam`

Use:

```bicep
using 'main.bicep'

param config = {
  appServicePlan: {
    name: 'pe-docs-plan-dev'
    os: 'Linux'
    skuName: 'B1'
    tags: {
      application: 'platform-docs'
      costCenter: '<cost-center>'
      environment: 'dev'
      location: 'westeurope'
      part: 'compute'
      resourceType: 'app-service-plan'
    }
  }
  authentication: {
    allowedTenantIds: [
      '<DEV2-TENANT-ID>'
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
      costCenter: '<cost-center>'
      environment: 'dev'
      location: 'westeurope'
      part: 'identity'
      resourceType: 'managed-identity'
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
    repository: '<GITHUB-ORG>/<GITHUB-REPOSITORY>'
    tags: {
      application: 'platform-docs'
      costCenter: '<cost-center>'
      environment: 'dev'
      location: 'westeurope'
      part: 'deployment'
      resourceType: 'managed-identity'
    }
    webAppRole: 'Website Contributor'
  }
  enableTelemetry: false
  location: 'westeurope'
  resourceGroup: {
    name: 'rg-platform-docs-dev'
    tags: {
      application: 'platform-docs'
      costCenter: '<cost-center>'
      environment: 'dev'
      location: 'westeurope'
      part: 'infrastructure'
      resourceType: 'resource-group'
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
      costCenter: '<cost-center>'
      environment: 'dev'
      location: 'westeurope'
      part: 'frontend'
      resourceType: 'web-app'
    }
  }
}
```

Replace:

```text
<cost-center>
<DEV2-TENANT-ID>
<GITHUB-ORG>
<GITHUB-REPOSITORY>
```

before deployment.

### App Service Plan SKU

`B1` is sufficient for the initial internal documentation workload.

If you later require deployment slots or additional production capabilities, moving to `S1` is straightforward.

### Node runtime

The Web App uses:

```text
NODE|24-lts
```

and serves the prebuilt Docusaurus files from:

```text
/home/site/wwwroot
```

App Service supports explicit Node startup commands and includes PM2 in its Linux Node environment.

## 8. Understand the two federation relationships

There are two separate federation flows.

### Easy Auth federation

```text
App Service
   │
   └── Easy Auth UAMI
            │
            │ UAMI assertion
            ▼
       FIC on App Registration
            │
            ▼
       Entra App Registration
```

The FIC uses:

```text
issuer:
https://login.microsoftonline.com/<DEV-TENANT-ID>/v2.0

subject:
<EASY-AUTH-UAMI-PRINCIPAL-ID>

audience:
api://AzureADTokenExchange
```

The Web App setting:

```text
OVERRIDE_USE_MI_FIC_ASSERTION_CLIENTID
```

contains the **UAMI client ID**, not the Entra application client ID.

Microsoft explicitly requires this configuration for secretless App Service authentication.

### GitHub federation

```text
GitHub Actions
      │
      │ GitHub OIDC token
      ▼
GitHub Deployment UAMI
      │
      │ Website Contributor
      ▼
Web App
```

The GitHub FIC has:

```text
issuer:
https://token.actions.githubusercontent.com

subject:
repo:<ORG>/<REPO>:environment:dev

audience:
api://AzureADTokenExchange
```

Microsoft recommends OIDC/user-assigned identity authentication over basic App Service publishing credentials for GitHub Actions.

## 9. Why the Easy Auth UAMI is separate

Do not assign `id-pe-docs-auth-dev` to other resources.

Microsoft specifically recommends that the UAMI used for Easy Auth client assertion should only be assigned to the App Service application using that registration.

That means:

```text
id-pe-docs-auth-dev
└── assigned only to pe-docs-webapp-...
```

The GitHub deployment identity remains a separate resource and is **not** attached to the Web App.

## 10. Why we use `common` plus an allowed-tenant list

The App Registration is multitenant:

```text
AzureADMultipleOrgs
```

and Easy Auth uses:

```text
https://login.microsoftonline.com/common/v2.0
```

We then explicitly restrict accepted tokens through:

```text
WEBSITE_AUTH_AAD_ALLOWED_TENANTS
```

For the PoC:

```text
WEBSITE_AUTH_AAD_ALLOWED_TENANTS=<DEV2-TENANT-ID>
```

App Service evaluates the token's `tid` claim against this setting and returns `403` when the tenant is not allowed. Microsoft supports up to ten tenant IDs in the setting.

This gives us:

```text
DEV2 identity        ✅
DEV identity         ❌
Random Entra tenant  ❌
Anonymous            ❌
```

Later we can allow both DEV2 and the corporate tenant simply by changing:

```bicep
allowedTenantIds: [
  '<DEV2-TENANT-ID>'
  '<CORPORATE-TENANT-ID>'
]
```

No new application architecture is required.

## 11. Verify Graph Bicep support

Your internal Entra module already uses:

```bicep
extension microsoftGraphV1_0
```

so your Bicep repository/environment likely already supports this extension.

Before deploying:

```powershell
az bicep version
```

If necessary:

```powershell
az bicep upgrade
```

Then:

```powershell
az bicep build `
    --file .\infra\pattern\docusaurusAppService\main.bicep
```

If `microsoftGraphV1_0` cannot be resolved, check the existing `bicepconfig.json` used by the repository containing your internal Entra module and reuse its extension configuration.

I would only fall back to PowerShell for the App Registration/FIC if your environment prevents Graph Bicep from being used.

## 12. Log into the DEV tenant

```powershell
az login `
    --tenant "<DEV-TENANT-ID>"
```

Select the subscription:

```powershell
az account set `
    --subscription "<DEV-SUBSCRIPTION-ID>"
```

Verify:

```powershell
az account show `
    --query "{subscription:name, subscriptionId:id, tenantId:tenantId}" `
    --output table
```

Make sure the tenant ID shown is the **DEV tenant**.

## 13. Restore and build the Bicep

Restore the private and public modules:

```powershell
az bicep restore `
    --file .\infra\pattern\docusaurusAppService\main.bicep
```

Build:

```powershell
az bicep build `
    --file .\infra\pattern\docusaurusAppService\main.bicep
```

Resolve compiler and linter findings before continuing.

## 14. Run subscription-level `what-if`

```powershell
$deploymentLocation = "westeurope"
```

Then:

```powershell
az deployment sub what-if `
    --name "platform-docs-awa-dev-what-if" `
    --location $deploymentLocation `
    --template-file .\infra\pattern\docusaurusAppService\main.bicep `
    --parameters .\infra\pattern\docusaurusAppService\main.bicepparam
```

Expect resources similar to:

```text
DEV subscription
│
└── rg-platform-docs-dev
    │
    ├── pe-docs-plan-dev
    │
    ├── id-pe-docs-auth-dev
    │
    ├── id-pe-docs-github-dev
    │
    └── pe-docs-webapp-xxxxxxxxxxxxx

DEV Entra
│
└── Platform Engineering Documentation
    ├── Service Principal
    └── Federated Identity Credential
```

## 15. Deploy the infrastructure

Run:

```powershell
az deployment sub create `
    --name "platform-docs-deployment" `
    --location $deploymentLocation `
    --template-file .\infra\pattern\docusaurusAppService\main.bicep `
    --parameters .\infra\pattern\docusaurusAppService\main.bicepparam
```

The deployment identity executing this template must have sufficient Entra permissions to create:

```text
Microsoft.Graph/applications
Microsoft.Graph/servicePrincipals
Microsoft.Graph/applications/federatedIdentityCredentials
```

If your DEV account owns the tenant or has suitable application-management permissions, this should be available.

## 16. Capture the deployment outputs

```powershell
$deployment = az deployment sub show `
    --name "platform-docs-deployment" `
    | ConvertFrom-Json
```

Capture:

```powershell
$authenticationApplicationClientId = `
    $deployment.properties.outputs.authenticationApplicationClientId.value

$deploymentIdentityClientId = `
    $deployment.properties.outputs.deploymentIdentityClientId.value

$deploymentTenantId = `
    $deployment.properties.outputs.deploymentTenantId.value

$webAppName = `
    $deployment.properties.outputs.webAppName.value

$webAppUrl = `
    $deployment.properties.outputs.webAppUrl.value
```

Display:

```powershell
$authenticationApplicationClientId
$deploymentIdentityClientId
$deploymentTenantId
$webAppName
$webAppUrl
```

## 17. Verify the DEV-side Entra configuration

In the DEV tenant:

**Entra ID → App registrations → Platform Engineering Documentation**

Verify:

```text
Supported account types:
Accounts in any organizational directory
```

The application should have:

```text
Web redirect URI:
https://<WEB-APP>.azurewebsites.net/.auth/login/aad/callback
```

Under:

**Certificates & secrets → Federated credentials**

verify:

```text
appservice-easyauth
```

There should be **no client secret**.

Also verify the Web App:

**Identity → User assigned**

contains:

```text
id-pe-docs-auth-dev
```

## 18. Grant DEV2 access

At this point DEV2 does not yet have an Enterprise Application representing our multitenant application.

Open:

```text
https://<WEB-APP>.azurewebsites.net
```

in an InPrivate browser.

Authenticate using your **DEV2 administrator account**.

Because this is a new unverified multitenant application, DEV2 may require administrator approval.

Grant consent on behalf of the DEV2 organization when prompted.

The result should create:

```text
DEV2 Entra tenant
└── Enterprise Applications
    └── Platform Engineering Documentation
```

This is intentionally the same boundary that corporate IAM will later approve.

### Troubleshooting

If you cannot access the Web App using the DEV2 account, ensure that no policies are blocking access, such as conditional access policies or network restrictions.

See whether the Web App is running and has public network access using the following command:

```powershell
az webapp show `
    --resource-group "rg-platform-docs-dev" `
    --name "pe-docs-webapp-hfnpizw5aao4w" `
    --query "{state:state,publicNetworkAccess:publicNetworkAccess}" `
    --output json
```

If not enabled there might be a policy that sets public network access to Disabled, for example, the assignment of a built-in policy named "Configure App Service apps to disable public network access" with a Modify effect. That is exactly capable of changing your requested Enabled value to Disabled during deployment.

Get the resource id:

```powershell
$webAppResourceId = az webapp show `
    --resource-group "rg-platform-docs-dev" `
    --name "pe-docs-webapp-hfnpizw5aao4w" `
    --query id `
    --output tsv
```

```powershell
az policy state list `
    --resource $webAppResourceId `
    --query "[].{Assignment:policyAssignmentName,Definition:policyDefinitionName,Compliance:complianceState}" `
    --output table
```

```powershell
$policyStates = az policy state list `
    --resource $webAppResourceId `
    --output json `
    | ConvertFrom-Json

$matchingPolicy = $policyStates |
    Where-Object {
        $_.policyDefinitionName -eq 'appservice-disablepublicnetworkaccess-change-policy-def'
    }

$matchingPolicy |
    Select-Object `
        policyAssignmentId,
        policyAssignmentName,
        policyDefinitionName,
        policyDefinitionReferenceId,
        complianceState
```

## 19. Verify the DEV2 Enterprise Application

Switch to DEV2:

**Entra ID → Enterprise applications → Platform Engineering Documentation**

Verify:

```text
Enabled for users to sign in:
Yes
```

and:

```text
Assignment required:
No
```

We want all DEV2 users to be eligible without individual assignment.

## 20. Test DEV2 authentication before deploying Docusaurus

The Web App currently has no useful site content, but Easy Auth can already be tested.

Browse:

```text
https://<WEB-APP>.azurewebsites.net/.auth/me
```

while authenticated using DEV2.

You should receive authenticated principal information.

Then try using an account from DEV rather than DEV2.

Because:

```text
WEBSITE_AUTH_AAD_ALLOWED_TENANTS=<DEV2-TENANT-ID>
```

the DEV identity should not be allowed to access the application.

Unauthorized tenant checks performed by App Service return `403 Forbidden`.

## 21. Create the GitHub Environment

In GitHub:

**Repository → Settings → Environments → New environment**

Create:

```text
dev
```

This name must exactly match:

```bicep
environmentName: 'dev'
```

because the federated identity subject is:

```text
repo:<ORG>/<REPO>:environment:dev
```

## 22. Add GitHub environment variables

Under the `dev` GitHub Environment, create variables:

```text
AZURE_CLIENT_ID
AZURE_SUBSCRIPTION_ID
AZURE_TENANT_ID
AZURE_WEBAPP_NAME
```

Values:

```text
AZURE_CLIENT_ID
= deploymentIdentityClientId

AZURE_SUBSCRIPTION_ID
= <DEV-SUBSCRIPTION-ID>

AZURE_TENANT_ID
= deploymentTenantId

AZURE_WEBAPP_NAME
= webAppName
```

These are identifiers, not credentials.

There are **no GitHub secrets required for Azure deployment**.

## 23. Update Docusaurus hosting configuration

Your current GitHub Pages configuration may resemble:

```typescript
url: 'https://<org>.github.io',
baseUrl: '/<repository>/',
```

App Service hosts Docusaurus at:

```text
https://<WEB-APP>.azurewebsites.net/
```

so the App Service build needs:

```text
baseUrl = /
```

Keep both hosting methods working during migration by making the configuration environment-driven.

For example:

```typescript
const config: Config = {
  url:
    process.env.DOCS_URL ??
    'https://<org>.github.io',

  baseUrl:
    process.env.DOCS_BASE_URL ??
    '/<repository>/',

  // Existing configuration continues here.
}
```

Do not otherwise modify the existing Docusaurus configuration.

## 24. Test the Docusaurus build locally

Set the App Service values:

```powershell
$env:DOCS_URL = $webAppUrl
$env:DOCS_BASE_URL = "/"
```

Build:

```powershell
npm ci
npm run build
```

The generated static site should appear under:

```text
build\
```

Optionally test locally using the Docusaurus tooling before deployment.

Afterwards:

```powershell
Remove-Item Env:DOCS_URL
Remove-Item Env:DOCS_BASE_URL
```

## 25. Create the GitHub Actions workflow

Create:

```text
.github/workflows/deploy-docs-appservice.yml
```

Use:

```yaml
name: Deploy Docusaurus to Azure App Service

on:
  push:
    branches:
      - main
  workflow_dispatch:

permissions:
  contents: read
  id-token: write

jobs:
  build-and-deploy:
    environment: dev
    runs-on: ubuntu-latest

    env:
      DOCS_BASE_URL: /
      DOCS_URL: https://${{ vars.AZURE_WEBAPP_NAME }}.azurewebsites.net

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up Node.js
        uses: actions/setup-node@v4
        with:
          node-version: 24
          cache: npm

      - name: Install dependencies
        run: npm ci

      - name: Build Docusaurus
        run: npm run build

      - name: Package Docusaurus
        run: |
          cd build
          zip -r ../site.zip .

      - name: Login to Azure
        uses: azure/login@v2
        with:
          client-id: ${{ vars.AZURE_CLIENT_ID }}
          subscription-id: ${{ vars.AZURE_SUBSCRIPTION_ID }}
          tenant-id: ${{ vars.AZURE_TENANT_ID }}

      - name: Deploy Docusaurus
        uses: azure/webapps-deploy@v3
        with:
          app-name: ${{ vars.AZURE_WEBAPP_NAME }}
          package: site.zip
```

Microsoft recommends OIDC for GitHub Actions → App Service authentication, and `azure/webapps-deploy@v3` supports deploying the already-compiled `build/` output.

We package the **contents** of `build/`, not the directory itself.

App Service ZIP deployment expands the archive into:

```text
/home/site/wwwroot
```

on Linux.

That matches our startup command:

```text
pm2 serve /home/site/wwwroot 8080 --spa --no-daemon
```

## 26. Why basic publishing credentials are disabled

The Bicep explicitly deploys:

```bicep
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
```

We do not need:

```text
FTP credentials
SCM username/password
Publish profile
AZURE_WEBAPP_PUBLISH_PROFILE
```

GitHub authenticates using:

```text
GitHub OIDC
    ↓
Deployment UAMI
    ↓
Azure RBAC
    ↓
Web App
```

Microsoft identifies user-assigned identity/OIDC as the recommended App Service GitHub deployment authentication when basic authentication is disabled.

## 27. Run the first deployment

Commit:

```text
infra/main.bicep
infra/main.bicepparam
docusaurus.config.ts
.github/workflows/deploy-docs-appservice.yml
```

Push to:

```text
main
```

Open:

**GitHub → Actions → Deploy Docusaurus to Azure App Service**

Expected sequence:

```text
Checkout
   │
   ▼
npm ci
   │
   ▼
npm run build
   │
   ▼
ZIP build output
   │
   ▼
GitHub OIDC
   │
   ▼
Deployment UAMI
   │
   ▼
Azure Web App
```

No long-lived deployment credential is involved.

## 28. Test anonymous access

Open an InPrivate browser:

```text
https://<WEB-APP>.azurewebsites.net
```

Expected:

```text
Anonymous user
      │
      ▼
App Service Easy Auth
      │
      ▼
Microsoft Entra login
```

You should never see Docusaurus without first authenticating.

## 29. Test a DEV2 employee account

Authenticate using a normal DEV2 user rather than the administrator used for consent.

Expected:

```text
DEV2 user
   │
   ▼
DEV2 Entra
   │
   ▼
Multitenant App Registration
   │
   ▼
Easy Auth
   │
   ▼
Docusaurus
```

No GitHub identity is involved.

## 30. Inspect the authenticated principal

While authenticated:

```text
https://<WEB-APP>.azurewebsites.net/.auth/me
```

You should see the Easy Auth client principal.

This is useful for validating:

```text
identity provider
tenant
user identity
claims
```

before declaring the implementation complete.

## 31. Test the tenant boundary

Open another InPrivate session.

Attempt to authenticate using an account from the DEV tenant instead of DEV2.

The flow may authenticate at Microsoft because we use the multitenant `/common` issuer, but App Service should reject the resulting token because its `tid` is not present in:

```text
WEBSITE_AUTH_AAD_ALLOWED_TENANTS
```

Expected result:

```text
DEV2        ✅
DEV         ❌
Other tenant ❌
```

App Service performs this tenant check against the token's `tid` claim.

## 32. Test direct/deep links

Open a documentation URL directly while logged out, for example:

```text
https://<WEB-APP>.azurewebsites.net/docs/platform-engineering/overview
```

Expected:

```text
Deep link
   │
   ▼
Easy Auth
   │
   ▼
Login
   │
   ▼
Original documentation URL
```

Also test:

* Images.
* Search.
* Static files.
* Internal navigation.
* Browser refresh on nested routes.
* Mobile browser.
* Logout/login.

The `--spa` option in the static server provides a fallback for client-side routes.

## 33. Test logout

Use:

```text
https://<WEB-APP>.azurewebsites.net/.auth/logout
```

Then revisit the site.

Easy Auth should require authentication again.

## 34. Verify there are no secrets

At this point verify all four areas.

### App Registration

Should contain:

```text
Federated credential ✅
Client secret         ❌
Certificate           ❌
```

### Web App

Should contain:

```text
OVERRIDE_USE_MI_FIC_ASSERTION_CLIENTID
```

but this value is merely the UAMI client ID.

It should **not** contain an application secret.

### GitHub

Should contain only variables:

```text
AZURE_CLIENT_ID
AZURE_SUBSCRIPTION_ID
AZURE_TENANT_ID
AZURE_WEBAPP_NAME
```

No Azure credential secret is necessary.

### App Service publishing

Should show:

```text
FTP basic authentication = Disabled
SCM basic authentication = Disabled
```

## 35. Keep GitHub Pages temporarily

For a short migration period:

```text
Existing consumers
       │
       ▼
GitHub Pages


Test consumers
       │
       ▼
Azure App Service
       │
       ▼
Entra
```

Validate the App Service version before redirecting users.

The major tests are:

```text
Authentication
Tenant restriction
Deep links
Search
Images
Downloads
Navigation
Page refresh
GitHub deployment
Logout
```

## 36. Move from DEV2 to the corporate tenant

Once the DEV → DEV2 architecture works, the corporate change is small.

The App Registration remains:

```text
DEV tenant
└── Platform Engineering Documentation
```

and remains multitenant.

Corporate IAM grants the same application access in the corporate tenant.

This creates:

```text
Corporate Entra tenant
└── Enterprise Application
    └── Platform Engineering Documentation
```

No employees need to be represented as B2B guests in DEV.

Then update:

```bicep
allowedTenantIds: [
  '<CORPORATE-TENANT-ID>'
]
```

or during migration:

```bicep
allowedTenantIds: [
  '<CORPORATE-TENANT-ID>'
  '<DEV2-TENANT-ID>'
]
```

Redeploy Bicep.

No change is required to:

```text
App Registration client ID
Easy Auth UAMI
FIC
Web App
App Service Plan
Docusaurus
GitHub workflow
GitHub deployment identity
```

This is a major advantage over the previous SWA tenant-specific issuer model.

## 37. Retire the old Static Web Apps solution

Only after the App Service implementation has passed all tests:

### Delete the old SWA

For example:

```powershell
az staticwebapp delete `
    --name "<OLD-SWA-NAME>" `
    --resource-group "<RESOURCE-GROUP>" `
    --yes
```

If the new Web App uses the same resource group, **do not delete the resource group**.

### Delete the old App Registration

In DEV:

**Entra ID → App registrations → old SWA application → Delete**

That also removes its old client secret.

### Delete the old DEV2 Enterprise Application

In DEV2:

**Entra ID → Enterprise applications → old SWA application → Delete**

Do not delete the new:

```text
Platform Engineering Documentation
```

enterprise application.

### Remove old repository configuration

Remove if present:

```text
static/staticwebapp.config.json
.github/workflows/deploy-docs-swa.yml
AZURE_STATIC_WEB_APPS_API_TOKEN
```

At this point the SWA implementation has been fully replaced.

## 38. Final architecture

The end state is:

```text
                     Documentation contributors
                              │
                              ▼
                        GitHub Enterprise
                        Internal repository
                              │
                              │ GitHub Actions OIDC
                              ▼
                     Deployment Managed Identity
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ DEV Azure tenant                                            │
│                                                             │
│ App Service Plan                                            │
│       │                                                     │
│       ▼                                                     │
│ Linux Web App                                               │
│ ├── Docusaurus                                              │
│ ├── Easy Auth                                               │
│ └── Easy Auth UAMI ── FIC ── Entra App Registration        │
│                                      │                      │
└──────────────────────────────────────┼──────────────────────┘
                                       │
                                  multitenant OIDC
                                       │
                      ┌────────────────┴─────────────────┐
                      ▼                                  ▼
                 DEV2 Entra                       Corporate Entra
                 during PoC                        production
                      │                                  │
                      ▼                                  ▼
                    users                              users
```

The separation of responsibilities is clean:

```text
GitHub access
    = documentation authors

Azure RBAC
    = deployment automation

Easy Auth UAMI + FIC
    = workload identity for authentication

Entra tenant membership
    = documentation consumers
```

This delivers the original goal: **employees open a URL, authenticate with their normal corporate Microsoft identity, and read the documentation without ever needing to know that GitHub is involved.**
