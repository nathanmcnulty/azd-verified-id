# Deploy Microsoft Entra Verified ID

This template sets up Microsoft Entra Verified ID for your organization and creates a **Verified Employee** credential for your users.

It automatically:

- Creates the Azure resources needed to protect signing keys and publish your organization's identity
- Connects Verified ID to a public domain that you control
- Creates the Verified Employee credential using information from Microsoft Entra ID
- Makes the credential available from [My Account](https://myaccount.microsoft.com/)

You do not need to build or host an application. The deployment guides you through the required sign-ins and tells you exactly which DNS records to create.

## Before You Start

Install these free Microsoft tools on your computer:

- [Azure CLI](https://aka.ms/installazurecli)
- [Azure Developer CLI](https://aka.ms/azure-dev/install)
- [PowerShell 7](https://aka.ms/powershell-release?tag=stable)

You also need:

- An Azure subscription where you are a **Contributor**
- An administrator account in the Microsoft Entra tenant
- Access to edit DNS records for your organization's public domain

For the simplest first deployment, use a **Global Administrator** account. See [Advanced configuration](docs/advanced-configuration.md) for a least-privilege option.

## Quick Start

Open PowerShell in a new, empty folder and run:

```powershell
azd init -t nathanmcnulty/azd-verified-id .
azd up
```

Follow the instructions shown in the terminal. The deployment will:

1. Ask you to sign in to Azure if needed.
2. Ask you to confirm the organization name shown on the credential.
3. Ask you to confirm the public Verified ID hostname.
4. Ask whether the signing Key Vault should be protected from permanent deletion.
5. Open a browser for administrator approval.
6. Create the Azure resources and Verified ID authority.

The default Verified ID address is `did.<your-primary-domain>`. For example, an organization using `contoso.com` gets `did.contoso.com`.

## Complete the DNS Step

The first run normally pauses and prints two DNS records:

- A **TXT** record that proves domain ownership
- A **CNAME** record that points the Verified ID domain to Azure

Create or replace those records with your DNS provider. Copy the names and values exactly as shown. If you use Cloudflare, set the CNAME to **DNS only**, not proxied.

After the records are saved, run:

```powershell
azd hooks run postprovision
```

The deployment waits for DNS, HTTPS, and Microsoft Entra replication. It then creates the Verified Employee credential and enables it in My Account.

Success looks like this:

```text
[OK] Verified ID persisted public DID and linked-domain verification
[OK] Managed VerifiedEmployee credential created
[OK] VerifiedEmployee credential enabled in My Account
[OK] Verified ID deployment is complete
```

## Confirm the Result

In the [Microsoft Entra admin center](https://entra.microsoft.com/):

1. Open **Verified ID**.
2. Confirm that domain ownership is verified.
3. Open **Credentials** and select **Verified Employee**.
4. Confirm that the credential is available in My Account.

Users can then visit [My Account](https://myaccount.microsoft.com/) to obtain their Verified Employee credential in Microsoft Authenticator.

## What Gets Created

The default deployment creates:

- One Azure resource group
- One Standard Azure Key Vault for Verified ID signing keys
- One Free Azure Static Web App for the public identity files
- One `did:web` Verified ID authority
- One Verified Employee credential enabled in My Account

A temporary sign-in registration is used for administrator approval and deleted immediately afterward.

## Safe to Run Again

You can safely run this command to check or resume the deployment:

```powershell
azd hooks run postprovision
```

The template verifies the existing authority and credential instead of replacing them. Existing Verified Employee settings are never overwritten.

## Common Issues

| Message or symptom | What to do |
| --- | --- |
| `DnsActionRequired` | Create the TXT and CNAME records printed by the deployment, then run `azd hooks run postprovision`. |
| Domain validation is still pending | Wait a few minutes for DNS propagation, then run the postprovision command again. |
| The wrong tenant or subscription is selected | Run `az logout`, then `az login --tenant <tenant-id>` and retry. |
| `AADSTS700016` references an unfamiliar application ID | Close that old browser tab. It belongs to a temporary application from an earlier timed-out run and has already been deleted. |
| Browser sign-in is unavailable | See the device-code option in [Advanced configuration](docs/advanced-configuration.md). |

## Removing the Deployment

Do not delete the Key Vault or Static Web App independently. They are part of the Verified ID authority.

Tenant reset is intentionally protected because it invalidates issued credentials. Read [Removal and tenant reset](docs/advanced-configuration.md#removal-and-tenant-reset) before using `azd down`.

## More Information

- [Advanced configuration](docs/advanced-configuration.md)
- [Verified Employee details](credential/verified-employee.md)
- [Security guidance](SECURITY.md)
