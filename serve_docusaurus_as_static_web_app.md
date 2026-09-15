# Docusaurus on Azure Static Web Apps with cross-tenant Entra authentication

## 1. Target architecture

We will build the following end-to-end solution:

```text
GitHub Enterprise
Internal Docusaurus repository
        │
        │ GitHub Actions
        ▼
DEV Azure tenant
┌─────────────────────────────────────┐
│ DEV subscription                    │
│                                     │
│ Resource Group                      │
│ └── Azure Static Web App            │
│     └── Standard SKU                │
│                                     │
│ Multitenant Entra App Registration  │
└─────────────────┬───────────────────┘
                  │
                  │ OIDC
                  ▼
DEV2 Entra tenant
┌─────────────────────────────────────┐
│ Enterprise Application              │
│                                     │
│ All DEV2 users                      │
│ Assignment required = No            │
└─────────────────────────────────────┘
```

The important characteristics are:

* Docusaurus remains in the existing internal GitHub repository.
* Azure infrastructure is deployed with Bicep.
* The Bicep deployment runs at subscription scope and creates its own resource group.
* Azure Static Web Apps is deployed through the AVM `avm/res/web/static-site`.
* Azure is not directly connected to the GitHub repository.
* GitHub Actions builds Docusaurus and deploys the generated static content.
* The Entra App Registration lives in DEV.
* The App Registration is multitenant.
* DEV2 represents the future corporate tenant.
* DEV2 users authenticate against their existing DEV2 accounts.
* No DEV2 users need to exist as B2B guests in DEV.
* Anonymous users cannot read the documentation.

We will use AVM directly rather than introducing a pass-through local module. This matches the style-guide preference for direct module references where the AVM already provides the required capability.

For this work, we are explicitly disregarding only the style-guide rule requiring AVM to use the latest ARM API version. All other relevant conventions remain applicable.

## 2. Repository structure

We will ultimately add the following files to the existing Docusaurus repository:

```text
repository/
│
├── .github/
│   └── workflows/
│       └── deploy-docs-swa.yml
│
├── infra/
│   ├── main.bicep
│   └── main.bicepparam
│
├── static/
│   └── staticwebapp.config.json
│
├── docs/
├── src/
├── docusaurus.config.ts
├── package.json
└── ...
```

The infrastructure files use the required `main.bicep` and `main.bicepparam` naming convention.

## 3. Create `infra/main.bicep`

Use:

```bicep
targetScope = 'subscription'

// ──────── Parameters ────────

@description('Required: Configuration of the Resource Group.')
param resourceGroupConfig ResourceGroupConfig

@description('Required: Configuration of the Azure Static Web App.')
param staticWebAppConfig StaticWebAppConfig

// ──────── Resource Group ────────

resource resourceGroupResource 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: resourceGroupConfig.name
  location: resourceGroupConfig.location
  tags: resourceGroupConfig.tags
}

// ──────── Static Web App ────────

var staticWebAppName = '${staticWebAppConfig.namePrefix}-${uniqueString(subscription().subscriptionId, resourceGroupConfig.name)}'

module staticWebApp 'br/public:avm/res/web/static-site:0.9.5' = {
  name: 'staticWebApp-deployment'
  scope: resourceGroup(resourceGroupConfig.name)
  params: {
    name: staticWebAppName
    sku: staticWebAppConfig.sku
    tags: staticWebAppConfig.tags
  }
  dependsOn: [
    resourceGroupResource
  ]
}

// ──────── Outputs ────────

@description('The name of the Resource Group.')
output resourceGroupName string = resourceGroupResource.name

@description('The resource ID of the Resource Group.')
output resourceGroupResourceId string = resourceGroupResource.id

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
  @description('Required: Prefix used to construct the Azure Static Web App name.')
  @minLength(1)
  @maxLength(26)
  namePrefix: string

  @description('Required: Hosting plan of the Azure Static Web App.')
  sku: 'Free' | 'Standard'

  @description('Required: Resource tags.')
  tags: object
}
```

### Why the name is constructed in `main.bicep`

This is important because we previously ran into:

```text
BCP057: The name "subscription" does not exist in the current context.
```

