Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:GraphBaseUri = 'https://graph.microsoft.com/v1.0'
$script:VerifiedIdAdminAppId = '6a8b4b39-c021-437c-b060-5a14a3fd65f3'
$script:VerifiedIdAdminScope = 'full_access'

function Get-VidGraphAccessToken {
    $azdResult = & azd auth token --scope 'https://graph.microsoft.com/.default' --output json 2>$null
    if ($LASTEXITCODE -eq 0) {
        $parsed = $azdResult | ConvertFrom-Json
        if (-not [string]::IsNullOrWhiteSpace($parsed.token)) { return $parsed.token }
    }

    $azResult = & az account get-access-token --resource-type ms-graph --output json 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to acquire a Microsoft Graph token from azd or Azure CLI. $($azResult -join ' ')"
    }
    return ($azResult | ConvertFrom-Json).accessToken
}

function Get-VidJwtPayload {
    param([Parameter(Mandatory)][string]$Token)

    $parts = $Token.Split('.')
    if ($parts.Count -lt 2) { throw 'Access token is not a JWT.' }
    $payload = $parts[1].Replace('-', '+').Replace('_', '/')
    while ($payload.Length % 4) { $payload += '=' }
    return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) | ConvertFrom-Json -Depth 20
}

function Assert-VidGraphBootstrapPermission {
    $token = Get-VidGraphAccessToken
    $payload = Get-VidJwtPayload -Token $token
    if ([string]::IsNullOrWhiteSpace($payload.scp)) {
        throw 'Microsoft Graph bootstrap requires a delegated user token.'
    }
    $scopes = @($payload.scp -split ' ')
    $requiredScopes = @('Application.ReadWrite.All', 'DelegatedPermissionGrant.ReadWrite.All')
    $missing = @($requiredScopes | Where-Object { $_ -notin $scopes })
    if ($missing.Count -gt 0) {
        throw "Microsoft Graph token is missing bootstrap scopes: $($missing -join ', ')."
    }
    $me = Invoke-VidGraphRequest -Method GET -Path '/me?$select=id' -AccessToken $token
    if ([string]::IsNullOrWhiteSpace($me.id)) { throw 'Microsoft Graph /me did not return the signed-in administrator.' }
}

function Invoke-VidGraphRequest {
    param(
        [Parameter(Mandatory)][ValidateSet('GET', 'POST', 'PATCH', 'DELETE')][string]$Method,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$AccessToken,
        [AllowNull()][object]$Body
    )

    $parameters = @{
        Method = $Method
        Uri = "$($script:GraphBaseUri)$Path"
        Headers = @{ Authorization = "Bearer $AccessToken" }
    }
    if ($PSBoundParameters.ContainsKey('Body')) { $parameters.Body = $Body }
    return Invoke-VidRestMethod @parameters
}

