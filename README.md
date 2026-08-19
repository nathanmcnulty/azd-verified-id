# azd-verified-id

Infrastructure-only Azure Developer CLI template for advanced Microsoft Entra Verified ID setup with a customer-managed signing Key Vault and a `did:web` domain.

The template converts the behavior of `Initialize-VerifiedID.ps1` into declarative Bicep and small, resumable azd hooks. It does not deploy an issuer/verifier sample application, retain a customer application registration, or use client secrets.

## Resources

The default deployment creates:

- One resource group
- One Standard Azure Key Vault using the access-policy permission model required by Verified ID
- One Free Azure Static Web App for the public DID documents
- One Microsoft Entra Verified ID `did:web` authority

Verified ID service principals and their Key Vault key policies are created or reconciled during tenant onboarding. The temporary public-client application used for delegated administration is removed after every hook run.

## Prerequisites

- PowerShell 7
- Azure CLI and Azure Developer CLI
- Authentication Policy Administrator in the target tenant
- Permissions to create applications and principal-specific delegated permission grants
- Contributor on the target Azure subscription or resource group
- Control of the public DNS hostname
- Microsoft Authenticator for later credential use

The Graph identity used by the hook must be able to perform the equivalent of `Application.ReadWrite.All` and `DelegatedPermissionGrant.ReadWrite.All`. The hook creates a temporary single-tenant public client, grants only the current user the Verified ID Admin `full_access` delegated scope, and uses authorization code with PKCE.

For a terminal without a usable local browser callback, select the device-code fallback before provisioning:

```powershell
$env:AZD_VERIFIED_ID_USE_DEVICE_CODE = 'true'
azd provision
```

## Deploy

```powershell
azd auth login
az login --tenant <tenant-id>
azd init
azd up
```

Preprovision discovers the tenant organization display name and verified primary domain. By default, the authority name is the organization display name and the DID hostname is `did.<primary-domain>`. Override either before `azd up` when needed:

```powershell
azd env set VERIFIED_ID_DISPLAY_NAME "Contoso"
azd env set VERIFIED_ID_DOMAIN did.contoso.com
```

The DNS hostname must be in a public zone you control. An `onmicrosoft.com` initial domain is not deployable as a customer-controlled DID hostname, so tenants without a verified custom domain must set `VERIFIED_ID_DOMAIN` explicitly.

The first tenant mutation requires typing the expected DID. For a deliberately unattended run:

```powershell
$env:AZD_VERIFIED_ID_NON_INTERACTIVE = 'true'
$env:VERIFIED_ID_CONFIRM_BOOTSTRAP_DID = 'did:web:did.contoso.com'
azd up --no-prompt
```

The first run commonly stops in the resumable `DnsActionRequired` state. Apply the TXT and CNAME values printed by the hook, wait for public DNS propagation, and rerun the postprovision hook explicitly. This works even when Bicep has no changes:

```powershell
azd hooks run postprovision
```

For `did.contoso.com`, the ownership TXT record name is `_dnsauth.did.contoso.com`. Keep the TXT record while replacing the CNAME with the Static Web App hostname produced by the deployment.

Credential creation waits until the public documents are available and Verified ID persists `linkedDomainsVerified: true`. The hook retries the domain refresh and polls the authority for up to five minutes to absorb service replication delays; it does not treat the validation request's `204` response as completion by itself.

## VerifiedEmployee

The hook creates the official `VerifiedEmployee` contract through the documented Admin API access-token attestation model, enables it in My Account, and records its manifest URL. Existing `VerifiedEmployee` contracts are discovered but never updated or replaced. Existing My Account contract IDs are preserved. See [`credential/verified-employee.md`](credential/verified-employee.md).

## Configuration

User-facing deployment inputs are mapped in [`infra/main.parameters.json`](infra/main.parameters.json) and described by Bicep parameter metadata, allowing a deployment wizard to discover them. Preprovision supplies every missing value before Bicep runs. Tenant-derived defaults are calculated from the selected Azure CLI tenant.

### Core inputs

| azd value | Default | Description |
| --- | --- | --- |
| `AZURE_LOCATION` | `westus2` | Key Vault region |
| `VERIFIED_ID_STATIC_WEB_APP_LOCATION` | `eastus2` | Static Web App region |
| `VERIFIED_ID_KEY_VAULT_SKU` | `standard` | `standard` or explicitly approved `premium` |
| `VERIFIED_ID_ENABLE_PURGE_PROTECTION` | `false` | Enable for a long-lived production authority |
| `VERIFIED_ID_DISPLAY_NAME` | Tenant organization name | Authority and credential issuer display name |
| `VERIFIED_ID_DOMAIN` | `did.<primary-domain>` | `did:web` hostname |
| `VERIFIED_ID_EMPLOYEE_LOGO_URI` | Microsoft logo URL | Anonymous HTTPS logo used during managed credential creation |
| `VERIFIED_ID_SKIP_TENANT_BOOTSTRAP` | `false` | Create only Azure infrastructure and skip tenant mutation |
| `AZD_VERIFIED_ID_USE_DEVICE_CODE` | `false` | Use device code instead of system-browser PKCE |

