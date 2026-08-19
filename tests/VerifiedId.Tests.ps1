BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\scripts\VerifiedId.psm1') -Force -DisableNameChecking
}

Describe 'Verified ID configuration helpers' {
    It 'normalizes an HTTPS hostname' {
        Normalize-VidHostname -Value 'HTTPS://DID.Contoso.com/' | Should -Be 'did.contoso.com'
    }

    It 'rejects paths in a did:web hostname' {
        { Normalize-VidHostname -Value 'https://did.contoso.com/path' } | Should -Throw
    }

    It 'rejects non-HTTPS origins' {
        { Normalize-VidHostname -Value 'http://did.contoso.com' } | Should -Throw
    }

    It 'finds an authority only by exact DID and linked domain' {
        $authorities = @(
            [pscustomobject]@{
                id = 'wrong'
                name = 'Contoso'
                didModel = [pscustomobject]@{
                    did = 'did:web:wrong.example.com'
                    linkedDomainUrls = @('https://wrong.example.com/')
                }
            },
            [pscustomobject]@{
                id = 'expected'
                name = 'A different display name'
                didModel = [pscustomobject]@{
                    did = 'did:web:did.contoso.com'
                    linkedDomainUrls = @('https://did.contoso.com/')
                }
            }
        )

        $result = Find-VidAuthority -Authorities $authorities -Hostname 'did.contoso.com'
        $result.id | Should -Be 'expected'
    }

    It 'does not accept a partial authority identity match' {
        $authority = [pscustomobject]@{
            id = 'partial'
            didModel = [pscustomobject]@{
                did = 'did:web:did.contoso.com'
                linkedDomainUrls = @('https://wrong.example.com/')
            }
        }
        Find-VidAuthority -Authorities @($authority) -Hostname 'did.contoso.com' | Should -BeNullOrEmpty
    }

    It 'refuses to replace a missing persisted authority' {
        { Find-VidAuthority -Authorities @() -Hostname 'did.contoso.com' -AuthorityId 'missing' } | Should -Throw
    }

    It 'refuses ambiguous authority matches' {
        $authority = [pscustomobject]@{
            id = 'one'
            didModel = [pscustomobject]@{
                did = 'did:web:did.contoso.com'
                linkedDomainUrls = @('https://did.contoso.com/')
            }
        }
        { Find-VidAuthority -Authorities @($authority, $authority) -Hostname 'did.contoso.com' } | Should -Throw
    }

    It 'recognizes strict boolean values' {
        ConvertTo-VidBoolean -Value 'true' | Should -BeTrue
        ConvertTo-VidBoolean -Value '0' | Should -BeFalse
        { ConvertTo-VidBoolean -Value 'sometimes' } | Should -Throw
    }
}

Describe 'Infrastructure security defaults' {
    BeforeAll {
        $mainBicep = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\infra\main.bicep') -Raw
        $vaultBicep = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\infra\modules\key-vault.bicep') -Raw
        $staticWebAppBicep = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\infra\modules\static-web-app.bicep') -Raw
    }

    It 'defaults Key Vault to Standard' {
        $mainBicep | Should -Match "param keyVaultSku string = 'standard'"
    }

    It 'uses the Key Vault access-policy model' {
        $vaultBicep | Should -Match 'enableRbacAuthorization:\s*false'
    }

    It 'retains 90 days of soft-deleted Key Vault data' {
        $vaultBicep | Should -Match 'softDeleteRetentionInDays:\s*90'
    }

    It 'uses the Free Static Web Apps tier' {
        $staticWebAppBicep | Should -Match "name:\s*'Free'"
        $staticWebAppBicep | Should -Match "tier:\s*'Free'"
    }

    It 'builds a Key Vault URI without a duplicate separator' {
        $vaultBicep | Should -Match 'keyVaultDnsSuffix'
        $vaultBicep | Should -Not -Match '\$\{name\}\.\$\{environment\(\)\.suffixes\.keyvaultDns\}'
    }
}

Describe 'Wizard input surface' {
    BeforeAll {
        $parameters = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\infra\main.parameters.json') -Raw | ConvertFrom-Json
        $parameterValues = @($parameters.parameters.PSObject.Properties.Value.value)
    }

    It 'exposes every user-facing hook input through Bicep parameters' {
        foreach ($name in @(
            'VERIFIED_ID_DISPLAY_NAME', 'VERIFIED_ID_DOMAIN', 'VERIFIED_ID_EMPLOYEE_LOGO_URI',
            'VERIFIED_ID_EMPLOYEE_LOCALE', 'VERIFIED_ID_EMPLOYEE_CARD_TITLE',
            'VERIFIED_ID_EMPLOYEE_CARD_BACKGROUND_COLOR', 'VERIFIED_ID_EMPLOYEE_CARD_TEXT_COLOR',
            'VERIFIED_ID_EMPLOYEE_CARD_DESCRIPTION', 'VERIFIED_ID_EMPLOYEE_LOGO_DESCRIPTION',
            'VERIFIED_ID_EMPLOYEE_CONSENT_TITLE', 'VERIFIED_ID_EMPLOYEE_CONSENT_INSTRUCTIONS',
            'VERIFIED_ID_ALLOW_PREMIUM', 'VERIFIED_ID_SKIP_TENANT_BOOTSTRAP', 'AZD_VERIFIED_ID_USE_DEVICE_CODE'
        )) {
            $parameterValues | Should -Contain "`${$name}"
        }
    }

    It 'initializes defaults before azd resolves infrastructure inputs' {
        $azureYaml = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\azure.yaml') -Raw
        $azureYaml | Should -Match '(?m)^\s{2}preup:'
        $azureYaml | Should -Match '(?m)^\s{2}preinfracreate:'
    }
}

Describe 'VerifiedEmployee display definition' {
    BeforeAll {
        $display = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\credential\verified-employee-display.json') -Raw | ConvertFrom-Json
    }

    It 'uses the configured Microsoft logo placeholder' {
        $display.card.logo.uri | Should -Be '__LOGO_URI__'
    }

    It 'contains the complete managed credential display claim set' {
        $claimNames = @($display.claims.claim)
        foreach ($claim in @('givenName', 'surname', 'mail', 'jobTitle', 'photo', 'displayName', 'preferredLanguage', 'revocationId')) {
            $claimNames | Should -Contain "vc.credentialSubject.$claim"
        }
    }

}

Describe 'VerifiedEmployee access-token rules' {
    BeforeAll {
        $rules = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\credential\verified-employee-rules.json') -Raw | ConvertFrom-Json
    }

    It 'creates the official VerifiedEmployee credential type' {
        @($rules.vc.type) | Should -Contain 'VerifiedEmployee'
    }

    It 'uses the supported Entra employee claim mappings' {
        $mappings = @($rules.attestations.accessTokens[0].mapping)
        @($mappings.inputClaim) | Should -Be @('displayName', 'givenName', 'jobTitle', 'preferredLanguage', 'surname', 'mail', 'userPrincipalName', 'photo')
        ($mappings | Where-Object outputClaim -EQ 'revocationId').indexed | Should -BeTrue
    }
}