function ConvertTo-VidBase64Url {
    param([Parameter(Mandatory)][byte[]]$Bytes)
    return [Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function New-VidPkcePair {
    $verifierBytes = [byte[]]::new(32)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($verifierBytes)
    $verifier = ConvertTo-VidBase64Url -Bytes $verifierBytes
    $challengeBytes = [System.Security.Cryptography.SHA256]::HashData([Text.Encoding]::ASCII.GetBytes($verifier))
    return [pscustomobject]@{
        Verifier = $verifier
        Challenge = ConvertTo-VidBase64Url -Bytes $challengeBytes
    }
}

function New-VidQueryString {
    param([Parameter(Mandatory)][hashtable]$Parameters)
    return ($Parameters.GetEnumerator() | ForEach-Object {
        '{0}={1}' -f [Uri]::EscapeDataString([string]$_.Key), [Uri]::EscapeDataString([string]$_.Value)
    }) -join '&'
}

function Invoke-VidBrowserAuthorization {
    param(
        [Parameter(Mandatory)][string]$TenantId,
        [Parameter(Mandatory)][string]$ClientId,
        [Parameter(Mandatory)][string]$LoginHint
    )

    $portProbe = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
    $portProbe.Start()
    try { $port = ([Net.IPEndPoint]$portProbe.LocalEndpoint).Port } finally { $portProbe.Stop() }

    $redirectUri = "http://localhost:$port/"
    $pkce = New-VidPkcePair
    $state = Get-VidRandomBase64Url -ByteLength 32
    $scope = "$($script:VerifiedIdAdminAppId)/$($script:VerifiedIdAdminScope)"
    $query = New-VidQueryString -Parameters @{
        client_id = $ClientId
        response_type = 'code'
        redirect_uri = $redirectUri
        response_mode = 'query'
        scope = $scope
        code_challenge = $pkce.Challenge
        code_challenge_method = 'S256'
        state = $state
        login_hint = $LoginHint
    }
    $authorizeUri = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/authorize?$query"

    $listener = [Net.HttpListener]::new()
    $listener.Prefixes.Add($redirectUri)
    $listener.Start()
    try {
        Write-VidInfo "Opening a browser for delegated Verified ID administration as $LoginHint."
        Start-Process $authorizeUri | Out-Null
        $contextTask = $listener.GetContextAsync()
        if (-not $contextTask.Wait([TimeSpan]::FromMinutes(10))) {
            throw "Timed out waiting for the Verified ID administrator sign-in. Close the browser tab for temporary application '$ClientId'; the application will now be deleted."
        }

        $context = $contextTask.Result
        $queryParameters = $context.Request.QueryString
        $returnedState = $queryParameters.Get('state')
        $authorizationError = $queryParameters.Get('error')
        $authorizationErrorDescription = $queryParameters.Get('error_description')
        $code = $queryParameters.Get('code')
        $responseText = '<html><body><h2>Verified ID authorization completed.</h2><p>This temporary authorization tab can be closed.</p><script>window.close();</script></body></html>'
        $responseBytes = [Text.Encoding]::UTF8.GetBytes($responseText)
        $context.Response.ContentType = 'text/html; charset=utf-8'
        $context.Response.ContentLength64 = $responseBytes.Length
        $context.Response.OutputStream.Write($responseBytes, 0, $responseBytes.Length)
        $context.Response.Close()

        if ($returnedState -cne $state) { throw 'OAuth state validation failed.' }
        if ($authorizationError) {
            throw "Authorization failed: $authorizationErrorDescription"
        }
        if ([string]::IsNullOrWhiteSpace($code)) { throw 'Authorization response did not contain a code.' }

        $tokenResponse = Invoke-RestMethod -Method POST `
            -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
            -ContentType 'application/x-www-form-urlencoded' `
            -Body @{
                client_id = $ClientId
                grant_type = 'authorization_code'
                code = $code
                redirect_uri = $redirectUri
                code_verifier = $pkce.Verifier
                scope = $scope
            } -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($tokenResponse.access_token)) {
            throw 'Token endpoint did not return an access token.'
        }
        return $tokenResponse.access_token
    } finally {
        if ($listener.IsListening) { $listener.Stop() }
        $listener.Close()
    }
}

function Invoke-VidDeviceAuthorization {
    param(
        [Parameter(Mandatory)][string]$TenantId,
        [Parameter(Mandatory)][string]$ClientId
    )

    $scope = "$($script:VerifiedIdAdminAppId)/$($script:VerifiedIdAdminScope)"
    $deviceResponse = Invoke-RestMethod -Method POST `
        -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/devicecode" `
        -ContentType 'application/x-www-form-urlencoded' `
        -Body @{ client_id = $ClientId; scope = $scope } -ErrorAction Stop
    Write-Host $deviceResponse.message -ForegroundColor Yellow

    $interval = [Math]::Max(5, [int]$deviceResponse.interval)
    $deadline = [DateTimeOffset]::UtcNow.AddSeconds([int]$deviceResponse.expires_in)
    while ([DateTimeOffset]::UtcNow -lt $deadline) {
        Start-Sleep -Seconds $interval
        try {
            $tokenResponse = Invoke-RestMethod -Method POST `
                -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
                -ContentType 'application/x-www-form-urlencoded' `
                -Body @{
                    client_id = $ClientId
                    grant_type = 'urn:ietf:params:oauth:grant-type:device_code'
                    device_code = $deviceResponse.device_code
                } -ErrorAction Stop
            if (-not [string]::IsNullOrWhiteSpace($tokenResponse.access_token)) {
                return $tokenResponse.access_token
            }
        } catch {
            $errorCode = ''
            if ($null -ne $_.ErrorDetails -and -not [string]::IsNullOrWhiteSpace($_.ErrorDetails.Message)) {
                try { $errorCode = ($_.ErrorDetails.Message | ConvertFrom-Json).error } catch { Write-Verbose 'Device-code error response was not JSON.' }
            }
            switch ($errorCode) {
                'authorization_pending' { continue }
                'slow_down' { $interval += 5; continue }
                'authorization_declined' { throw 'The administrator declined device-code authorization.' }
                'expired_token' { throw 'The device code expired before authorization completed.' }
                default { throw }
            }
        }
    }
    throw 'The device code expired before authorization completed.'
}

function New-VidTemporaryAdminApplication {
    param([Parameter(Mandatory)][string]$TenantId)

    $graphToken = Get-VidGraphAccessToken
    $temporary = [ordered]@{
        ApplicationObjectId = ''
        AppId = ''
        ServicePrincipalId = ''
        PermissionGrantId = ''
        AccessToken = ''
        DisplayName = "azd-verified-id-temp-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
    }

    try {
        $me = Invoke-VidGraphRequest -Method GET -Path '/me?$select=id,userPrincipalName' -AccessToken $graphToken
        $filter = [Uri]::EscapeDataString("appId eq '$($script:VerifiedIdAdminAppId)'")
        $resourceResult = Invoke-VidGraphRequest -Method GET -Path "/servicePrincipals?`$filter=$filter&`$select=id,appId,oauth2PermissionScopes" -AccessToken $graphToken
        $resource = @($resourceResult.value)[0]
        if ($null -eq $resource) { throw 'Verifiable Credentials Service Admin service principal was not found.' }
        $scope = @($resource.oauth2PermissionScopes | Where-Object { $_.value -eq $script:VerifiedIdAdminScope -and $_.isEnabled })[0]
        if ($null -eq $scope) { throw "Verified ID delegated scope '$($script:VerifiedIdAdminScope)' was not found." }

        $app = Invoke-VidGraphRequest -Method POST -Path '/applications' -AccessToken $graphToken -Body @{
            displayName = $temporary.DisplayName
            signInAudience = 'AzureADMyOrg'
            publicClient = @{ redirectUris = @('http://localhost') }
        }
        $temporary.ApplicationObjectId = $app.id
        $temporary.AppId = $app.appId
        Set-VidEnvironmentValue -Name 'VERIFIED_ID_TEMP_APPLICATION_OBJECT_ID' -Value $app.id

        $servicePrincipal = $null
        for ($attempt = 1; $attempt -le 12; $attempt++) {
            try {
                $servicePrincipal = Invoke-VidGraphRequest -Method POST -Path '/servicePrincipals' -AccessToken $graphToken -Body @{ appId = $app.appId }
                break
            } catch {
                if ($attempt -ge 12 -or (Get-VidHttpErrorText -ErrorRecord $_) -notmatch 'does not reference a valid application|Request_BadRequest|not found') { throw }
                Start-Sleep -Seconds 5
            }
        }
        if ($null -eq $servicePrincipal -or [string]::IsNullOrWhiteSpace($servicePrincipal.id)) {
            throw 'Temporary service principal did not become available.'
        }
        $temporary.ServicePrincipalId = $servicePrincipal.id
        Set-VidEnvironmentValue -Name 'VERIFIED_ID_TEMP_SERVICE_PRINCIPAL_ID' -Value $servicePrincipal.id

        $grant = Invoke-VidGraphRequest -Method POST -Path '/oauth2PermissionGrants' -AccessToken $graphToken -Body @{
            clientId = $servicePrincipal.id
            consentType = 'Principal'
            principalId = $me.id
            resourceId = $resource.id
            scope = $scope.value
        }
        $temporary.PermissionGrantId = $grant.id
        Set-VidEnvironmentValue -Name 'VERIFIED_ID_TEMP_PERMISSION_GRANT_ID' -Value $grant.id

        if (ConvertTo-VidBoolean -Value $env:AZD_VERIFIED_ID_USE_DEVICE_CODE) {
            $temporary.AccessToken = Invoke-VidDeviceAuthorization -TenantId $TenantId -ClientId $app.appId
        } else {
            $temporary.AccessToken = Invoke-VidBrowserAuthorization -TenantId $TenantId -ClientId $app.appId -LoginHint $me.userPrincipalName
        }
        return [pscustomobject]$temporary
    } catch {
        $failureStack = $_.ScriptStackTrace
        Remove-VidTemporaryAdminApplication -TemporaryApplication ([pscustomobject]$temporary) -SuppressErrors
        $detail = Get-VidHttpErrorText -ErrorRecord $_
        throw "Unable to create the temporary Verified ID administration application. The signed-in Graph token needs Application.ReadWrite.All and DelegatedPermissionGrant.ReadWrite.All. $detail`n$failureStack"
    }
}

