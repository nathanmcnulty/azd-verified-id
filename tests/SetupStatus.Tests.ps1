BeforeDiscovery {
    Import-Module (Join-Path $PSScriptRoot '../scripts/modules/VerifiedIdStatus.psm1') -Force
}

Describe 'Read-only setup status' {
    InModuleScope VerifiedIdStatus {
        BeforeAll {
            function New-FixtureToken([hashtable]$Claims) {
                $payload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($Claims | ConvertTo-Json -Depth 8 -Compress))).TrimEnd('=').Replace('+', '-').Replace('/', '_')
                "e30.$payload.fixture"
            }
        }
        BeforeEach {
            $script:target = @{ TenantId = '11111111-1111-1111-1111-111111111111'; SubscriptionId = '22222222-2222-2222-2222-222222222222'; OperatorObjectId = '33333333-3333-3333-3333-333333333333'; Hostname = 'did.example.com'; StaticWebAppHostname = 'site.azurestaticapps.net'; ResourceGroup = 'fixture-rg'; KeyVaultName = 'fixture-vault' }
            $script:claims = @{ tid = $target.TenantId; oid = $target.OperatorObjectId; aud = '6a8b4b39-c021-437c-b060-5a14a3fd65f3'; scp = 'full_access'; iss = "https://sts.windows.net/$($target.TenantId)/"; exp = [DateTimeOffset]::UtcNow.AddHours(1).ToUnixTimeSeconds(); nbf = [DateTimeOffset]::UtcNow.AddMinutes(-1).ToUnixTimeSeconds() }
            $script:authority = [pscustomobject]@{ id = 'authority-id'; didModel = [pscustomobject]@{ did = 'did:web:did.example.com'; linkedDomainUrls = @('https://did.example.com/'); didDocumentStatus = 'published' }; linkedDomainsVerified = $true; keyVaultMetadata = [pscustomobject]@{ subscriptionId = $target.SubscriptionId; resourceGroup = $target.ResourceGroup; resourceName = $target.KeyVaultName }; signingSecret = 'DO-NOT-REPORT' }
            $script:linkClaims = @{ iss = 'did:web:did.example.com'; sub = 'did:web:did.example.com'; nbf = $claims.nbf; exp = $claims.exp; vc = @{ type = @('VerifiableCredential', 'DomainLinkageCredential'); credentialSubject = @{ id = 'did:web:did.example.com'; origin = 'https://did.example.com' } } }
            $script:adminFixtureToken = New-FixtureToken $claims | ConvertTo-SecureString -AsPlainText -Force
            Mock Get-VidStatusCname { @('site.azurestaticapps.net') }
            Mock Invoke-VidStatusGet {
                switch ($Uri.AbsolutePath) {
                    '/.well-known/did.json' { [pscustomobject]@{ id = 'did:web:did.example.com'; verificationMethod = @(@{ id = 'key'; privateKey = 'DO-NOT-REPORT' }) } }
                    '/.well-known/did-configuration.json' { [pscustomobject]@{ '@context' = 'https://identity.foundation/.well-known/did-configuration/v1'; linked_dids = @((New-FixtureToken $script:linkClaims)) } }
                    '/v1.0/verifiableCredentials/authorities' { [pscustomobject]@{ value = @($script:authority) } }
                    '/v1.0/verifiableCredentials/authorities/authority-id/contracts' { [pscustomobject]@{ value = @([pscustomobject]@{ id = 'contract-id'; rules = @{ vc = @{ type = @('VerifiedEmployee') } }; manifestUrl = 'https://secret.example/?bearer=DO-NOT-REPORT' }) } }
                    '/v1.0/verifiableCredentials/organizationSettings/myAccount' { [pscustomobject]@{ contractIdsEnabled = @('contract-id') } }
                    default { throw 'Unexpected GET.' }
                }
            }
        }
        It 'reports independently ready configuration while issuance and presentation remain pending; receipts contain no returned material' {
            $result = Get-VerifiedIdSetupStatus @target -AdminAccessToken $adminFixtureToken
            $result.configurationReady | Should -BeTrue
            ($result.gates | Where-Object name -eq 'authority').state | Should -Be 'Ready'
            ($result.gates | Where-Object name -eq 'did-document').state | Should -Be 'Observed'
            ($result.gates | Where-Object name -eq 'issuance').state | Should -Be 'Pending'
            ($result | ConvertTo-Json -Depth 8) | Should -Not -Match 'DO-NOT-REPORT|bearer=|e30\.'
            Should -Invoke Invoke-VidStatusGet -Times 5 -Exactly
        }
        It 'does no network work without target context and does not read persisted Complete as readiness' {
            $env:VERIFIED_ID_SETUP_STATUS = 'Complete'
            try {
                $result = Get-VerifiedIdSetupStatus
                $result.configurationReady | Should -BeFalse
                @($result.gates).Count | Should -Be 11
                Should -Invoke Invoke-VidStatusGet -Times 0 -Exactly
                Should -Invoke Get-VidStatusCname -Times 0 -Exactly
            } finally { Remove-Item Env:VERIFIED_ID_SETUP_STATUS }
        }
        It 'keeps missing admin access actionable while observing public gates' {
            $result = Get-VerifiedIdSetupStatus @target
            ($result.gates | Where-Object name -eq 'dns').state | Should -Be 'Ready'
            ($result.gates | Where-Object name -eq 'admin-access').nextStep | Should -Match 'existing unexpired delegated'
            Should -Invoke Invoke-VidStatusGet -Times 0 -Exactly -ParameterFilter { $AdminAccessToken }
        }
        It 'rejects mismatched or stale unsigned token routing claims: <field>' -ForEach @(
            @{ field = 'tid'; value = '44444444-4444-4444-4444-444444444444' },
            @{ field = 'oid'; value = '44444444-4444-4444-4444-444444444444' },
            @{ field = 'aud'; value = 'https://graph.microsoft.com' },
            @{ field = 'scp'; value = 'User.Read' }, @{ field = 'iss'; value = 'https://foreign.example/' },
            @{ field = 'exp'; value = 1 }, @{ field = 'nbf'; value = 9999999999 }
        ) {
            $claims[$field] = $value
            $wrong = New-FixtureToken $claims | ConvertTo-SecureString -AsPlainText -Force
            $result = Get-VerifiedIdSetupStatus @target -AdminAccessToken $wrong
            ($result.gates | Where-Object name -eq 'admin-access').state | Should -Be 'Pending'
            Should -Invoke Invoke-VidStatusGet -Times 0 -Exactly -ParameterFilter { $AdminAccessToken }
        }
        It 'rejects a foreign authority vault and does not query its contract' {
            $authority.keyVaultMetadata.subscriptionId = 'foreign'
            $result = Get-VerifiedIdSetupStatus @target -AdminAccessToken $adminFixtureToken
            ($result.gates | Where-Object name -eq 'authority').state | Should -Be 'Pending'
            Should -Invoke Invoke-VidStatusGet -Times 0 -Exactly -ParameterFilter { $Uri.AbsolutePath -match '/contracts' }
        }
        It 'rejects a persisted foreign authority ID' {
            $result = Get-VerifiedIdSetupStatus @target -AuthorityId 'foreign-id' -AdminAccessToken $adminFixtureToken
            ($result.gates | Where-Object name -eq 'authority').state | Should -Be 'Pending'
        }
        It 'rejects ambiguous authority responses' {
            Mock Invoke-VidStatusGet { [pscustomobject]@{ value = @($script:authority, $script:authority) } } -ParameterFilter { $Uri.AbsolutePath -eq '/v1.0/verifiableCredentials/authorities' }
            (Get-VerifiedIdSetupStatus @target -AdminAccessToken $adminFixtureToken).configurationReady | Should -BeFalse
        }
        It 'rejects a contract GET whose returned ID differs from the selected ID' {
            Mock Invoke-VidStatusGet { [pscustomobject]@{ id = 'foreign'; rules = @{ vc = @{ type = @('VerifiedEmployee') } } } } -ParameterFilter { $Uri.AbsolutePath -like '*/contracts/contract-id' }
            $result = Get-VerifiedIdSetupStatus @target -ContractId 'contract-id' -AdminAccessToken $adminFixtureToken
            ($result.gates | Where-Object name -eq 'credential-contract').state | Should -Be 'Pending'
        }
        It 'reports expired or foreign domain-link claims as pending: <field>' -ForEach @(@{ field = 'exp'; value = 1 }, @{ field = 'iss'; value = 'did:web:foreign.example' }, @{ field = 'nbf'; value = 9999999999 }) {
            $linkClaims[$field] = $value
            $result = Get-VerifiedIdSetupStatus @target -AdminAccessToken $adminFixtureToken
            ($result.gates | Where-Object name -eq 'domain-link-document').state | Should -Be 'Pending'
        }
        It 're-observes service readiness on resume rather than caching the previous result' {
            (Get-VerifiedIdSetupStatus @target -AdminAccessToken $adminFixtureToken).configurationReady | Should -BeTrue
            $authority.linkedDomainsVerified = $false
            $result = Get-VerifiedIdSetupStatus @target -AdminAccessToken $adminFixtureToken
            ($result.gates | Where-Object name -eq 'service-domain-verification').state | Should -Be 'Pending'
            $result.configurationReady | Should -BeFalse
        }
        It 'does not serialize exceptions or failed service response details' {
            Mock Invoke-VidStatusGet { throw 'DO-NOT-REPORT token=secret' }
            $json = Get-VerifiedIdSetupStatus @target -AdminAccessToken $adminFixtureToken | ConvertTo-Json -Depth 8
            $json | Should -Not -Match 'DO-NOT-REPORT|token=secret'
        }
        It 'keeps missing or incorrectly typed service verification flags pending: <variant>' -ForEach @(@{ variant = 'missing' }, @{ variant = 'string' }) {
            if ($variant -eq 'missing') { $authority.PSObject.Properties.Remove('linkedDomainsVerified') } else { $authority.linkedDomainsVerified = 'true' }
            $result = Get-VerifiedIdSetupStatus @target -AdminAccessToken $adminFixtureToken
            ($result.gates | Where-Object name -eq 'service-domain-verification').state | Should -Be 'Pending'
        }
        It 'rejects conflicting or empty contract authority binding without a downstream settings GET: <path>/<binding>' -ForEach @(
            @{ path = 'list'; binding = 'foreign-authority' }, @{ path = 'exact'; binding = 'foreign-authority' },
            @{ path = 'list'; binding = '' }, @{ path = 'exact'; binding = '' },
            @{ path = 'list'; binding = $null }, @{ path = 'exact'; binding = $null }
        ) {
            $script:contractBinding = $binding
            $script:contractPath = $path
            Mock Invoke-VidStatusGet {
                $dto = [pscustomobject]@{ id = 'contract-id'; authorityId = $script:contractBinding; rules = @{ vc = @{ type = @('VerifiedEmployee') } } }
                if ($script:contractPath -eq 'list') { [pscustomobject]@{ value = @($dto) } } else { $dto }
            } -ParameterFilter { $Uri.AbsolutePath -match '/contracts' }
            $parameters = @{} + $target
            if ($path -eq 'exact') { $parameters.ContractId = 'contract-id' }
            $result = Get-VerifiedIdSetupStatus @parameters -AdminAccessToken $adminFixtureToken
            ($result.gates | Where-Object name -eq 'credential-contract').state | Should -Be 'Pending'
            Should -Invoke Invoke-VidStatusGet -Times 0 -Exactly -ParameterFilter { $Uri.AbsolutePath -eq '/v1.0/verifiableCredentials/organizationSettings/myAccount' }
        }
        It 'supports matching and documented omitted contract authority bindings: <path>/<binding>' -ForEach @(
            @{ path = 'list'; binding = 'matching' }, @{ path = 'exact'; binding = 'matching' },
            @{ path = 'list'; binding = 'omitted' }, @{ path = 'exact'; binding = 'omitted' }
        ) {
            $script:contractBinding = $binding
            $script:contractPath = $path
            Mock Invoke-VidStatusGet {
                $dto = [pscustomobject]@{ id = 'contract-id'; rules = @{ vc = @{ type = @('VerifiedEmployee') } } }
                if ($script:contractBinding -eq 'matching') { $dto | Add-Member -NotePropertyName authorityId -NotePropertyValue 'authority-id' }
                if ($script:contractPath -eq 'list') { [pscustomobject]@{ value = @($dto) } } else { $dto }
            } -ParameterFilter { $Uri.AbsolutePath -match '/contracts' }
            $parameters = @{} + $target
            if ($path -eq 'exact') { $parameters.ContractId = 'contract-id' }
            $result = Get-VerifiedIdSetupStatus @parameters -AdminAccessToken $adminFixtureToken
            $result.configurationReady | Should -BeTrue
            Should -Invoke Invoke-VidStatusGet -Times 1 -Exactly -ParameterFilter { $Uri.AbsolutePath -eq '/v1.0/verifiableCredentials/organizationSettings/myAccount' }
        }
        It 'keeps wrong-origin and unsupported domain-link credentials pending' {
            $linkClaims.vc.credentialSubject.origin = 'https://foreign.example'
            ($result = Get-VerifiedIdSetupStatus @target -AdminAccessToken $adminFixtureToken) | Out-Null
            ($result.gates | Where-Object name -eq 'domain-link-document').state | Should -Be 'Pending'
            Mock Invoke-VidStatusGet { [pscustomobject]@{ '@context' = 'https://identity.foundation/.well-known/did-configuration/v1'; linked_dids = @(@{ proof = @{ type = 'unsupported' } }) } } -ParameterFilter { $Uri.AbsolutePath -eq '/.well-known/did-configuration.json' }
            $result = Get-VerifiedIdSetupStatus @target -AdminAccessToken $adminFixtureToken
            ($result.gates | Where-Object name -eq 'domain-link-document').state | Should -Be 'Pending'
        }
    }
}

