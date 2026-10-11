#requires -Version 7.6
Set-StrictMode -Version Latest

function ConvertFrom-VidStatusJwt {
    param([Parameter(Mandatory)][string]$Value)
    $parts = $Value.Split('.')
    if ($parts.Count -ne 3 -or $parts[1].Length -gt 65536) { throw 'Invalid compact token.' }
    $part = $parts[1].Replace('-', '+').Replace('_', '/')
    $part = $part.PadRight($part.Length + ((4 - $part.Length % 4) % 4), '=')
    [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($part)) | ConvertFrom-Json -AsHashtable
}

function Test-VidStatusHost {
    param([string]$Hostname)
    if ($Hostname.Length -gt 253 -or $Hostname -notmatch '^(?=.{1,253}$)(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,63}$') { return $false }
    return $true
}

function Invoke-VidStatusGet {
    [CmdletBinding()]
    param([Parameter(Mandatory)][uri]$Uri, [string]$PublicHostname, [Security.SecureString]$AdminAccessToken)
    if ($Uri.Scheme -ne 'https' -or $Uri.Port -ne 443 -or $Uri.UserInfo -or $Uri.Query -or $Uri.Fragment) { throw 'Invalid status request boundary.' }
    if ($AdminAccessToken) {
        if ($Uri.Host -cne 'verifiedid.did.msidentity.com' -or $Uri.AbsolutePath -notmatch '^/v1\.0/verifiableCredentials/(authorities(?:/[a-zA-Z0-9-]+/contracts(?:/[a-zA-Z0-9-]+)?)?|organizationSettings/myAccount)$') { throw 'Invalid admin status route.' }
        Invoke-RestMethod -Method Get -Uri $Uri -Authentication Bearer -Token $AdminAccessToken -MaximumRedirection 0 -TimeoutSec 30 -ErrorAction Stop
    } else {
        if (-not (Test-VidStatusHost $PublicHostname) -or $Uri.Host -cne $PublicHostname.ToLowerInvariant() -or $Uri.AbsolutePath -notin @('/.well-known/did.json', '/.well-known/did-configuration.json')) { throw 'Invalid public status route.' }
        Invoke-RestMethod -Method Get -Uri $Uri -MaximumRedirection 0 -TimeoutSec 30 -ErrorAction Stop
    }
}

function Get-VidStatusCname {
    param([string]$Hostname)
    @(Resolve-DnsName -Name $Hostname -Type CNAME -DnsOnly -ErrorAction Stop | Where-Object Type -eq 'CNAME' | ForEach-Object { $_.NameHost.TrimEnd('.').ToLowerInvariant() })
}

