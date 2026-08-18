BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\scripts\VerifiedId.psm1') -Force -DisableNameChecking
    $contract = [pscustomobject]@{
        id = 'contract-id'
        name = 'Verified employee'
        manifestUrl = 'https://verifiedid.did.msidentity.com/v1.0/tenants/tenant/verifiableCredentials/contracts/contract-id/manifest'
        rules = [pscustomobject]@{ vc = [pscustomobject]@{ type = @('VerifiedEmployee') } }
        displays = @([pscustomobject]@{ locale = 'en-US' })
    }
    $rules = $contract.rules
    $display = $contract.displays[0]
}

Describe 'VerifiedEmployee Admin API behavior' {
    It 'returns an existing contract without creating or updating it' {
        $requests = [Collections.Generic.List[hashtable]]::new()
        $invoker = {
            param($request)
            $requests.Add($request)
            [pscustomobject]@{ value = @([pscustomobject]@{
                id = 'contract-id'; name = 'Verified employee'
                manifestUrl = 'https://verifiedid.did.msidentity.com/v1.0/tenants/tenant/verifiableCredentials/contracts/contract-id/manifest'
                rules = [pscustomobject]@{ vc = [pscustomobject]@{ type = @('VerifiedEmployee') } }
            }) }
        }.GetNewClosure()

        $result = New-VidVerifiedEmployeeContract -AuthorityId 'authority-id' -Rules $rules -Display $display `
            -AccessToken 'token' -RequestInvoker $invoker

        $result.id | Should -Be 'contract-id'
        @($requests | Where-Object Method -EQ 'GET').Count | Should -Be 1
        @($requests | Where-Object Method -In @('POST', 'PATCH')).Count | Should -Be 0
    }

    It 'creates a missing contract once with rules and a display array' {
        $requests = [Collections.Generic.List[hashtable]]::new()
        $invoker = {
            param($request)
            $requests.Add($request)
            if ($request.Method -eq 'GET') { return [pscustomobject]@{ value = @() } }
            return [pscustomobject]@{
                id = 'contract-id'; name = 'Verified employee'
                manifestUrl = 'https://verifiedid.did.msidentity.com/v1.0/tenants/tenant/verifiableCredentials/contracts/contract-id/manifest'
                rules = [pscustomobject]@{ vc = [pscustomobject]@{ type = @('VerifiedEmployee') } }
            }
        }.GetNewClosure()

        $result = New-VidVerifiedEmployeeContract -AuthorityId 'authority-id' -Rules $rules -Display $display `
            -AccessToken 'token' -RequestInvoker $invoker

        $result.id | Should -Be 'contract-id'
        $post = @($requests | Where-Object Method -EQ 'POST')
        $post.Count | Should -Be 1
        $post[0].Path | Should -Be '/v1.0/verifiableCredentials/authorities/authority-id/contracts'
        $post[0].Body.rules | Should -Be $rules
        @($post[0].Body.displays).Count | Should -Be 1
        @($requests | Where-Object Method -EQ 'PATCH').Count | Should -Be 0
    }

    It 'recovers when contract creation succeeds but the POST response is lost' {
        $state = [pscustomobject]@{ GetCount = 0 }
        $invoker = {
            param($request)
            if ($request.Method -eq 'POST') { throw 'Connection closed after request.' }
            $state.GetCount++
            if ($state.GetCount -eq 1) { return [pscustomobject]@{ value = @() } }
            return [pscustomobject]@{ value = @([pscustomobject]@{
                id = 'contract-id'; name = 'Verified employee'
                manifestUrl = 'https://verifiedid.did.msidentity.com/v1.0/tenants/tenant/verifiableCredentials/contracts/contract-id/manifest'
                rules = [pscustomobject]@{ vc = [pscustomobject]@{ type = @('VerifiedEmployee') } }
            }) }
        }.GetNewClosure()

        $result = New-VidVerifiedEmployeeContract -AuthorityId 'authority-id' -Rules $rules -Display $display `
            -AccessToken 'token' -RequestInvoker $invoker

        $result.id | Should -Be 'contract-id'
    }

    It 'does not replace an existing My Account contract list' {
        $requests = [Collections.Generic.List[hashtable]]::new()
        $invoker = { param($request) $requests.Add($request); [pscustomobject]@{ contractIdsEnabled = @('existing-id', 'contract-id') } }.GetNewClosure()

        $result = Enable-VidMyAccountContract -ContractId 'contract-id' -AccessToken 'token' -RequestInvoker $invoker

        $result.Changed | Should -BeFalse
        @($requests | Where-Object Method -EQ 'GET').Count | Should -Be 1
        @($requests | Where-Object Method -EQ 'POST').Count | Should -Be 0
    }

    It 'additively enables My Account and verifies existing IDs remain' {
        $requests = [Collections.Generic.List[hashtable]]::new()
        $state = [pscustomobject]@{ GetCount = 0 }
        $invoker = {
            param($request)
            $requests.Add($request)
            if ($request.Method -eq 'POST') { return $null }
            $state.GetCount++
            if ($state.GetCount -eq 1) { return [pscustomobject]@{ contractIdsEnabled = @('existing-id') } }
            return [pscustomobject]@{ contractIdsEnabled = @('existing-id', 'contract-id') }
        }.GetNewClosure()

        $result = Enable-VidMyAccountContract -ContractId 'contract-id' -AccessToken 'token' -RequestInvoker $invoker

        $result.Changed | Should -BeTrue
        $result.ContractIdsEnabled | Should -Contain 'existing-id'
        $result.ContractIdsEnabled | Should -Contain 'contract-id'
        $post = @($requests | Where-Object Method -EQ 'POST')
        $post.Count | Should -Be 1
        $post[0].Body.contractIdsEnabled | Should -Contain 'existing-id'
        $post[0].Body.contractIdsEnabled | Should -Contain 'contract-id'
    }

    It 'fails when My Account drops a previously enabled contract' {
        $state = [pscustomobject]@{ GetCount = 0 }
        $invoker = {
            param($request)
            if ($request.Method -eq 'POST') { return $null }
            $state.GetCount++
            if ($state.GetCount -eq 1) { return [pscustomobject]@{ contractIdsEnabled = @('existing-id') } }
            return [pscustomobject]@{ contractIdsEnabled = @('contract-id') }
        }.GetNewClosure()

        { Enable-VidMyAccountContract -ContractId 'contract-id' -AccessToken 'token' -RequestInvoker $invoker } | Should -Throw
    }
}

Describe 'VerifiedEmployee manifest behavior' {
    It 'validates the contract, authority, issuance model, and logo' {
        $headerJson = '{"alg":"ES256","kid":"did:web:did.example.com#key-1"}'
        $payloadJson = '{"iss":"did:web:did.example.com","id":"contract-id","input":{"issuer":"did:web:did.example.com","attestations":{"accessTokens":[{"oboScope":"User.Read.All"}]}},"vcTypes":["VerifiableCredential","VerifiedEmployee"],"display":{"card":{"logo":{"uri":"https://example.com/logo.png"}}}}'
        $encode = {
            param([string]$Value)
            [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Value)).TrimEnd('=').Replace('+', '-').Replace('/', '_')
        }
        $token = "$(& $encode $headerJson).$(& $encode $payloadJson).signature"
        $fetcher = { param($uri) [pscustomobject]@{ token = $token } }.GetNewClosure()
        $manifestContract = [pscustomobject]@{
            id = 'contract-id'
            manifestUrl = 'https://verifiedid.did.msidentity.com/v1.0/tenants/tenant/verifiableCredentials/contracts/contract-id/manifest'
        }

        $result = Assert-VidVerifiedEmployeeManifest -Contract $manifestContract -ExpectedDid 'did:web:did.example.com' `
            -ExpectedLogoUri 'https://example.com/logo.png' -ManifestFetcher $fetcher

        $result.id | Should -Be 'contract-id'
    }
}