Describe 'Closed GET transport' {
    InModuleScope VerifiedIdStatus {
        BeforeEach { Mock Invoke-RestMethod { @{ id = 'fixture' } }; $fixtureToken = ConvertTo-SecureString 'fixture' -AsPlainText -Force }
        It 'uses GET with no redirects and bearer authentication only on the exact admin origin' {
            Invoke-VidStatusGet -Uri 'https://verifiedid.did.msidentity.com/v1.0/verifiableCredentials/authorities' -AdminAccessToken $fixtureToken
            Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter { $Method -eq 'Get' -and $MaximumRedirection -eq 0 -and $Authentication -eq 'Bearer' -and $Token -eq $fixtureToken }
        }
        It 'uses unauthenticated GET for the selected public origin' {
            Invoke-VidStatusGet -Uri 'https://did.example.com/.well-known/did.json' -PublicHostname 'did.example.com'
            Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter { $Method -eq 'Get' -and $MaximumRedirection -eq 0 -and -not $Token -and -not $Headers }
        }
        It 'rejects unauthorized admin routes and URI boundaries: <url>' -ForEach @(
            @{ url = 'https://foreign.example/v1.0/verifiableCredentials/authorities' },
            @{ url = 'https://verifiedid.did.msidentity.com/v1.0/verifiableCredentials/authorities/a/generateDidDocument' },
            @{ url = 'https://verifiedid.did.msidentity.com/secrets' },
            @{ url = 'http://verifiedid.did.msidentity.com/v1.0/verifiableCredentials/authorities' },
            @{ url = 'https://verifiedid.did.msidentity.com/v1.0/verifiableCredentials/authorities?token=secret' },
            @{ url = 'https://user@verifiedid.did.msidentity.com/v1.0/verifiableCredentials/authorities' }
        ) {
            { Invoke-VidStatusGet -Uri $url -AdminAccessToken $fixtureToken } | Should -Throw
            Should -Invoke Invoke-RestMethod -Times 0 -Exactly
        }
        It 'rejects foreign public origins and unapproved document paths' {
            { Invoke-VidStatusGet -Uri 'https://foreign.example/.well-known/did.json' -PublicHostname 'did.example.com' } | Should -Throw
            { Invoke-VidStatusGet -Uri 'https://did.example.com/secret' -PublicHostname 'did.example.com' } | Should -Throw
            Should -Invoke Invoke-RestMethod -Times 0 -Exactly
        }
        It 'does not follow a failed redirect transport or expose its location in the authoritative report' {
            Mock Invoke-RestMethod { throw 'Redirect https://foreign.example/?secret=fixture' }
            { Invoke-VidStatusGet -Uri 'https://did.example.com/.well-known/did.json' -PublicHostname 'did.example.com' } | Should -Throw
            Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter { $MaximumRedirection -eq 0 }
        }
    }
}

Describe 'CLI without implicit authentication' {
    It 'returns actionable context pending from the actual entry point and imports no bootstrap module' {
        $entry = Join-Path $PSScriptRoot '../scripts/Get-VerifiedIdSetupStatus.ps1'
        $result = & $entry -TenantId '' -SubscriptionId '' -OperatorObjectId '' -Hostname '' -StaticWebAppHostname '' -ResourceGroup '' -KeyVaultName '' -AuthorityId '' -ContractId '' | ConvertFrom-Json
        $result.reportType | Should -Be 'verifiedIdSetupStatus'
        $result.configurationReady | Should -BeFalse
        $code = Get-Content $entry -Raw
        $code | Should -Not -Match 'VerifiedId\.psm1|azd\s+|az\s+|Connect-|Import-VidAzdEnvironment'
    }
}
