Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-VidStep {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host ""
    Write-Host "== $Message ==" -ForegroundColor Cyan
}

function Write-VidInfo {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "  $Message" -ForegroundColor Gray
}

function Write-VidSuccess {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "  [OK] $Message" -ForegroundColor Green
}

function ConvertTo-VidBoolean {
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [object]$Value,
        [bool]$Default = $false
    )

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return $Default
    }

    if ($Value -is [bool]) {
        return $Value
    }

    switch -Regex ([string]$Value) {
        '^(1|true|yes|y|on)$' { return $true }
        '^(0|false|no|n|off)$' { return $false }
        default { throw "Value '$Value' is not a recognized boolean." }
    }
}

function Get-VidSha256Hex {
    param([Parameter(Mandatory)][string]$Value)

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
    $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
    return [Convert]::ToHexString($hash).ToLowerInvariant()
}

function Get-VidRandomBase64Url {
    param([ValidateRange(16, 128)][int]$ByteLength = 32)

    $bytes = [byte[]]::new($ByteLength)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    return [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function ConvertFrom-VidJwtSegment {
    param([Parameter(Mandatory)][string]$Segment)

    $base64 = $Segment.Replace('-', '+').Replace('_', '/')
    while ($base64.Length % 4) { $base64 += '=' }
    try {
        $json = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($base64))
        return $json | ConvertFrom-Json -Depth 50
    } catch {
        throw 'The value was not a valid base64url-encoded JWT JSON segment.'
    }
}

function Normalize-VidHostname {
    param([Parameter(Mandatory)][string]$Value)

    $candidate = $Value.Trim()
    if ($candidate -notmatch '^https?://') {
        $candidate = "https://$candidate"
    }

    $uri = $null
    if (-not [Uri]::TryCreate($candidate, [UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -ne 'https') {
        throw "Verified ID domain must be a valid HTTPS hostname. Received '$Value'."
    }
    if (-not $uri.IsDefaultPort -or -not [string]::IsNullOrEmpty($uri.Query) -or -not [string]::IsNullOrEmpty($uri.Fragment)) {
        throw 'Verified ID domain must not include a port, query, or fragment.'
    }
    if ($uri.AbsolutePath -ne '/') {
        throw 'This template currently supports a did:web hostname without a path.'
    }

    $hostname = $uri.IdnHost.TrimEnd('.').ToLowerInvariant()
    if ($hostname.Length -gt 253 -or $hostname -notmatch '^(?=.{1,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$') {
        throw "'$hostname' is not a valid DNS hostname."
    }

    return $hostname
}

function Get-VidHttpStatusCode {
    param([Parameter(Mandatory)][System.Management.Automation.ErrorRecord]$ErrorRecord)

    try {
        if ($null -ne $ErrorRecord.Exception.Response.StatusCode) {
            return [int]$ErrorRecord.Exception.Response.StatusCode
        }
    } catch {
        return $null
    }
    return $null
}

function Get-VidObjectProperty {
    param(
        [AllowNull()][object]$InputObject,
        [Parameter(Mandatory)][string]$Name,
        [AllowNull()][object]$Default = $null
    )

    if ($null -eq $InputObject) { return $Default }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) { return $Default }
    return $property.Value
}

function Get-VidHttpErrorText {
    param([Parameter(Mandatory)][System.Management.Automation.ErrorRecord]$ErrorRecord)

    if ($null -ne $ErrorRecord.ErrorDetails -and -not [string]::IsNullOrWhiteSpace($ErrorRecord.ErrorDetails.Message)) {
        try {
            $body = $ErrorRecord.ErrorDetails.Message | ConvertFrom-Json -Depth 20
            if ($body.error.code -or $body.error.message) {
                return "$($body.error.code): $($body.error.message)".Trim(': ')
            }
        } catch {
            return $ErrorRecord.ErrorDetails.Message
        }
    }
    return $ErrorRecord.Exception.Message
}

function Invoke-VidRestMethod {
    param(
        [Parameter(Mandatory)][ValidateSet('GET', 'POST', 'PUT', 'PATCH', 'DELETE')][string]$Method,
        [Parameter(Mandatory)][string]$Uri,
        [hashtable]$Headers = @{},
        [AllowNull()][object]$Body,
        [ValidateRange(1, 10)][int]$MaxAttempts = 4,
        [switch]$NoRetry
    )

    $attempt = 0
    while ($true) {
        $attempt++
        try {
            $parameters = @{
                Method = $Method
                Uri = $Uri
                Headers = $Headers
                ErrorAction = 'Stop'
                MaximumRedirection = 0
            }
            if ($PSBoundParameters.ContainsKey('Body') -and $null -ne $Body) {
                $parameters.ContentType = 'application/json'
                $parameters.Body = $Body | ConvertTo-Json -Depth 50 -Compress
            }
            return Invoke-RestMethod @parameters
        } catch {
            $statusCode = Get-VidHttpStatusCode -ErrorRecord $_
            $retryable = $statusCode -in @(408, 429, 500, 502, 503, 504)
            if ($NoRetry -or -not $retryable -or $attempt -ge $MaxAttempts) {
                throw
            }

            $delay = [Math]::Min(30, [Math]::Pow(2, $attempt))
            try {
                $retryAfter = $_.Exception.Response.Headers.RetryAfter.Delta.TotalSeconds
                if ($retryAfter -gt 0) { $delay = [int][Math]::Ceiling($retryAfter) }
            } catch {
                Write-Verbose 'The response did not include a usable Retry-After value.'
            }
            Start-Sleep -Seconds $delay
        }
    }
}

function Confirm-VidAction {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [Parameter(Mandatory)][string]$ExpectedValue,
        [string]$NonInteractiveConfirmationVariable = ''
    )

    $nonInteractive = ConvertTo-VidBoolean -Value $env:AZD_VERIFIED_ID_NON_INTERACTIVE
    if ($nonInteractive) {
        if ([string]::IsNullOrWhiteSpace($NonInteractiveConfirmationVariable)) {
            throw "Noninteractive execution cannot confirm: $Prompt"
        }
        $confirmation = [Environment]::GetEnvironmentVariable($NonInteractiveConfirmationVariable)
        if ($confirmation -cne $ExpectedValue) {
            throw "Set $NonInteractiveConfirmationVariable exactly to '$ExpectedValue' to approve this action."
        }
        return
    }

    $answer = Read-Host "$Prompt Type '$ExpectedValue' to continue"
    if ($answer -cne $ExpectedValue) {
        throw 'Confirmation did not match. No tenant change was made.'
    }
}

Export-ModuleMember -Function *-Vid*
