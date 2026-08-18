# Security

## Reporting

Do not open a public issue containing tenant IDs, access tokens, Static Web App deployment tokens, DID signing material, or other credentials. Use the repository owner's private security reporting channel.

## Deployment boundaries

This template performs privileged tenant administration. Review the printed authority, tenant, subscription, resource group, Key Vault, and hostname before approving bootstrap or teardown.

The `Verified ID optout` operation is tenant-wide and irreversible. It is disabled by default and must never be used as ordinary rollback or reconciliation.

## Persisted data

The azd environment stores resource IDs, authority IDs, the public DID, public DNS guidance, public manifest URL, and state labels. It must not contain bearer tokens, refresh tokens, authorization codes, or deployment tokens.