A `.bicepparam` file cannot use the deployment-context `subscription()` function in this way.

Therefore the parameter file provides:

```text
pe-docs-webapp
```

and `main.bicep` constructs:

```text
pe-docs-webapp-xxxxxxxxxxxxx
```

using:

```bicep
uniqueString(
  subscription().subscriptionId,
  resourceGroupConfig.name
)
```

This also means that the same prefix deployed into a different resource group or subscription produces a different deterministic name.

### Why Static Web App `location` is omitted

The AVM defaults `location` to:

```bicep
resourceGroup().location
```

which is exactly what we want. The Static Web App will therefore use the resource group's location without duplicating that value in `staticWebAppConfig`.

This follows the style rule to omit configuration where the verified module default already represents the desired state.

### Why only `name`, `sku`, and `tags` are supplied

The current AVM defaults include:

```text
sku                    = Free
allowConfigFileUpdates = true
provider               = None
```

We explicitly override `sku` because custom authentication requires Static Web Apps Standard. We leave `allowConfigFileUpdates` and `provider` untouched because their defaults already match our desired design.

The AVM currently exposes `name`, `resourceId`, and `defaultHostname`, which we use as our deployment outputs rather than predicting Azure-generated values ourselves.

AVM `0.9.5` is currently the latest published version in its changelog.

## 4. Create `infra/main.bicepparam`

Use:

```bicep
using 'main.bicep'

param resourceGroupConfig = {
  location: 'westeurope'
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

param staticWebAppConfig = {
  namePrefix: 'pe-docs-webapp'
  sku: 'Standard'
  tags: {
    application: 'platform-docs'
    costCenter: '<cost-center>'
    environment: 'dev'
    location: 'westeurope'
    part: 'frontend'
    resourceType: 'static-web-app'
  }
}
```

Replace:

```text
<cost-center>
```

with the appropriate value.

The configuration objects and their properties are intentionally kept together and alphabetically ordered in accordance with the Bicepparam conventions.

The tags distinguish:

```text
part: infrastructure
```

from:

```text
part: frontend
```

which also supports the cost-tracking conventions in the parameter style guide.

## 5. Log in to the DEV Azure tenant

From PowerShell:

```powershell
az login --tenant "<DEV-TENANT-ID>"
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

Confirm that both the tenant and subscription are the intended DEV environment.

## 6. Restore and validate Bicep

Restore the AVM:

```powershell
az bicep restore `
    --file .\infra\resource\main.bicep
```

Build the template:

```powershell
az bicep build `
    --file .\infra\resource\main.bicep
```

Resolve any Bicep compiler or linter findings before continuing. The style guide explicitly requires linting and validation of Bicep code.

## 7. Run a subscription-level `what-if`

Use:

```powershell
$deploymentLocation = "westeurope"
```

Then:

```powershell
az deployment sub what-if `
    --location $deploymentLocation `
    --template-file .\infra\resource\main.bicep `
    --parameters .\infra\resource\main.bicepparam
```

The important changes should be approximately:

```text
Subscription
│
└── + rg-platform-docs-dev
    │
    └── + Microsoft.Web/staticSites
        └── pe-docs-webapp-xxxxxxxxxxxxx
```

The Resource Group API `2025-04-01` is the current documented version and supports subscription-scope deployment.

## 8. Deploy the infrastructure

Run:

```powershell
az deployment sub create `
    --name "platform-docs-deployment" `
    --location $deploymentLocation `
    --template-file .\infra\resource\main.bicep `
    --parameters .\infra\resource\main.bicepparam
```

This creates both:

```text
rg-platform-docs-dev
└── Azure Static Web App
```

in one subscription deployment.

## 9. Capture the deployment outputs

Retrieve the deployment:

```powershell
$deployment = az deployment sub show `
    --name "platform-docs-deployment" `
    | ConvertFrom-Json
```

Get the Static Web App name:

```powershell
$staticWebAppName = `
    $deployment.properties.outputs.staticWebAppName.value
```

Get the generated hostname:

```powershell
$defaultHostname = `
    $deployment.properties.outputs.staticWebAppDefaultHostname.value
```

Display them:

