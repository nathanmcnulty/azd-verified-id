Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:VerifiedIdBaseUri = 'https://verifiedid.did.msidentity.com'

function Invoke-VidAdminRequest {
    param(
        [Parameter(Mandatory)][ValidateSet('GET', 'POST', 'PATCH', 'DELETE')][string]$Method,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$AccessToken,
        [AllowNull()][object]$Body,
        [switch]$NoRetry
    )

    $parameters = @{
        Method = $Method
        Uri = "$($script:VerifiedIdBaseUri)$Path"
        Headers = @{ Authorization = "Bearer $AccessToken" }
        NoRetry = $NoRetry
    }
    if ($PSBoundParameters.ContainsKey('Body')) { $parameters.Body = $Body }
    return Invoke-VidRestMethod @parameters
}

function Invoke-VidAdminOperation {
    param(
        [Parameter(Mandatory)][hashtable]$Parameters,
        [AllowNull()][scriptblock]$Invoker
    )
    if ($null -ne $Invoker) { return & $Invoker $Parameters }
    return Invoke-VidAdminRequest @Parameters
}

function Get-VidAuthorities {
    param([Parameter(Mandatory)][string]$AccessToken)
    $result = Invoke-VidAdminRequest -Method GET -Path '/v1.0/verifiableCredentials/authorities' -AccessToken $AccessToken
    if ($null -eq $result) { return @() }
    if ($null -ne $result.PSObject.Properties['value']) { return @($result.value) }
    if ($result -is [Array]) { return @($result) }
    return @()
}

function Find-VidAuthority {
    param(
        [AllowNull()][object[]]$Authorities,
        [Parameter(Mandatory)][string]$Hostname,
        [AllowEmptyString()][string]$AuthorityId = ''
    )

    $expectedDid = "did:web:$Hostname"
    $expectedOrigins = @("https://$Hostname", "https://$Hostname/")
    if (-not [string]::IsNullOrWhiteSpace($AuthorityId)) {
        $byId = @($Authorities | Where-Object { $_.id -eq $AuthorityId })
        if ($byId.Count -gt 1) { throw "Multiple authorities returned the persisted ID '$AuthorityId'." }
        if ($byId.Count -eq 1) {
            $linkedDomains = @($byId[0].didModel.linkedDomainUrls)
            if ($byId[0].didModel.did -ne $expectedDid -or @($linkedDomains | Where-Object { $_ -in $expectedOrigins }).Count -eq 0) {
                throw "Persisted authority '$AuthorityId' does not match $expectedDid."
            }
            return $byId[0]
        }
        throw "Persisted authority '$AuthorityId' was not returned by Verified ID. Refusing to bind to a replacement authority."
    }

    $authorityMatches = @($Authorities | Where-Object {
        if ($null -eq $_ -or $null -eq $_.PSObject.Properties['didModel']) { return $false }
        $linkedDomains = @($_.didModel.linkedDomainUrls)
        $_.didModel.did -eq $expectedDid -and @($linkedDomains | Where-Object { $_ -in $expectedOrigins }).Count -gt 0
    })
    if ($authorityMatches.Count -gt 1) { throw "Multiple Verified ID authorities match '$Hostname'. Refusing an ambiguous deployment." }
    if ($authorityMatches.Count -eq 1) { return $authorityMatches[0] }
    return $null
}

function Add-VidKeyVaultAccessPolicy {
    param(
        [Parameter(Mandatory)][string]$SubscriptionId,
        [Parameter(Mandatory)][string]$ResourceGroupName,
        [Parameter(Mandatory)][string]$VaultName,
        [Parameter(Mandatory)][string]$TenantId,
        [Parameter(Mandatory)][string]$ObjectId,
        [Parameter(Mandatory)][string[]]$KeyPermissions
    )

    $uri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.KeyVault/vaults/$VaultName/accessPolicies/add?api-version=2023-02-01"
    $bodyPath = [IO.Path]::GetTempFileName()
    try {
        @{
            properties = @{
                accessPolicies = @(
                    @{
                        tenantId = $TenantId
                        objectId = $ObjectId
                        permissions = @{
                            keys = $KeyPermissions
                            secrets = @()
                            certificates = @()
                            storage = @()
                        }
                    }
                )
            }
        } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $bodyPath -Encoding utf8NoBOM

        $result = & az rest --method put --url $uri --body "@$bodyPath" --output none 2>&1
        if ($LASTEXITCODE -ne 0) { throw "Unable to add Key Vault policy for '$ObjectId': $($result -join ' ')" }
    } finally {
        Remove-Item -LiteralPath $bodyPath -Force -ErrorAction SilentlyContinue
    }
}

