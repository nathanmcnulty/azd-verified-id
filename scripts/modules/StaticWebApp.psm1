Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:StaticWebAppApiVersion = '2024-11-01'

function Get-VidStaticSitesClientPlatform {
    if ($IsWindows) { return 'win-x64' }
    if ($IsLinux -and [Runtime.InteropServices.RuntimeInformation]::OSArchitecture -eq 'X64') { return 'linux-x64' }
    if ($IsMacOS -and [Runtime.InteropServices.RuntimeInformation]::OSArchitecture -eq 'X64') { return 'osx-x64' }
    throw 'Static Web Apps deployment currently requires an x64 Windows, Linux, or macOS host.'
}

function Get-VidStaticSitesClient {
    $platform = Get-VidStaticSitesClientPlatform
    $metadata = Invoke-RestMethod -Method GET -Uri 'https://aka.ms/swalocaldeploy' -ErrorAction Stop
    $release = @($metadata | Where-Object { $_.version -eq 'stable' })[0]
    if ($null -eq $release) { throw 'StaticSitesClient stable release metadata was not returned.' }
    $file = $release.files.$platform
    if ([string]::IsNullOrWhiteSpace($file.url) -or [string]::IsNullOrWhiteSpace($file.sha)) {
        throw "StaticSitesClient metadata does not include '$platform'."
    }

    $cacheRoot = Join-Path $HOME '.verifiedid-tools/StaticSitesClient'
    $releaseRoot = Join-Path $cacheRoot $release.buildId
    [IO.Directory]::CreateDirectory($releaseRoot) | Out-Null
    $binaryPath = Join-Path $releaseRoot ([IO.Path]::GetFileName(([Uri]$file.url).LocalPath))
    $download = -not (Test-Path -LiteralPath $binaryPath -PathType Leaf)
    if (-not $download) {
        $download = (Get-FileHash -LiteralPath $binaryPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $file.sha.ToLowerInvariant()
    }
    if ($download) {
        Invoke-WebRequest -Uri $file.url -OutFile $binaryPath -ErrorAction Stop
        $hash = (Get-FileHash -LiteralPath $binaryPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($hash -ne $file.sha.ToLowerInvariant()) {
            Remove-Item -LiteralPath $binaryPath -Force -ErrorAction SilentlyContinue
            throw 'StaticSitesClient checksum validation failed.'
        }
        if (-not $IsWindows) { & chmod +x $binaryPath }
    }
    return $binaryPath
}

function New-VidStaticWebAppContent {
    param(
        [Parameter(Mandatory)][object]$Documents,
        [Parameter(Mandatory)][string]$AuthorityId
    )

    $root = Join-Path ([IO.Path]::GetTempPath()) "azd-verified-id-$AuthorityId-$([guid]::NewGuid().ToString('N'))"
    $wellKnown = Join-Path $root '.well-known'
    [IO.Directory]::CreateDirectory($wellKnown) | Out-Null
    $jsonOptions = @{ Depth = 50 }
    $Documents.DidDocument | ConvertTo-Json @jsonOptions | Set-Content -LiteralPath (Join-Path $wellKnown 'did.json') -Encoding utf8NoBOM
    $Documents.DidConfiguration | ConvertTo-Json @jsonOptions | Set-Content -LiteralPath (Join-Path $wellKnown 'did-configuration.json') -Encoding utf8NoBOM
    '<!doctype html><html lang="en"><head><meta charset="utf-8"><title>Verified ID</title></head><body><p>Verified ID well-known endpoints.</p></body></html>' |
        Set-Content -LiteralPath (Join-Path $root 'index.html') -Encoding utf8NoBOM
    'Not found' | Set-Content -LiteralPath (Join-Path $root '404.html') -Encoding utf8NoBOM
    @{
        globalHeaders = @{
            'X-Content-Type-Options' = 'nosniff'
            'Referrer-Policy' = 'no-referrer'
            'Content-Security-Policy' = "default-src 'none'; frame-ancestors 'none'"
        }
        routes = @(
            @{ route = '/.well-known/did.json'; headers = @{ 'Content-Type' = 'application/json; charset=utf-8'; 'Cache-Control' = 'no-cache' } },
            @{ route = '/.well-known/did-configuration.json'; headers = @{ 'Content-Type' = 'application/json; charset=utf-8'; 'Cache-Control' = 'no-cache' } }
        )
    } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $root 'staticwebapp.config.json') -Encoding utf8NoBOM
    return $root
}

function Get-VidStaticWebAppDeploymentToken {
    param(
        [Parameter(Mandatory)][string]$SubscriptionId,
        [Parameter(Mandatory)][string]$ResourceGroupName,
        [Parameter(Mandatory)][string]$StaticWebAppName
    )

    $uri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Web/staticSites/$StaticWebAppName/listSecrets?api-version=$($script:StaticWebAppApiVersion)"
    $output = & az rest --method post --url $uri --output json 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Unable to retrieve the Static Web App deployment token: $($output -join ' ')" }
    $token = ($output | ConvertFrom-Json).properties.apiKey
    if ([string]::IsNullOrWhiteSpace($token)) { throw 'Static Web App did not return a deployment token.' }
    return $token
}

function Publish-VidStaticWebAppContent {
    param(
        [Parameter(Mandatory)][string]$ContentRoot,
        [Parameter(Mandatory)][string]$DeploymentToken
    )

    $client = Get-VidStaticSitesClient
    $variables = @{
        DEPLOYMENT_ACTION = 'upload'
        DEPLOYMENT_PROVIDER = 'azd-verified-id'
        SKIP_APP_BUILD = 'true'
        SKIP_API_BUILD = 'true'
        DEPLOYMENT_TOKEN = $DeploymentToken
        APP_LOCATION = $ContentRoot
        VERBOSE = 'false'
    }
    $previous = @{}
    foreach ($entry in $variables.GetEnumerator()) {
        $previous[$entry.Key] = [Environment]::GetEnvironmentVariable($entry.Key, 'Process')
        [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, 'Process')
    }
    try {
        $output = & $client 2>&1
        if ($LASTEXITCODE -ne 0) { throw "Static Web App deployment failed: $($output -join [Environment]::NewLine)" }
    } finally {
        foreach ($entry in $previous.GetEnumerator()) {
            [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, 'Process')
        }
    }
}

function Get-VidStaticWebAppCustomDomain {
    param(
        [Parameter(Mandatory)][string]$SubscriptionId,
        [Parameter(Mandatory)][string]$ResourceGroupName,
        [Parameter(Mandatory)][string]$StaticWebAppName,
        [Parameter(Mandatory)][string]$Hostname
    )

    $uri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Web/staticSites/$StaticWebAppName/customDomains/${Hostname}?api-version=$($script:StaticWebAppApiVersion)"
    $output = & az rest --method get --url $uri --output json 2>&1
    if ($LASTEXITCODE -eq 0) { return $output | ConvertFrom-Json }
    if (($output -join ' ') -match 'NotFound|ResourceNotFound|404') { return $null }
    throw "Unable to read Static Web App custom domain '$Hostname': $($output -join ' ')"
}

function Request-VidStaticWebAppCustomDomain {
    param(
        [Parameter(Mandatory)][string]$SubscriptionId,
        [Parameter(Mandatory)][string]$ResourceGroupName,
        [Parameter(Mandatory)][string]$StaticWebAppName,
        [Parameter(Mandatory)][string]$Hostname
    )

    $baseUri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Web/staticSites/$StaticWebAppName/customDomains/$Hostname"
    $bodyPath = [IO.Path]::GetTempFileName()
    try {
        @{ properties = @{ validationMethod = 'dns-txt-token' } } | ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath $bodyPath -Encoding utf8NoBOM
        $output = & az rest --method put --url "${baseUri}?api-version=$($script:StaticWebAppApiVersion)" --body "@$bodyPath" --output json 2>&1
        if ($LASTEXITCODE -ne 0 -and ($output -join ' ') -notmatch 'Conflict|already exists') {
            throw "Unable to request custom domain '$Hostname': $($output -join ' ')"
        }
    } finally {
        Remove-Item -LiteralPath $bodyPath -Force -ErrorAction SilentlyContinue
    }

    for ($attempt = 1; $attempt -le 12; $attempt++) {
        $domain = Get-VidStaticWebAppCustomDomain -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName `
            -StaticWebAppName $StaticWebAppName -Hostname $Hostname
        $domainProperties = Get-VidObjectProperty -InputObject $domain -Name 'properties'
        $validationToken = Get-VidObjectProperty -InputObject $domainProperties -Name 'validationToken' -Default ''
        $status = Get-VidObjectProperty -InputObject $domainProperties -Name 'status' -Default ''
        if ($null -ne $domain -and ($validationToken -or $status -in @('Ready', 'Failed', 'Unhealthy'))) {
            return $domain
        }
        Start-Sleep -Seconds 5
    }
    return Get-VidStaticWebAppCustomDomain -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName `
        -StaticWebAppName $StaticWebAppName -Hostname $Hostname
}

function Invoke-VidStaticWebAppCustomDomainValidation {
    param(
        [Parameter(Mandatory)][string]$SubscriptionId,
        [Parameter(Mandatory)][string]$ResourceGroupName,
        [Parameter(Mandatory)][string]$StaticWebAppName,
        [Parameter(Mandatory)][string]$Hostname
    )

    $uri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Web/staticSites/$StaticWebAppName/customDomains/$Hostname/validate?api-version=$($script:StaticWebAppApiVersion)"
    $bodyPath = [IO.Path]::GetTempFileName()
    try {
        @{ properties = @{ validationMethod = 'dns-txt-token' } } | ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath $bodyPath -Encoding utf8NoBOM
        $output = & az rest --method post --url $uri --body "@$bodyPath" --output none 2>&1
        if ($LASTEXITCODE -ne 0) {
            $detail = $output -join ' '
            if ($detail -notmatch 'CNAME Record is invalid|TXT Record is invalid|validation token|Cannot find Hostname') {
                throw "Unable to validate custom domain '$Hostname': $detail"
            }
            Write-Verbose $detail
        }
    } finally {
        Remove-Item -LiteralPath $bodyPath -Force -ErrorAction SilentlyContinue
    }
}

function Test-VidHttpsJsonDocument {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][ValidateSet('did', 'configuration')][string]$Kind,
        [Parameter(Mandatory)][string]$ExpectedDid
    )

    try {
        $response = Invoke-WebRequest -Uri $Uri -Method GET -MaximumRedirection 0 -ErrorAction Stop
        if ([int]$response.StatusCode -ne 200) { return $false }
        $document = $response.Content | ConvertFrom-Json -Depth 50
        if ($Kind -eq 'did') { return $document.id -eq $ExpectedDid }
        return @($document.linked_dids).Count -gt 0
    } catch {
        return $false
    }
}

