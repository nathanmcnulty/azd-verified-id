# Advanced Configuration

The default configuration is designed for a guided `azd init` and `azd up` deployment. Change these values only when the organization requires different names, regions, branding, or automation behavior.

The guided command prompts for the issuer display name, Verified ID hostname, and purge protection. Standard azd prompts select the environment, subscription, and Azure location. A GUI can set these values before deployment to suppress the corresponding questions.

Set an option before deployment with:

```powershell
azd env set <NAME> <VALUE>
```

## Core Options

| Name | Default | Purpose |
| --- | --- | --- |
| `AZURE_LOCATION` | `westus2` | Azure region for the Key Vault and resource group |
| `VERIFIED_ID_STATIC_WEB_APP_LOCATION` | `eastus2` | Azure region for the public DID website |
| `VERIFIED_ID_DISPLAY_NAME` | Tenant organization name | Name shown as the authority and credential issuer |
| `VERIFIED_ID_DOMAIN` | `did.<primary-domain>` | Public hostname used by `did:web` |
| `VERIFIED_ID_KEY_VAULT_SKU` | `standard` | Key Vault SKU |
| `VERIFIED_ID_ENABLE_PURGE_PROTECTION` | `false` | Protect a production signing vault from permanent deletion |
| `VERIFIED_ID_EMPLOYEE_LOGO_URI` | Microsoft logo URL | Anonymous HTTPS logo used when the credential is created |

Purge protection must be selected before the first deployment. The template does not modify this setting on an existing signing vault.

Premium Key Vault requires both settings:

```powershell
azd env set VERIFIED_ID_KEY_VAULT_SKU premium
azd env set VERIFIED_ID_ALLOW_PREMIUM true
```

## Resource Names

Names are stable and generated automatically from the azd environment and subscription. They can be overridden before the first deployment.

| Name | Generated default |
| --- | --- |
| `AZURE_RESOURCE_GROUP_NAME` | `rg-verified-id-<environment>` |
| `VERIFIED_ID_KEY_VAULT_NAME` | Globally unique `kvvid...` name |
| `VERIFIED_ID_STATIC_WEB_APP_NAME` | Globally unique `swa-vid...` name |

## Credential Appearance

These values are used only when a missing Verified Employee credential is created. The template never restyles an existing credential.

| Name | Default |
| --- | --- |
| `VERIFIED_ID_EMPLOYEE_LOCALE` | `en-US` |
| `VERIFIED_ID_EMPLOYEE_CARD_TITLE` | `Verified Employee` |
| `VERIFIED_ID_EMPLOYEE_CARD_BACKGROUND_COLOR` | `#000000` |
| `VERIFIED_ID_EMPLOYEE_CARD_TEXT_COLOR` | `#FFFFFF` |
| `VERIFIED_ID_EMPLOYEE_CARD_DESCRIPTION` | `This verifiable credential is issued to all members of the {displayName} org.` |
| `VERIFIED_ID_EMPLOYEE_LOGO_DESCRIPTION` | `Default verified employee logo` |
| `VERIFIED_ID_EMPLOYEE_CONSENT_TITLE` | `Do you want to accept the verified employee credential from {displayName}.` |
| `VERIFIED_ID_EMPLOYEE_CONSENT_INSTRUCTIONS` | `Verify your identity and workplace the easy way. Add this ID for online and in-person use.` |

`{displayName}` is replaced with `VERIFIED_ID_DISPLAY_NAME` during creation. Color values must use the `#RRGGBB` format. Logo URLs must use HTTPS and allow anonymous access.

## Authentication Options

The default flow opens the system browser and uses the signed-in administrator as a login hint. One temporary application is created for each tenant operation and deleted after the operation completes.

Use device-code authentication when a local browser callback is unavailable:

```powershell
azd env set AZD_VERIFIED_ID_USE_DEVICE_CODE true
azd hooks run postprovision
```

Authorization URLs from timed-out operations stop working because their temporary applications are deleted. Close old tabs and rerun the command to start a new authorization.

For least privilege, the administrator needs Authentication Policy Administrator plus permission to create temporary application registrations and principal-specific delegated permission grants. Global Administrator satisfies these requirements but is not required when the permissions are delegated separately.

## Infrastructure-Only Deployment

To create Azure resources without onboarding or changing the Verified ID tenant:

```powershell
azd env set VERIFIED_ID_SKIP_TENANT_BOOTSTRAP true
azd up
```

Set the value back to `false` before running tenant setup.

## Unattended Deployment

Interactive approval is the safer default. For controlled automation, provide an exact DID confirmation in the process environment:

```powershell
$env:AZD_VERIFIED_ID_NON_INTERACTIVE = 'true'
$env:AZD_VERIFIED_ID_CONFIRM_BOOTSTRAP_DID = 'did:web:did.contoso.com'
azd up --no-prompt
```

Do not persist confirmation variables in the azd environment. Browser or device-code administrator authorization is still required because the template does not retain an application credential or refresh token.

## Resume and Status

Use this command after DNS changes or whenever tenant state needs to be checked:

```powershell
azd hooks run postprovision
```

The hook verifies persisted authority and contract IDs, Key Vault metadata, public DID files, domain ownership, the credential manifest, and My Account settings. It does not use display names as identity and does not update an existing credential.

Useful status values are stored in the azd environment:

| Status | Meaning |
| --- | --- |
| `Complete` | Deployment and tenant configuration are ready |
| `DnsActionRequired` | DNS records must be created or corrected |
| `AwaitingHttps` | DNS is correct and Azure HTTPS configuration is still propagating |
| `Failed` | The last reconciliation did not complete; review the terminal error |

## Removal and Tenant Reset

Normal `azd down` removes Azure resources but does not reset the Verified ID tenant. Removing those resources while an authority remains configured breaks that authority, so the command requires confirmation.

Tenant-wide opt-out is appropriate only for a dedicated test tenant or an intentional permanent reset. It invalidates every issued credential and removes all authorities and contracts.

```powershell
azd env set VERIFIED_ID_RESET_TENANT_ON_DOWN true
azd down --purge
```

The teardown hook clears My Account settings, waits for every authority to disappear, deletes Azure resources, and purges the Key Vault. Interactive confirmation requires typing the configured hostname.

For noninteractive reset, set `AZD_VERIFIED_ID_CONFIRM_TENANT_RESET_DOMAIN` in the process environment to the exact hostname. Noninteractive resource deletion without tenant reset similarly requires `AZD_VERIFIED_ID_CONFIRM_RESOURCE_DELETE_DOMAIN`.

## Wizard Integration

User-facing inputs are mapped in [`infra/main.parameters.json`](../infra/main.parameters.json) and described by Bicep parameter metadata. Early initialization hooks calculate tenant-derived defaults before azd resolves infrastructure inputs.

A GUI should present normal user inputs such as subscription, region, domain, branding, SKU, and purge protection. It should hide computed IDs, existence flags, status values, DNS tokens, and temporary object IDs. Safety confirmations should be requested at execution time and passed only to the child process.