```powershell
$staticWebAppName
$defaultHostname
```

The hostname will resemble:

```text
gentle-tree-012345678.azurestaticapps.net
```

Construct the authentication callback:

```powershell
$authenticationCallbackUrl = `
    "https://$defaultHostname/.auth/login/aad/callback"

$authenticationCallbackUrl
```

For example:

```text
https://gentle-tree-012345678.azurestaticapps.net/.auth/login/aad/callback
```

Microsoft documents `/.auth/login/aad/callback` as the callback endpoint for the Microsoft Entra provider in Static Web Apps.

## 10. Configure the App Registration in DEV

The App Registration lives in the same DEV tenant as the Static Web App.

If you still have the existing `docs-oidc-poc` registration, you can reuse it. Otherwise create a new registration.

Use:

**Microsoft Entra ID → App registrations → New registration**

Configure:

```text
Name:
pe-docs-webapp

Supported account types:
Multiple Entra ID tenants
```

Do **not** select:

```text
Any Entra ID tenant + Personal Microsoft Accounts
```

We need organizational Entra identities only.

### Add the Static Web App callback

Under:

**Authentication → Add a platform → Web**

add:

```text
https://<STATIC-WEB-APP-HOSTNAME>/.auth/login/aad/callback
```

Use the value stored in:

```powershell
$authenticationCallbackUrl
```

If this is the old PoC registration, remove:

```text
https://jwt.ms
```

and disable the temporary:

```text
Implicit grant → ID tokens
```

setting we enabled for the earlier test.

## 11. Remove unnecessary API permissions

Go to:

**App registrations → pe-docs-webapp → API permissions**

If the automatically created:

```text
Microsoft Graph
└── User.Read
```

permission is still present, remove it.

The documentation site does not need to call Microsoft Graph. We only require OIDC authentication.

Do not add permissions such as:

```text
Directory.Read.All
Group.Read.All
Mail.Read
User.Read.All
```

The result should be a very low-privilege authentication application.

## 12. Create the App Registration client secret

Go to:

**Certificates & secrets → Client secrets → New client secret**

Create a secret with an expiry appropriate for the PoC.

Copy the **Value**, not the secret ID.

Record:

```text
Application client ID
Client secret value
```

The secret is used server-side by Azure Static Web Apps and must not be committed to Git.

Static Web Apps custom authentication uses an App Registration client ID and client credential stored as Static Web App application settings.

**TODO: Replace with Managed Identity approach once available.**

## 13. Grant DEV2 tenant-wide consent

Now switch to the **DEV2 tenant**.

Record:

```text
DEV2 tenant ID
```

Then construct:

```text
https://login.microsoftonline.com/<DEV2-TENANT-ID>/adminconsent?client_id=<APPLICATION-CLIENT-ID>
```

```powershell
$dev2_tenant_id = "<DEV2-TENANT-ID>"
$app_client_id = "<APPLICATION-CLIENT-ID>"

$url = "https://login.microsoftonline.com/" +
   "$dev2_tenant_id" +
   "/adminconsent?client_id=" +
   "$app_client_id"

$url
```

Open this URL in a browser and authenticate using a DEV2 administrator account.

Approve the application.

Microsoft documents this tenant-wide admin-consent URL and states that granting consent creates the corresponding Enterprise Application/service principal in the target tenant.

## 14. Verify the Enterprise Application in DEV2

In DEV2:

**Microsoft Entra ID → Enterprise applications → All applications**

Find:

```text
pe-docs-webapp
```

Open:

**Properties**

Verify:

```text
Assignment required?
No
```

This is important.

We want:

```text
Any authenticated DEV2 user
           │
           ▼
       Documentation
```

rather than:

```text
DEV2 user
   │
   ▼
Explicit user/group assignment
   │
   ▼
Documentation
```

The entire goal is to avoid individual reader provisioning.

## 15. Add the Entra settings to the Static Web App

We now need two server-side application settings:

```text
AZURE_CLIENT_ID
AZURE_CLIENT_SECRET
```

The cleanest approach for this initial implementation is:

**Azure Portal → Static Web App → Settings → Environment variables**

Add:

```text
Name:
AZURE_CLIENT_ID