function Deploy-VidDocumentsAndDomain {
    param(
        [Parameter(Mandatory)][object]$Documents,
        [Parameter(Mandatory)][string]$AuthorityId,
        [Parameter(Mandatory)][string]$ExpectedDid,
        [Parameter(Mandatory)][string]$SubscriptionId,
        [Parameter(Mandatory)][string]$ResourceGroupName,
        [Parameter(Mandatory)][string]$StaticWebAppName,
        [Parameter(Mandatory)][string]$StaticWebAppHostname,
        [Parameter(Mandatory)][string]$Hostname
    )

    $contentRoot = New-VidStaticWebAppContent -Documents $Documents -AuthorityId $AuthorityId
    try {
        $deploymentToken = Get-VidStaticWebAppDeploymentToken -SubscriptionId $SubscriptionId `
            -ResourceGroupName $ResourceGroupName -StaticWebAppName $StaticWebAppName
        Publish-VidStaticWebAppContent -ContentRoot $contentRoot -DeploymentToken $deploymentToken
    } finally {
        $deploymentToken = $null
        Remove-Item -LiteralPath $contentRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    $defaultDidUri = "https://$StaticWebAppHostname/.well-known/did.json"
    if (-not (Test-VidHttpsJsonDocument -Uri $defaultDidUri -Kind did -ExpectedDid $ExpectedDid)) {
        throw "DID document was not valid at the Static Web App default hostname: $defaultDidUri"
    }

    $customDomain = Get-VidStaticWebAppCustomDomain -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName `
        -StaticWebAppName $StaticWebAppName -Hostname $Hostname
    $customDomainProperties = Get-VidObjectProperty -InputObject $customDomain -Name 'properties'
    $customDomainStatus = Get-VidObjectProperty -InputObject $customDomainProperties -Name 'status' -Default ''
    if ($null -eq $customDomain -or $customDomainStatus -notin @('Ready', 'Adding', 'Validating', 'RetrievingValidationToken')) {
        $customDomain = Request-VidStaticWebAppCustomDomain -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName `
            -StaticWebAppName $StaticWebAppName -Hostname $Hostname
    }

    $customDomainProperties = Get-VidObjectProperty -InputObject $customDomain -Name 'properties'
    $status = [string](Get-VidObjectProperty -InputObject $customDomainProperties -Name 'status' -Default 'RetrievingValidationToken')
    $validationToken = [string](Get-VidObjectProperty -InputObject $customDomainProperties -Name 'validationToken' -Default '')
    $txtName = "_dnsauth.$Hostname"
    Set-VidEnvironmentValue -Name 'VERIFIED_ID_DNS_TXT_NAME' -Value $txtName
    if (-not [string]::IsNullOrWhiteSpace($validationToken)) {
        Set-VidEnvironmentValue -Name 'VERIFIED_ID_DNS_TXT_VALUE' -Value $validationToken
    }
    Set-VidEnvironmentValue -Name 'VERIFIED_ID_DNS_CNAME_TARGET' -Value $StaticWebAppHostname
    Set-VidEnvironmentValue -Name 'VERIFIED_ID_CUSTOM_DOMAIN_STATUS' -Value $status

    if ($status -ne 'Ready') {
        Invoke-VidStaticWebAppCustomDomainValidation -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName `
            -StaticWebAppName $StaticWebAppName -Hostname $Hostname
        for ($attempt = 1; $attempt -le 60; $attempt++) {
            $customDomain = Get-VidStaticWebAppCustomDomain -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName `
                -StaticWebAppName $StaticWebAppName -Hostname $Hostname
            $customDomainProperties = Get-VidObjectProperty -InputObject $customDomain -Name 'properties'
            $status = [string](Get-VidObjectProperty -InputObject $customDomainProperties -Name 'status' -Default 'Validating')
            Set-VidEnvironmentValue -Name 'VERIFIED_ID_CUSTOM_DOMAIN_STATUS' -Value $status
            if ($status -eq 'Ready') { break }
            if ($status -in @('Failed', 'Unhealthy')) { throw "Static Web App custom domain validation failed with status '$status'." }
            if ($attempt -lt 60) { Start-Sleep -Seconds 5 }
        }
        if ($status -ne 'Ready') {
            Write-Warning "Static Web App custom domain '$Hostname' is '$status'."
            Write-Host "  Create/retain TXT: $txtName = $validationToken"
            Write-Host "  Set CNAME:         $Hostname -> $StaticWebAppHostname"
            Write-Host '  Then rerun azd hooks run postprovision. The hook will resume from the current state.'
            return [pscustomobject]@{ Ready = $false; Status = $status }
        }
    }

    $didUri = "https://$Hostname/.well-known/did.json"
    $configurationUri = "https://$Hostname/.well-known/did-configuration.json"
    $ready = $false
    for ($attempt = 1; $attempt -le 12; $attempt++) {
        $ready = (Test-VidHttpsJsonDocument -Uri $didUri -Kind did -ExpectedDid $ExpectedDid) -and
            (Test-VidHttpsJsonDocument -Uri $configurationUri -Kind configuration -ExpectedDid $ExpectedDid)
        if ($ready) { break }
        Start-Sleep -Seconds 5
    }
    if (-not $ready) {
        Write-Warning 'Custom domain is bound, but the public DID documents or TLS are still propagating. Rerun azd provision.'
        return [pscustomobject]@{ Ready = $false; Status = 'AwaitingHttps' }
    }
    return [pscustomobject]@{ Ready = $true; Status = 'Ready' }
}

Export-ModuleMember -Function *-Vid*