function Get-VerifiedIdSetupStatus {
    [CmdletBinding()]
    param(
        [string]$TenantId, [string]$SubscriptionId, [string]$OperatorObjectId,
        [string]$Hostname, [string]$StaticWebAppHostname, [string]$ResourceGroup, [string]$KeyVaultName,
        [string]$AuthorityId, [string]$ContractId, [Security.SecureString]$AdminAccessToken
    )
    $now = [DateTimeOffset]::UtcNow
    $gates = [Collections.Generic.List[object]]::new()
    function Add-Gate([string]$Name, [string]$State, [string]$Action) {
        $gates.Add([ordered]@{ name = $Name; state = $State; nextStep = $Action })
    }
    $contextValid = $true
    foreach ($id in @($TenantId, $SubscriptionId, $OperatorObjectId)) {
        $parsed = [guid]::Empty
        if (-not [guid]::TryParse($id, [ref]$parsed) -or $parsed -eq [guid]::Empty) { $contextValid = $false }
    }
    $hostValid = Test-VidStatusHost $Hostname
    if (-not $hostValid -or -not (Test-VidStatusHost $StaticWebAppHostname) -or $StaticWebAppHostname -notmatch '\.azurestaticapps\.net$' -or $ResourceGroup -notmatch '^[a-zA-Z0-9_.()-]{1,90}$' -or $KeyVaultName -notmatch '^[a-zA-Z][a-zA-Z0-9-]{1,22}[a-zA-Z0-9]$') { $contextValid = $false }
    foreach ($id in @($AuthorityId, $ContractId)) { if ($id -and $id -notmatch '^[a-zA-Z0-9-]{1,128}$') { $contextValid = $false } }
    if ($contextValid) { Add-Gate 'context' 'Ready' 'Selected target context is syntactically valid; it is not authenticated by local values.' }
    else { Add-Gate 'context' 'Pending' 'Supply the selected tenant, subscription, operator object ID, domain, Static Web App hostname, resource group and vault; identifiers must be valid.' }

    if ($contextValid) {
        $Hostname = $Hostname.ToLowerInvariant()
        $did = "did:web:$Hostname"
        try {
            $aliases = @(Get-VidStatusCname $Hostname)
            if ($StaticWebAppHostname.ToLowerInvariant() -in $aliases) { Add-Gate 'dns' 'Ready' 'The observed CNAME targets the selected Static Web App.' }
            else { Add-Gate 'dns' 'Pending' 'An authorized DNS operator must publish the CNAME for the selected domain and wait for propagation.' }
        } catch { Add-Gate 'dns' 'Pending' 'DNS lookup failed; check propagation and local resolver access before retrying.' }
        try {
            $doc = Invoke-VidStatusGet -Uri "https://$Hostname/.well-known/did.json" -PublicHostname $Hostname
            if ($doc.id -eq $did -and @($doc.verificationMethod).Count -gt 0) { Add-Gate 'did-document' 'Observed' 'Matching public DID document observed over HTTPS; signing keys and cryptographic validity are not verified by this status command.' }
            else { Add-Gate 'did-document' 'Pending' 'Publish the matching DID document using the separately authorized setup workflow.' }
        } catch { Add-Gate 'did-document' 'Pending' 'The expected HTTPS DID document is unavailable or malformed; check domain binding and public publication.' }
        try {
            $doc = Invoke-VidStatusGet -Uri "https://$Hostname/.well-known/did-configuration.json" -PublicHostname $Hostname
            $matching = $false
            foreach ($credential in @($doc.linked_dids)) {
                if ($credential -isnot [string]) { continue }
                try {
                    $claims = ConvertFrom-VidStatusJwt $credential
                    $subject = $claims.vc.credentialSubject
                    if ($claims.iss -eq $did -and $claims.sub -eq $did -and 'DomainLinkageCredential' -in @($claims.vc.type) -and $subject.id -eq $did -and $subject.origin -eq "https://$Hostname" -and $claims.exp -is [ValueType] -and [long]$claims.exp -gt $now.ToUnixTimeSeconds() -and $claims.nbf -is [ValueType] -and [long]$claims.nbf -le $now.ToUnixTimeSeconds()) { $matching = $true }
                } catch { }
            }
            if (@($doc.'@context') -contains 'https://identity.foundation/.well-known/did-configuration/v1' -and $matching) { Add-Gate 'domain-link-document' 'Observed' 'Matching unexpired unsigned decoded Domain Linkage claims observed; only fresh service verification below establishes service readiness.' }
            else { Add-Gate 'domain-link-document' 'Pending' 'Publish a current matching Domain Linkage credential; unsupported proof formats require independent verification.' }
        } catch { Add-Gate 'domain-link-document' 'Pending' 'The public domain-link document is unavailable or malformed; publish it through the separately authorized workflow.' }
    } else {
        foreach ($gate in @('dns', 'did-document', 'domain-link-document')) { Add-Gate $gate 'Pending' 'Complete selected target context before network observation.' }
    }

    $tokenValid = $false
    if ($contextValid -and $AdminAccessToken) {
        try {
            $plain = [Net.NetworkCredential]::new('', $AdminAccessToken).Password
            $claims = ConvertFrom-VidStatusJwt $plain
            $tokenValid = $claims.tid -eq $TenantId -and $claims.oid -eq $OperatorObjectId -and $claims.aud -eq '6a8b4b39-c021-437c-b060-5a14a3fd65f3' -and 'full_access' -cin @($claims.scp -split ' ') -and $claims.exp -is [ValueType] -and [long]$claims.exp -gt $now.ToUnixTimeSeconds() -and $claims.nbf -is [ValueType] -and [long]$claims.nbf -le $now.ToUnixTimeSeconds() -and $claims.iss -in @("https://sts.windows.net/$TenantId/", "https://login.microsoftonline.com/$TenantId/v2.0")
        } catch { $tokenValid = $false }
        finally { $plain = $null; $claims = $null }
    }
    if ($tokenValid) { Add-Gate 'admin-access' 'Observed' 'Unsigned decoded claims match the selected routing context; the admin service must authenticate each GET.' }
    else { Add-Gate 'admin-access' 'Pending' 'Supply an existing unexpired delegated Verified ID admin token for the selected tenant/operator with full_access. This command does not authenticate, consent or create a bootstrap application.' }

    $authority = $null
    $contract = $null
    if ($tokenValid) {
        try {
            $response = Invoke-VidStatusGet -Uri 'https://verifiedid.did.msidentity.com/v1.0/verifiableCredentials/authorities' -AdminAccessToken $AdminAccessToken
            $all = if ($response -is [array]) { $response } else { $response.value }
            $candidates = @($all | Where-Object { $_.didModel.did -eq $did -and "https://$Hostname" -in @($_.didModel.linkedDomainUrls | ForEach-Object { $_.TrimEnd('/') }) -and (-not $AuthorityId -or $_.id -eq $AuthorityId) })
            if ($candidates.Count -eq 1) {
                $candidate = $candidates[0]
                $vault = $candidate.keyVaultMetadata
                if ($candidate.id -match '^[a-zA-Z0-9-]{1,128}$' -and $vault.subscriptionId -eq $SubscriptionId -and $vault.resourceGroup -eq $ResourceGroup -and $vault.resourceName -eq $KeyVaultName) { $authority = $candidate }
            }
            if ($authority) { Add-Gate 'authority' 'Ready' 'Fresh service response identifies one authority bound to the selected DID, domain and vault target.' }
            else { Add-Gate 'authority' 'Pending' 'No unique matching authority/vault binding was observed; reconcile the selected authority before any separately authorized writes.' }
        } catch { Add-Gate 'authority' 'Pending' 'The admin authority GET was denied, unavailable or malformed; verify the existing operator authorization and target.' }
    } else { Add-Gate 'authority' 'Pending' 'Provide matching admin access to observe the selected authority.' }
    $serviceDomainReady = $false
    try { $serviceDomainReady = $authority -and $authority.didModel.didDocumentStatus -eq 'published' -and $authority.linkedDomainsVerified -is [bool] -and $authority.linkedDomainsVerified } catch { }
    if ($serviceDomainReady) { Add-Gate 'service-domain-verification' 'Ready' 'Fresh authority GET reports a published DID and verified linked domains.' }
    else { Add-Gate 'service-domain-verification' 'Pending' 'An authorized operator must finish service domain verification; this command never invokes document generation or verification POSTs.' }

    if ($authority) {
        try {
            $path = "/v1.0/verifiableCredentials/authorities/$($authority.id)/contracts"
            if ($ContractId) { $path += "/$ContractId" }
            $response = Invoke-VidStatusGet -Uri "https://verifiedid.did.msidentity.com$path" -AdminAccessToken $AdminAccessToken
            $all = if ($ContractId) { @($response) } elseif ($response -is [array]) { $response } else { $response.value }
            $candidates = @($all | Where-Object {
                # Get-contract can omit authorityId. A present binding must
                # agree with the selected authority, including list responses.
                $binding = $_.PSObject.Properties['authorityId']
                'VerifiedEmployee' -in @($_.rules.vc.type) -and (-not $ContractId -or $_.id -eq $ContractId) -and
                    ($null -eq $binding -or ($binding.Value -is [string] -and $binding.Value -ceq $authority.id))
            })
            if ($candidates.Count -eq 1 -and $candidates[0].id -match '^[a-zA-Z0-9-]{1,128}$') { $contract = $candidates[0] }
            if ($contract) { Add-Gate 'credential-contract' 'Ready' 'Fresh selected-authority contract GET identifies one VerifiedEmployee contract; issuance remains a separate trial.' }
            else { Add-Gate 'credential-contract' 'Pending' 'Reconcile or create the selected VerifiedEmployee contract through the separately authorized setup workflow.' }
        } catch { Add-Gate 'credential-contract' 'Pending' 'The contract GET was denied, unavailable or malformed; check the selected contract and authorization.' }
    } else { Add-Gate 'credential-contract' 'Pending' 'Observe the unique selected authority before checking its contract.' }
    if ($contract) {
        try {
            $settings = Invoke-VidStatusGet -Uri 'https://verifiedid.did.msidentity.com/v1.0/verifiableCredentials/organizationSettings/myAccount' -AdminAccessToken $AdminAccessToken
            if ($contract.id -in @($settings.contractIdsEnabled)) { Add-Gate 'myaccount' 'Ready' 'Fresh service settings enable the selected contract for MyAccount.' }
            else { Add-Gate 'myaccount' 'Pending' 'An authorized operator must enable the selected contract in MyAccount.' }
        } catch { Add-Gate 'myaccount' 'Pending' 'MyAccount settings could not be observed; check authorization and retry.' }
    } else { Add-Gate 'myaccount' 'Pending' 'Resolve the selected credential contract before observing MyAccount enablement.' }
    Add-Gate 'issuance' 'Pending' 'VID-002 requires an authorized real credential issuance trial; configuration observations do not prove issuance.'
    Add-Gate 'presentation' 'Pending' 'VID-002 requires a real presentation trial with the selected credential and verifier.'
    [ordered]@{
        schemaVersion = '1.0'; reportType = 'verifiedIdSetupStatus'; observedAt = $now.ToString('o')
        configurationReady = @($gates | Where-Object { $_.name -notin @('issuance', 'presentation') -and $_.state -eq 'Pending' }).Count -eq 0
        gates = @($gates.ToArray())
    }
}

Export-ModuleMember -Function Get-VerifiedIdSetupStatus
