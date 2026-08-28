# Security

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting channel for this repository. Do not open a public issue containing tenant IDs, access tokens, signing material, deployment tokens, or other secrets. If private reporting is unavailable, contact the repository owner privately before disclosing details.

## Deployment boundaries

This template performs privileged tenant administration. Review the printed authority, tenant, subscription, resource group, Key Vault, and hostname before approving bootstrap or teardown. The tenant-wide `Verified ID optout` operation is irreversible and is disabled by default.

## Secret handling

Never commit bearer tokens, refresh tokens, authorization codes, deployment tokens, or private signing material. Treat `.azure` state and local evidence as sensitive administrative data.
