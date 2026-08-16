# Starting Prompt: azd-verified-id

Convert the existing Microsoft Entra Verified ID work in this account into a private, secure Azure Developer CLI (`azd`) template. Do not copy or use the unsafe sample application patterns from `active-directory-verifiable-credentials-dotnet` as an implementation foundation.

## Product direction

Build a minimal but complete issuer/verifier solution based on Nathan's own script and current Microsoft Entra Verified ID guidance. The deployment should demonstrate secure credential issuance and presentation without embedding client secrets, weak token handling, permissive CORS, insecure storage, or sample-only shortcuts.

## Reference material

- `nathanmcnulty/nathanmcnulty/Entra/verified-id/Initialize-VerifiedID.ps1` as the primary source for the existing deployment logic and intent.
- `nathanmcnulty/research-passkeys` only for repository organization, validation, and deployment automation patterns where relevant; do not mix passkey behavior into the Verified ID product.
- `nathanmcnulty/azd-entra-iga` for Bicep, lifecycle hooks, managed identity, configuration, and Graph permission validation patterns.
- `nathanmcnulty/azd-myworkid` for a complete azd application deployment shape.
- Microsoft Learn documentation for the current Entra Verified ID service, DID configuration, credential manifests, issuance, presentation, app registration, and production security requirements.
- `active-directory-verifiable-credentials-dotnet` may be consulted only to understand protocol terminology or historical API shapes. Treat its code as untrusted reference material and do not copy its unsafe patterns.

## Expected implementation

Use `azure.yaml`, Bicep, and azd hooks. Prefer Azure Functions, Container Apps, or App Service only after selecting the simplest secure hosting model. Use managed identity where supported and store unavoidable secrets/certificates in Key Vault. Include:

- A tenant-safe bootstrap that validates prerequisites and clearly reports manual Verified ID configuration steps.
- A secure issuer endpoint and verifier endpoint with strict request validation, nonce/state handling, replay protection, and no credential secrets in source control.
- Minimal sample credential definitions and explicit configuration for issuer DID, authority, credential type, claims, and trust settings.
- Safe webhook handling, structured logging without personal credential contents, and correlation IDs.
- Local development and deployed smoke tests that use disposable/test identities and never print access tokens or QR payload secrets.
- Idempotent deployment, cleanup, least-privilege permissions, and documentation for production hardening.

Start with one credential issuance flow and one presentation verification flow. Clearly separate Azure infrastructure automation from tenant actions that require administrator consent or portal configuration. Include a security review section explaining why unsafe sample patterns were not reused.