function Set-VidServicePolicies {
    param(
        [Parameter(Mandatory)][object]$Onboarding,
        [Parameter(Mandatory)][string]$SubscriptionId,
        [Parameter(Mandatory)][string]$ResourceGroupName,
        [Parameter(Mandatory)][string]$VaultName,
        [Parameter(Mandatory)][string]$TenantId
    )

    $adminPermissions = @('get', 'create', 'delete', 'list', 'sign', 'recover', 'backup', 'restore')
    $runtimePermissions = @('get', 'list', 'sign')
    $policies = @(
        @{ Id = $Onboarding.verifiableCredentialAdminServicePrincipalId; Permissions = $adminPermissions; EnvironmentName = 'VERIFIED_ID_ADMIN_SP_ID' },
        @{ Id = $Onboarding.verifiableCredentialServicePrincipalId; Permissions = $runtimePermissions; EnvironmentName = 'VERIFIED_ID_SERVICE_SP_ID' },
        @{ Id = $Onboarding.verifiableCredentialRequestServicePrincipalId; Permissions = $runtimePermissions; EnvironmentName = 'VERIFIED_ID_REQUEST_SP_ID' }
    )

    $processed = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($policy in $policies) {
        if ([string]::IsNullOrWhiteSpace($policy.Id)) {
            throw "Verified ID onboarding did not return $($policy.EnvironmentName)."
        }
        Set-VidEnvironmentValue -Name $policy.EnvironmentName -Value $policy.Id
        if (-not $processed.Add($policy.Id)) { continue }
        Add-VidKeyVaultAccessPolicy -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName `
            -VaultName $VaultName -TenantId $TenantId -ObjectId $policy.Id -KeyPermissions $policy.Permissions
    }
}

function Assert-VidAuthorityVault {
    param(
        [Parameter(Mandatory)][object]$Authority,
        [Parameter(Mandatory)][string]$SubscriptionId,
        [Parameter(Mandatory)][string]$ResourceGroupName,
        [Parameter(Mandatory)][string]$VaultName
    )

    $metadata = $Authority.keyVaultMetadata
    if ($null -eq $metadata) { throw "Authority '$($Authority.id)' does not expose Key Vault metadata." }
    if ($metadata.subscriptionId -ne $SubscriptionId -or
        $metadata.resourceGroup -ne $ResourceGroupName -or
        $metadata.resourceName -ne $VaultName) {
        throw "Authority '$($Authority.id)' is bound to a different Key Vault. Expected $SubscriptionId/$ResourceGroupName/$VaultName."
    }
}

function Wait-VidAuthority {
    param(
        [Parameter(Mandatory)][string]$AuthorityId,
        [Parameter(Mandatory)][string]$AccessToken
    )

    for ($attempt = 1; $attempt -le 18; $attempt++) {
        $authority = @(Get-VidAuthorities -AccessToken $AccessToken | Where-Object { $_.id -eq $AuthorityId })[0]
        if ($null -ne $authority) { return $authority }
        Start-Sleep -Seconds ([Math]::Min(20, $attempt + 2))
    }
    throw "Authority '$AuthorityId' did not become available within the expected time."
}

function Get-VidDocuments {
    param(
        [Parameter(Mandatory)][string]$AuthorityId,
        [Parameter(Mandatory)][string]$Origin,
        [Parameter(Mandatory)][string]$AccessToken
    )

    $didDocument = $null
    for ($attempt = 1; $attempt -le 12; $attempt++) {
        try {
            $didDocument = Invoke-VidAdminRequest -Method POST `
                -Path "/v1.0/verifiableCredentials/authorities/$AuthorityId/generateDidDocument" `
                -AccessToken $AccessToken -NoRetry
            break
        } catch {
            $detail = Get-VidHttpErrorText -ErrorRecord $_
            if ($attempt -ge 12 -or $detail -notmatch 'failedToFindSpecifiedIssuerInDb|issuer id|keyVaultOperationForbidden|KeyVault server failed') { throw }
            Start-Sleep -Seconds ([Math]::Min(30, 5 + ($attempt * 2)))
        }
    }

    $wellKnown = Invoke-VidAdminRequest -Method POST `
        -Path "/v1.0/verifiableCredentials/authorities/$AuthorityId/generateWellknownDidConfiguration" `
        -AccessToken $AccessToken -Body @{ domainUrl = $Origin } -NoRetry

    return [pscustomobject]@{
        DidDocument = $didDocument
        DidConfiguration = $wellKnown
    }
}

function Get-VidVerifiedEmployeeContract {
    param(
        [Parameter(Mandatory)][string]$AuthorityId,
        [Parameter(Mandatory)][string]$AccessToken,
        [AllowEmptyString()][string]$ContractId = '',
        [AllowNull()][scriptblock]$RequestInvoker
    )

    if (-not [string]::IsNullOrWhiteSpace($ContractId)) {
        $contract = Invoke-VidAdminOperation -Invoker $RequestInvoker -Parameters @{
            Method = 'GET'; Path = "/v1.0/verifiableCredentials/authorities/$AuthorityId/contracts/$ContractId"; AccessToken = $AccessToken
        }
        if ($null -eq $contract -or $contract.id -ne $ContractId -or @($contract.rules.vc.type) -notcontains 'VerifiedEmployee') {
            throw "Persisted VerifiedEmployee contract '$ContractId' did not match the expected managed credential."
        }
        return $contract
    }

    $result = Invoke-VidAdminOperation -Invoker $RequestInvoker -Parameters @{
        Method = 'GET'; Path = "/v1.0/verifiableCredentials/authorities/$AuthorityId/contracts"; AccessToken = $AccessToken
    }
    $contracts = if ($null -ne $result -and $null -ne $result.PSObject.Properties['value']) { @($result.value) } elseif ($result -is [Array]) { @($result) } else { @() }
    $contractMatches = @($contracts | Where-Object {
        $_.name -eq 'VerifiedEmployee' -or @($_.rules.vc.type) -contains 'VerifiedEmployee'
    })
    if ($contractMatches.Count -gt 1) { throw 'Multiple VerifiedEmployee contracts were returned for this authority.' }
    if ($contractMatches.Count -eq 1) { return $contractMatches[0] }
    return $null
}

function New-VidVerifiedEmployeeContract {
    param(
        [Parameter(Mandatory)][string]$AuthorityId,
        [Parameter(Mandatory)][object]$Rules,
        [Parameter(Mandatory)][object]$Display,
        [Parameter(Mandatory)][string]$AccessToken,
        [AllowNull()][scriptblock]$RequestInvoker
    )

    $existing = Get-VidVerifiedEmployeeContract -AuthorityId $AuthorityId -AccessToken $AccessToken -RequestInvoker $RequestInvoker
    if ($null -ne $existing) { return $existing }

    $payload = @{
        name = 'Verified employee'
        rules = $Rules
        displays = @($Display)
    }
    try {
        $contract = Invoke-VidAdminOperation -Invoker $RequestInvoker -Parameters @{
            Method = 'POST'; Path = "/v1.0/verifiableCredentials/authorities/$AuthorityId/contracts"
            AccessToken = $AccessToken; Body = $payload; NoRetry = $true
        }
    } catch {
        $existing = Get-VidVerifiedEmployeeContract -AuthorityId $AuthorityId -AccessToken $AccessToken -RequestInvoker $RequestInvoker
        if ($null -ne $existing) { return $existing }
        throw
    }

    if ($null -eq $contract -or [string]::IsNullOrWhiteSpace($contract.id) -or
        [string]::IsNullOrWhiteSpace($contract.manifestUrl) -or @($contract.rules.vc.type) -notcontains 'VerifiedEmployee') {
        throw 'The Admin API did not return the expected VerifiedEmployee contract.'
    }
    return $contract
}

function Enable-VidMyAccountContract {
    param(
        [Parameter(Mandatory)][string]$ContractId,
        [Parameter(Mandatory)][string]$AccessToken,
        [AllowNull()][scriptblock]$RequestInvoker
    )

    $path = '/v1.0/verifiableCredentials/organizationSettings/myAccount'
    $changed = $false
    $requiredIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    [void]$requiredIds.Add($ContractId)
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        $current = Invoke-VidAdminOperation -Invoker $RequestInvoker -Parameters @{ Method = 'GET'; Path = $path; AccessToken = $AccessToken }
        $enabledIds = @((Get-VidObjectProperty -InputObject $current -Name 'contractIdsEnabled' -Default @()))
        foreach ($id in $enabledIds) { [void]$requiredIds.Add($id) }
        if (@($requiredIds | Where-Object { $_ -notin $enabledIds }).Count -eq 0) {
            return [pscustomobject]@{ Changed = $changed; ContractIdsEnabled = $enabledIds }
        }

        $expectedIds = @($requiredIds)
        $postError = $null
        try {
            Invoke-VidAdminOperation -Invoker $RequestInvoker -Parameters @{
                Method = 'POST'; Path = $path; AccessToken = $AccessToken
                Body = @{ contractIdsEnabled = $expectedIds }; NoRetry = $true
            } | Out-Null
            $changed = $true
        } catch {
            $postError = $_
        }

        $updated = Invoke-VidAdminOperation -Invoker $RequestInvoker -Parameters @{ Method = 'GET'; Path = $path; AccessToken = $AccessToken }
        $verifiedIds = @((Get-VidObjectProperty -InputObject $updated -Name 'contractIdsEnabled' -Default @()))
        if (@($expectedIds | Where-Object { $_ -notin $verifiedIds }).Count -eq 0) {
            return [pscustomobject]@{ Changed = $true; ContractIdsEnabled = $verifiedIds }
        }
        if ($attempt -eq 3 -and $null -ne $postError) { throw $postError }
    }
    throw "VerifiedEmployee contract '$ContractId' was not enabled in My Account without removing another enabled contract."
}

function Assert-VidVerifiedEmployeeManifest {
    param(
        [Parameter(Mandatory)][object]$Contract,
        [Parameter(Mandatory)][string]$ExpectedDid,
        [Parameter(Mandatory)][string]$ExpectedLogoUri,
        [AllowNull()][scriptblock]$ManifestFetcher
    )

    if ([string]::IsNullOrWhiteSpace($Contract.id) -or [string]::IsNullOrWhiteSpace($Contract.manifestUrl)) {
        throw 'VerifiedEmployee contract ID or manifest URL is missing.'
    }
    $manifestUri = [Uri]$Contract.manifestUrl
    if ($manifestUri.Scheme -ne 'https' -or $manifestUri.Host -ne 'verifiedid.did.msidentity.com' -or
        $manifestUri.AbsolutePath -notmatch "/contracts/$([regex]::Escape($Contract.id))/manifest$") {
        throw "VerifiedEmployee manifest URL is not the expected Microsoft endpoint for contract '$($Contract.id)'."
    }

    $manifest = $null
    for ($attempt = 1; $attempt -le 12; $attempt++) {
        try {
            $manifest = if ($null -ne $ManifestFetcher) { & $ManifestFetcher $manifestUri } else { Invoke-RestMethod -Method GET -Uri $manifestUri -ErrorAction Stop }
            if (-not [string]::IsNullOrWhiteSpace($manifest.token)) { break }
        } catch {
            if ($attempt -eq 12) { throw }
        }
        Start-Sleep -Seconds 5
    }
    $segments = @($manifest.token -split '\.')
    if ($segments.Count -ne 3) { throw 'VerifiedEmployee manifest did not contain a compact signed JWT.' }
    $header = ConvertFrom-VidJwtSegment -Segment $segments[0]
    $payload = ConvertFrom-VidJwtSegment -Segment $segments[1]
    if ($header.alg -ne 'ES256' -or $header.kid -notlike "$ExpectedDid#*") { throw 'VerifiedEmployee manifest signing header did not match the authority DID.' }
    if ($payload.iss -ne $ExpectedDid -or $payload.id -ne $Contract.id -or $payload.input.issuer -ne $ExpectedDid) { throw 'VerifiedEmployee manifest identity did not match the authority and contract.' }
    if (@($payload.vcTypes) -notcontains 'VerifiedEmployee' -or @($payload.input.attestations.accessTokens).Count -eq 0) { throw 'VerifiedEmployee manifest did not contain the expected access-token issuance model.' }
    if (@($payload.input.attestations.accessTokens | Where-Object oboScope -EQ 'User.Read.All').Count -eq 0) { throw 'VerifiedEmployee manifest did not request the expected User.Read.All OBO scope.' }
    if ($payload.display.card.logo.uri -ne $ExpectedLogoUri) { throw 'VerifiedEmployee manifest logo did not match the configured logo.' }
    return $payload
}

function Initialize-VidTenant {
    param(
        [Parameter(Mandatory)][string]$AccessToken,
        [Parameter(Mandatory)][string]$TenantId,
        [Parameter(Mandatory)][string]$SubscriptionId,
        [Parameter(Mandatory)][string]$ResourceGroupName,
        [Parameter(Mandatory)][string]$VaultName,
        [Parameter(Mandatory)][string]$Hostname,
        [Parameter(Mandatory)][string]$DisplayName,
        [AllowEmptyString()][string]$PersistedAuthorityId = '',
        [AllowEmptyString()][string]$PersistedContractId = ''
    )

    $origin = "https://$Hostname/"
    $authorities = Get-VidAuthorities -AccessToken $AccessToken
    $authority = Find-VidAuthority -Authorities $authorities -Hostname $Hostname -AuthorityId $PersistedAuthorityId
    if ($null -ne $authority) {
        Assert-VidAuthorityVault -Authority $authority -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName -VaultName $VaultName
    }

    $onboarding = Invoke-VidAdminRequest -Method POST -Path '/v1.0/verifiableCredentials/onboard' -AccessToken $AccessToken
    Set-VidServicePolicies -Onboarding $onboarding -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName `
        -VaultName $VaultName -TenantId $TenantId

    if ($null -eq $authority) {
        $payload = @{
            name = $DisplayName
            linkedDomainUrl = $origin
            didMethod = 'web'
            keyVaultMetadata = @{
                subscriptionId = $SubscriptionId
                resourceGroup = $ResourceGroupName
                resourceName = $VaultName
                resourceUrl = "https://$VaultName.vault.azure.net/"
            }
        }
        for ($attempt = 1; $attempt -le 12; $attempt++) {
            try {
                $authority = Invoke-VidAdminRequest -Method POST -Path '/v1.0/verifiableCredentials/authorities' `
                    -AccessToken $AccessToken -Body $payload -NoRetry
                break
            } catch {
                $authority = Find-VidAuthority -Authorities (Get-VidAuthorities -AccessToken $AccessToken) -Hostname $Hostname
                if ($null -ne $authority) { break }
                $detail = Get-VidHttpErrorText -ErrorRecord $_
                if ($attempt -ge 12 -or $detail -notmatch 'keyVaultOperationForbidden|KeyVault server failed|Forbidden|issuer') { throw }
                Start-Sleep -Seconds ([Math]::Min(30, 5 + ($attempt * 2)))
            }
        }
        if ($null -eq $authority) { throw "Verified ID authority for '$Hostname' was not created." }
        $authority = Wait-VidAuthority -AuthorityId $authority.id -AccessToken $AccessToken
    }

    Assert-VidAuthorityVault -Authority $authority -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName -VaultName $VaultName
    $documents = Get-VidDocuments -AuthorityId $authority.id -Origin $origin -AccessToken $AccessToken
    $contract = Get-VidVerifiedEmployeeContract -AuthorityId $authority.id -AccessToken $AccessToken -ContractId $PersistedContractId

    Set-VidEnvironmentValue -Name 'VERIFIED_ID_AUTHORITY_ID' -Value $authority.id
    Set-VidEnvironmentValue -Name 'VERIFIED_ID_DID' -Value $authority.didModel.did
    Set-VidEnvironmentValue -Name 'VERIFIED_ID_TENANT_STATUS' -Value 'AuthorityReady'
    if ($null -ne $contract) {
        Set-VidEnvironmentValue -Name 'VERIFIED_ID_EMPLOYEE_MANIFEST_URL' -Value $contract.manifestUrl
        Set-VidEnvironmentValue -Name 'VERIFIED_ID_EMPLOYEE_CONTRACT_ID' -Value $contract.id
    }

    return [pscustomobject]@{
        Authority = $authority
        Onboarding = $onboarding
        Documents = $documents
        VerifiedEmployeeContract = $contract
    }
}

function Invoke-VidTenantOptOut {
    param([Parameter(Mandatory)][string]$AccessToken)
    Invoke-VidAdminRequest -Method POST -Path '/v1.0/verifiableCredentials/optout' -AccessToken $AccessToken -NoRetry | Out-Null
}

function Invoke-VidWellKnownValidation {
    param(
        [Parameter(Mandatory)][string]$AuthorityId,
        [Parameter(Mandatory)][string]$AccessToken
    )
    Invoke-VidAdminRequest -Method POST `
        -Path "/v1.0/verifiableCredentials/authorities/$AuthorityId/validateWellKnownDidConfiguration" `
        -AccessToken $AccessToken -NoRetry | Out-Null
}

Export-ModuleMember -Function *-Vid*