### Credential Styling

These values are only used when creating a missing `VerifiedEmployee` contract. Existing contracts are never restyled.

| azd value | Default |
| --- | --- |
| `VERIFIED_ID_EMPLOYEE_LOCALE` | `en-US` |
| `VERIFIED_ID_EMPLOYEE_CARD_TITLE` | `Verified Employee` |
| `VERIFIED_ID_EMPLOYEE_CARD_BACKGROUND_COLOR` | `#000000` |
| `VERIFIED_ID_EMPLOYEE_CARD_TEXT_COLOR` | `#FFFFFF` |
| `VERIFIED_ID_EMPLOYEE_CARD_DESCRIPTION` | `This verifiable credential is issued to all members of the {displayName} org.` |
| `VERIFIED_ID_EMPLOYEE_LOGO_DESCRIPTION` | `Default verified employee logo` |
| `VERIFIED_ID_EMPLOYEE_CONSENT_TITLE` | `Do you want to accept the verified employee credential from {displayName}.` |
| `VERIFIED_ID_EMPLOYEE_CONSENT_INSTRUCTIONS` | `Verify your identity and workplace the easy way. Add this ID for online and in-person use.` |

`{displayName}` is replaced with `VERIFIED_ID_DISPLAY_NAME` during contract creation.

### Advanced Inputs

| azd value | Default | Description |
| --- | --- | --- |
| `AZURE_RESOURCE_GROUP_NAME` | `rg-verified-id-<environment>` | Resource group name |
| `VERIFIED_ID_KEY_VAULT_NAME` | Stable generated name | Globally unique Key Vault name |
| `VERIFIED_ID_STATIC_WEB_APP_NAME` | Stable generated name | Globally unique Static Web App name |
| `VERIFIED_ID_ALLOW_PREMIUM` | `false` | Required in addition to selecting the Premium SKU |

Premium Key Vault is never selected implicitly. It requires both:

```powershell
azd env set VERIFIED_ID_KEY_VAULT_SKU premium
azd env set VERIFIED_ID_ALLOW_PREMIUM true
```

Automated tests verify that Standard remains the default.

Purge protection must also be selected before the first `azd provision`; the create-only vault design deliberately refuses to mutate an existing signing vault.

Infrastructure-only validation can deliberately skip tenant mutation:

```powershell
azd env set VERIFIED_ID_SKIP_TENANT_BOOTSTRAP true
azd provision
```

Remove or set that value to `false` before the real Verified ID bootstrap.

## Reruns

The hook resumes by persisted authority ID and verifies the exact DID, linked domain, subscription, resource group, and Key Vault metadata before changing anything. Display names are not used as authority identity. Once the dedicated vault exists, Bicep references it without updating the parent resource; this prevents a rerun from replacing policies added by Verified ID or another administrator.

Use `azd hooks run postprovision` to reconcile tenant state without requiring an infrastructure change. Each run marks status as `Reconciling`, validates the authority, public documents, manifest, contract, and My Account setting, then derives the final status. Failures set `VERIFIED_ID_PROVISIONING_STATUS` to `Failed` instead of leaving a stale `Complete` value.

Nonsecret IDs and status values are stored in the selected azd environment. Access tokens, authorization codes, refresh tokens, and Static Web App deployment tokens are never persisted.

## Cleanup

Deleting the Static Web App or Key Vault breaks an active authority. `azd down` therefore requires typed confirmation.

Tenant-wide Verified ID opt-out is disabled by default. To explicitly reset a dedicated test tenant before Azure resource deletion:

```powershell
azd env set VERIFIED_ID_RESET_TENANT_ON_DOWN true
azd down
```

The hook inventories the tenant, verifies that the expected authority points to this environment's Key Vault, warns that every authority, contract, and issued credential will be invalidated, and requires the domain to be typed again. Noninteractive reset additionally requires the process variable `VERIFIED_ID_CONFIRM_TENANT_RESET_DOMAIN` to exactly equal the configured hostname.

Noninteractive resource deletion without tenant reset requires the process variable `VERIFIED_ID_CONFIRM_RESOURCE_DELETE_DOMAIN` to equal the configured hostname. Confirmation values should not be persisted in the azd environment.

## Validate

```powershell
./scripts/Test-Repository.ps1
```

Validation parses every PowerShell file, builds Bicep, and runs Pester 5 tests when available.

## Security decisions

- No long-lived customer app registration or client secret
- Principal-specific temporary delegated grant, removed after use
- PKCE and OAuth state validation
- Exact authority and Key Vault metadata matching
- Key Vault access-policy model with no secret or certificate permissions
- Standard Key Vault by default
- Free Static Web Apps used only for anonymous well-known documents
- Deployment and bearer tokens kept in process memory only
- No issuer/verifier sample application, callback endpoint, CORS policy, or credential data store
- Tenant-wide opt-out guarded separately from normal deployment

The Azure Samples issuer/verifier applications are not used as an implementation foundation.