Value:
<Application client ID>
```

and:

```text
Name:
AZURE_CLIENT_SECRET

Value:
<Client secret value>
```

Apply the changes.

Microsoft currently exposes Static Web Apps application settings under **Environment variables**, and they can also be configured through `az staticwebapp appsettings`.

I am deliberately keeping the secret out of `main.bicepparam`.

Once the solution is proven, we can decide whether to mature credential handling using a certificate/Key Vault approach rather than putting a secret into the infrastructure source. Static Web Apps supports certificate-based custom authentication through Key Vault as well.

## 16. Add `static/staticwebapp.config.json`

Create:

```text
static/staticwebapp.config.json
```

with:

```json
{
  "auth": {
    "identityProviders": {
      "azureActiveDirectory": {
        "registration": {
          "openIdIssuer": "https://login.microsoftonline.com/<DEV2-TENANT-ID>/v2.0",
          "clientIdSettingName": "AZURE_CLIENT_ID",
          "clientSecretSettingName": "AZURE_CLIENT_SECRET"
        }
      }
    }
  },
  "routes": [
    {
      "route": "/*",
      "allowedRoles": [
        "authenticated"
      ]
    }
  ],
  "responseOverrides": {
    "401": {
      "statusCode": 302,
      "redirect": "/.auth/login/aad?post_login_redirect_uri=.referrer"
    }
  }
}
```

Replace:

```text
<DEV2-TENANT-ID>
```

with the actual DEV2 tenant ID.

The key security boundary is:

```json
"openIdIssuer": "https://login.microsoftonline.com/<DEV2-TENANT-ID>/v2.0"
```

We are **not** using:

```text
/common
```

or:

```text
/organizations
```

Therefore authentication is specifically bound to DEV2.

Microsoft explicitly supports a tenant-specific V2 Entra issuer in Static Web Apps custom authentication. Custom authentication requires the Standard plan.

The route:

```json
"allowedRoles": [
  "authenticated"
]
```

protects the entire site, while the `401` override sends anonymous users directly into the Entra login flow. Microsoft documents this as the pattern for protecting an entire Static Web App.

Using:

```text
post_login_redirect_uri=.referrer
```

also returns the user to the documentation page they originally tried to open rather than always sending them to the home page.

## 17. Adjust the Docusaurus hosting configuration

Your current GitHub Pages configuration may resemble:

```typescript
url: 'https://my-org.github.io',
baseUrl: '/my-docs/',
```

Azure Static Web Apps hosts the site at the domain root:

```text
https://<hostname>.azurestaticapps.net/
```

so the SWA build needs:

```typescript
url: 'https://<hostname>.azurestaticapps.net',
baseUrl: '/',
```

Because GitHub Pages is still useful while testing, I recommend making these values environment-driven.

For example in `docusaurus.config.ts`:

```typescript
const config: Config = {
  url:
    process.env.DOCS_URL ??
    'https://<CURRENT-GITHUB-PAGES-HOST>',

  baseUrl:
    process.env.DOCS_BASE_URL ??
    '/<CURRENT-GITHUB-PAGES-BASE-PATH>/',

  // Existing configuration continues here.
}
```

Do not change the rest of your Docusaurus configuration unnecessarily.

The GitHub Pages workflow can continue using its current/default values, while the Azure workflow explicitly supplies:

```text
DOCS_URL=https://<STATIC-WEB-APP-HOSTNAME>
DOCS_BASE_URL=/
```

## 18. Verify the Docusaurus build locally

In PowerShell:

```powershell
$env:DOCS_URL = "https://$defaultHostname"
$env:DOCS_BASE_URL = "/"