function Remove-VidTemporaryAdminApplication {
    param(
        [AllowNull()][object]$TemporaryApplication,
        [switch]$SuppressErrors
    )

    if ($null -eq $TemporaryApplication) { return }
    try {
        $token = Get-VidGraphAccessToken
        foreach ($item in @(
            @{ Id = $TemporaryApplication.PermissionGrantId; Path = '/oauth2PermissionGrants/' },
            @{ Id = $TemporaryApplication.ServicePrincipalId; Path = '/servicePrincipals/' },
            @{ Id = $TemporaryApplication.ApplicationObjectId; Path = '/applications/' }
        )) {
            if ([string]::IsNullOrWhiteSpace($item.Id)) { continue }
            try {
                Invoke-VidGraphRequest -Method DELETE -Path "$($item.Path)$($item.Id)" -AccessToken $token | Out-Null
            } catch {
                if ((Get-VidHttpStatusCode -ErrorRecord $_) -ne 404) { throw }
            }
            for ($attempt = 1; $attempt -le 12; $attempt++) {
                try {
                    Invoke-VidGraphRequest -Method GET -Path "$($item.Path)$($item.Id)?`$select=id" -AccessToken $token | Out-Null
                } catch {
                    if ((Get-VidHttpStatusCode -ErrorRecord $_) -eq 404) { break }
                    throw
                }
                if ($attempt -eq 12) { throw "Temporary Graph object '$($item.Id)' remained visible after deletion." }
                Start-Sleep -Seconds 2
            }
        }
        foreach ($name in @('VERIFIED_ID_TEMP_PERMISSION_GRANT_ID', 'VERIFIED_ID_TEMP_SERVICE_PRINCIPAL_ID', 'VERIFIED_ID_TEMP_APPLICATION_OBJECT_ID')) {
            Set-VidEnvironmentValue -Name $name -Value '' -Force
        }
    } catch {
        if ($SuppressErrors) {
            Write-Warning "Temporary application cleanup requires attention: $($_.Exception.Message)"
            return
        }
        throw
    }
}

function Remove-VidOrphanedAdminApplication {
    $temporary = [pscustomobject]@{
        PermissionGrantId = Get-VidEnvironmentValue -Name 'VERIFIED_ID_TEMP_PERMISSION_GRANT_ID'
        ServicePrincipalId = Get-VidEnvironmentValue -Name 'VERIFIED_ID_TEMP_SERVICE_PRINCIPAL_ID'
        ApplicationObjectId = Get-VidEnvironmentValue -Name 'VERIFIED_ID_TEMP_APPLICATION_OBJECT_ID'
    }
    if ($temporary.PermissionGrantId -or $temporary.ServicePrincipalId -or $temporary.ApplicationObjectId) {
        Write-Warning 'A previous run left temporary Verified ID administration object IDs. Attempting cleanup before continuing.'
        Remove-VidTemporaryAdminApplication -TemporaryApplication $temporary
    }
}

Export-ModuleMember -Function *-Vid*
