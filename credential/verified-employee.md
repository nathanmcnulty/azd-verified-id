# Managed VerifiedEmployee credential

The postprovision hook creates the directory-backed `VerifiedEmployee` credential through the documented Admin API contract endpoint.

The hook uses `verified-employee-rules.json` for the documented access-token claim mappings and `verified-employee-display.json` for card, consent, and claim display settings. It always checks for an existing contract by `VerifiedEmployee` type before creation and never updates or replaces an existing contract.

After creation or discovery, the hook additively enables the contract in My Account through `organizationSettings/myAccount`. Existing enabled contract IDs are preserved.

Override the default logo before provisioning with:

```powershell
azd env set VERIFIED_ID_EMPLOYEE_LOGO_URI https://example.com/logo.png
```

The URL must use HTTPS and return an image anonymously.

The managed schema includes directory-backed claims documented by Microsoft, including `revocationId`, `displayName`, `givenName`, `surname`, and optional `jobTitle`, `preferredLanguage`, `mail`, and `photo` values.