npm ci
npm run build
```

Docusaurus should generate:

```text
build\
```

Verify that the Static Web Apps configuration was copied into the build output:

```powershell
Test-Path .\build\staticwebapp.config.json
```

Expected:

```text
True
```

Inspect it if needed:

```powershell
Get-Content .\build\staticwebapp.config.json
```

This matters because Static Web Apps processes the configuration from the deployed output directory. When skipping the SWA build process, Microsoft specifically notes that `staticwebapp.config.json` must be included in the deployed output.

Clean up the temporary PowerShell environment variables afterwards if desired:

```powershell
Remove-Item Env:DOCS_URL
Remove-Item Env:DOCS_BASE_URL
```

## 19. Obtain the Static Web App deployment token

Open:

**Azure Portal → Static Web App → Manage deployment token**

Copy the deployment token.

This credential allows GitHub Actions to deploy content to the Static Web App. It has nothing to do with end-user Entra authentication.

## 20. Add GitHub repository configuration

In the GitHub repository, go to:

**Settings → Secrets and variables → Actions**

### Add repository secret

Create:

```text
AZURE_STATIC_WEB_APPS_API_TOKEN
```

with the SWA deployment-token value.

### Add repository variable

Create:

```text
DOCS_URL
```

with:

```text
https://<STATIC-WEB-APP-HOSTNAME>
```

For example:

```text
https://gentle-tree-012345678.azurestaticapps.net
```

`DOCS_BASE_URL` does not really need to become a repository variable because it will always be `/` for this deployment.

## 21. Create the GitHub Actions workflow

Create:

```text
.github/workflows/deploy-docs-swa.yml
```

Use:

```yaml
name: Deploy Docusaurus to Azure Static Web Apps

on:
  push:
    branches:
      - main
  workflow_dispatch:

permissions:
  contents: read

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest

    env:
      DOCS_BASE_URL: /
      DOCS_URL: ${{ vars.DOCS_URL }}

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up Node.js
        uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: npm

      - name: Install dependencies
        run: npm ci

      - name: Build Docusaurus
        run: npm run build

      - name: Verify Static Web Apps configuration
        run: test -f build/staticwebapp.config.json

      - name: Deploy
        uses: Azure/static-web-apps-deploy@v1
        with:
          action: upload
          app_location: build
          azure_static_web_apps_api_token: ${{ secrets.AZURE_STATIC_WEB_APPS_API_TOKEN }}
          output_location: ''
          skip_app_build: true
```

If your repository already pins another Node.js version, use that version instead of `20`.

The important deployment properties are:

```yaml
app_location: build
output_location: ''
skip_app_build: true
```

We explicitly build Docusaurus ourselves, then ask Static Web Apps to deploy the already generated files. Microsoft documents this pattern for scenarios where you want complete control over the frontend build.

## 22. Deploy the site

Commit:

```text
infra/main.bicep
infra/main.bicepparam
static/staticwebapp.config.json
docusaurus.config.ts
.github/workflows/deploy-docs-swa.yml
```

and push to:

```text
main
```

Monitor:

**GitHub → Actions → Deploy Docusaurus to Azure Static Web Apps**

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
Verify staticwebapp.config.json
   │
   ▼
Deploy build/
```

## 23. Test anonymous access

Open an InPrivate browser and browse to:

```text
https://<STATIC-WEB-APP-HOSTNAME>
```

You should **not** see Docusaurus immediately.

Expected flow:

```text
Anonymous browser
       │
       ▼
Azure Static Web Apps
       │
       │ 401
       ▼
/.auth/login/aad
       │
       ▼
DEV2 Entra
```

You can also test without a browser:

```powershell
curl.exe -I "https://$defaultHostname/"
```

The anonymous request should be redirected rather than receiving the documentation directly.

## 24. Test using a DEV2 user

Authenticate with a normal DEV2 account.

Expected flow:

```text
DEV2 user
   │
   ▼
DEV2 Entra authentication
   │
   ▼
OIDC token
   │
   ▼
Azure Static Web Apps
   │
   ▼
authenticated role
   │
   ▼
Docusaurus
```

No GitHub identity or repository access should be involved.

## 25. Inspect the authenticated principal

While logged in, open:

```text
https://<STATIC-WEB-APP-HOSTNAME>/.auth/me
```

Static Web Apps exposes this endpoint to display information about the authenticated client principal.

You should see an authenticated identity corresponding to the DEV2 user.

Do not paste the complete authentication response into tickets or public channels.

## 26. Perform the negative test

Open another InPrivate session.

Attempt to authenticate with an account from DEV that is **not present in DEV2**.

