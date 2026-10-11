# Read-only setup status (PowerShell 7.6+)

Run `./scripts/Get-VerifiedIdSetupStatus.ps1` to obtain one JSON status result. Re-run it after changes to observe current state; it does not persist status or reuse a previous `Complete` flag. Without selected context it returns actionable pending gates and performs no network requests.

Supply `TenantId`, `SubscriptionId`, `OperatorObjectId`, `Hostname`, `StaticWebAppHostname`, `ResourceGroup` and `KeyVaultName` explicitly, or set their existing process-environment counterparts listed in the entry point. Optional `AuthorityId` and `ContractId` bind persisted exact IDs. This command does not load the azd environment, acquire tokens, invoke hooks, consent, create registrations, read signing secrets or alter any environment value.

```powershell
./scripts/Get-VerifiedIdSetupStatus.ps1 `
  -TenantId $selectedTenant -SubscriptionId $selectedSubscription `
  -OperatorObjectId $selectedOperator -Hostname $selectedDomain `
  -StaticWebAppHostname $selectedSite -ResourceGroup $selectedGroup `
  -KeyVaultName $selectedVault -AdminAccessToken $existingAdminToken
```

`existingAdminToken` must be a `SecureString` already obtained through an authorized normal browser/broker flow. Do not put plaintext tokens in command history, azd settings or saved reports. No token is necessary to observe the public DNS/documents. Admin gates remain pending without an existing usable token. The selected operator must be permitted to read this tenant's Verified ID configuration; locally supplied IDs do not authorize access.

The admin token's unsigned decoded tenant, operator, audience, delegated `full_access` scope, issuer and validity interval guard routing only. The service authenticates each GET. [Microsoft documents the admin audience and scope](https://learn.microsoft.com/en-us/entra/verified-id/admin-api); `full_access` also permits writes, despite this client's GET-only behavior. The manifest records this existing requirement, not approval to grant it.

| Gate | Observation and pending action |
| --- | --- |
| context | Validate the selected identifiers and DNS names; complete missing context before network requests. |
| dns | Observe the CNAME pointing to the selected Static Web App; an authorized DNS operator must correct missing or foreign records. |
| did-document | Observe HTTPS document ID and verification-method presence; publish the matching document through authorized setup if absent. |
| domain-link-document | Observe matching unexpired compact JWT claims; unsupported Linked Data proof formats remain pending independent verification. |
| admin-access | Decode routing claims without asserting signature verification; obtain existing matching authorized access if unavailable. |
| authority | Service GET must identify one DID/domain authority with selected subscription/resource-group/vault metadata; reconcile mismatches separately. |
| service-domain-verification | Fresh service authority must report `published` and `linkedDomainsVerified: true`; status never invokes verification POSTs. |
| credential-contract | Observe one VerifiedEmployee contract on the selected authority, matching an explicit contract ID when supplied. |
| myaccount | Fresh settings must enable that exact contract. |
| issuance | Pending until the real credential issuance trial in VID-002. |
| presentation | Pending until the real credential presentation trial in VID-002. |

`Observed` means structural or unsigned decoded evidence, not cryptographic verification. [DIF domain linkage requires cryptographic proof](https://identity.foundation/well-known-did-configuration/resources/did-configuration/); this command does not verify signatures. `Ready` records the particular successful lookup or fresh service response described by that gate. `configurationReady` requires no pending configuration gates, including the fresh service domain flags. It never claims end-to-end credential issuance, user delivery or presentation readiness. Responses and exception details are discarded rather than copied into the closed report; tokens, signing material, manifests, bearer URLs and identity attributes are excluded.

The only authenticated routes are GET `authorities`, selected-authority `contracts` or exact contract, and `organizationSettings/myAccount` on `https://verifiedid.did.msidentity.com`. Public requests use only the two selected-domain well-known HTTPS paths with no bearer token. All HTTP requests disable redirects and reject credentials, query strings, fragments and foreign origins. DNS and HTTPS failures remain separate actionable pending gates.

## Read-only resume versus writes

This status entry point only observes. `azd hooks run postprovision` is the separately authorized **mutating resume** workflow: it can create temporary admin objects, onboard a tenant, generate documents, publish static assets, request domain binding, validate domains, create contracts, enable MyAccount and persist settings. DNS publication, signing-key changes, tenant reset and teardown similarly require their own authorization. Status never calls those helpers and never automatically fixes a pending gate.

The baseline source at [4d34f9a](https://github.com/nathanmcnulty/azd-verified-id/tree/4d34f9a1c87c948190bd188fd2aa97d7ca58798b) identifies Graph bootstrap delegated `Application.ReadWrite.All` and `DelegatedPermissionGrant.ReadWrite.All` in [GraphBootstrap.psm1](https://github.com/nathanmcnulty/azd-verified-id/blob/4d34f9a1c87c948190bd188fd2aa97d7ca58798b/scripts/modules/GraphBootstrap.psm1), the admin app/scope above, and Key Vault/tenant write operations in [VerifiedIdAdmin.psm1](https://github.com/nathanmcnulty/azd-verified-id/blob/4d34f9a1c87c948190bd188fd2aa97d7ca58798b/scripts/modules/VerifiedIdAdmin.psm1). Existing advanced configuration describes Authentication Policy Administrator for tenant setup and the separate application-registration/consent administrator requirements. These baseline write permissions are documented evidence, not new status permissions. `azd-permissions.json` is deliberately partial: effective operator roles, deployment/cleanup RBAC, signing access, consent actors and DNS-provider permissions still require exact-target verification. The status feature adds no grants, Azure RBAC, Graph scopes or signing permissions.

## Optional component decisions

Evaluation uses immutable azd-reference [277584b](https://github.com/nathanmcnulty/azd-reference/tree/277584b33fcae7d47113718aad6428abdc4bc50f); there is no runtime dependency on reference.

| Component | Decision and contract comparison |
| --- | --- |
| deployment-validation 1.1.1 stable | Defer adoption for this change. Its [schema](https://github.com/nathanmcnulty/azd-reference/blob/277584b33fcae7d47113718aad6428abdc4bc50f/schemas/deployment-validation.schema.json) requires requirements, checks, summary, outcome and validation modes. A future adapter can map gate names/states and next steps to checks, retaining `Observed` versus service readiness and exact selected target bindings. Do not claim its generic success outcome as credential issuance. One native status result is authoritative now; no parallel competing result paths. |
| deployment-receipt 0.2.1 candidate | Defer: [receipt schema](https://github.com/nathanmcnulty/azd-reference/blob/277584b33fcae7d47113718aad6428abdc4bc50f/schemas/deployment-receipt.schema.json) and [standard](https://github.com/nathanmcnulty/azd-reference/blob/277584b33fcae7d47113718aad6428abdc4bc50f/standards/deployment-receipts.md) describe plan/enforce mutation counts and bound resourceMutation/cleanup operations. Read-only observation must not invent applied counts or signing actions. A future authorized write workflow could produce a separately bound safe receipt, excluding signing keys, tokens and request secrets. |

No component lock is created because no reusable code is adopted. Assessment pins are evidence only. Offline fixtures exercise the actual status module, transport and CLI, including ready configuration and stale/foreign bindings. They prove no live authorization, DNS propagation, service verification, issuance, presentation or cleanup; VID-002 retains those acceptance gates.