Expected result:

```text
DEV account
    │
    ▼
DEV2 tenant-specific issuer
    │
    ▼
Rejected
```

This test proves that we built:

```text
DEV2 identities ✅
Other tenants   ❌
Anonymous       ❌
```

rather than:

```text
Any Microsoft identity ✅
```

## 27. Test a deep documentation link

Open a URL directly to a documentation page, for example:

```text
https://<STATIC-WEB-APP-HOSTNAME>/docs/platform/something
```

while logged out.

Expected flow:

```text
Deep link
   │
   ▼
Login
   │
   ▼
Return to original deep link
```

This verifies the:

```text
post_login_redirect_uri=.referrer
```

behavior.

## 28. Test logout

Navigate to:

```text
https://<STATIC-WEB-APP-HOSTNAME>/.auth/logout
```

Then request the documentation again.

You should be required to authenticate again.

Static Web Apps provides `/.auth/login/...`, `/.auth/logout`, and `/.auth/me` as managed authentication endpoints.

## 29. Keep GitHub Pages during validation

I would not disable GitHub Pages immediately.

For a short validation period, keep:

```text
Existing users
    │
    ▼
GitHub Pages


Test users
    │
    ▼
Azure Static Web Apps
```

Verify at least:

* Navigation.
* Search.
* Images.
* Static downloads.
* Deep links.
* Authentication.
* Logout.
* Mobile/browser behavior.
* Existing Docusaurus plugins.
* Internal links.
* External links.

Once the SWA version is proven, disable the GitHub Pages deployment.

## 30. Final access model

After cutover:

```text
Documentation contributors
        │
        ▼
GitHub Enterprise
        │
        ▼
Internal repository


Documentation consumers
        │
        ▼
Corporate Entra ID
        │
        ▼
Azure Static Web Apps
        │
        ▼
Docusaurus
```

This cleanly separates:

```text
Who can edit the documentation
```

from:

```text
Who can read the documentation
```

which is the problem with the current GitHub Pages model.

## 31. Moving from DEV2 to the corporate tenant

Once this is fully proven with DEV2, we can approach corporate IAM with a working implementation.

The corporate change becomes small.

### Corporate IAM

Corporate IAM grants tenant-wide consent to the **same multitenant App Registration** using its existing client ID.

That creates the corresponding Enterprise Application in the corporate tenant.

They ensure:

```text
Assignment required = No
```

### Static Web Apps configuration

If DEV2 was purely a test identity tenant and no longer needs access, change:

```json
"openIdIssuer": "https://login.microsoftonline.com/<DEV2-TENANT-ID>/v2.0"
```

to:

```json
"openIdIssuer": "https://login.microsoftonline.com/<CORPORATE-TENANT-ID>/v2.0"
```

and redeploy Docusaurus.

Nothing else needs to change:

```text
Static Web App              unchanged
App Registration client ID unchanged
Client secret               unchanged
GitHub workflow             unchanged
GitHub repository           unchanged
Docusaurus                  unchanged
```

Only the trusted identity tenant changes.

### If DEV2 and corporate must both remain supported

Do **not** simply change the issuer to:

```text
/common
```

because that broadens the authentication boundary to other Entra tenants.

If both DEV2 and corporate identities must remain valid simultaneously, we should configure two explicitly trusted OIDC providers instead. Static Web Apps custom authentication supports multiple custom OpenID Connect providers.

For the current PoC, however, keeping the site **DEV2-only** gives us the strongest end-to-end proof of the eventual corporate architecture.

## End state

When this guide is complete, we will have proven:

```text
GitHub Internal repository
          │
          │ Build + deploy
          ▼
Azure Static Web Apps
DEV tenant
          │
          │ OIDC
          ▼
DEV2 Entra tenant
          │
          ▼
Any DEV2 employee
          │
          ▼
Private company documentation
```

with:

* No GitHub requirement for readers.
* No reader-by-reader authorization.
* No B2B guest provisioning in DEV.
* No publicly readable documentation.
* Existing Entra authentication controls.
* Docusaurus remaining a normal static site.
* Infrastructure managed through Bicep.
* AVM used directly where it provides the required functionality.
