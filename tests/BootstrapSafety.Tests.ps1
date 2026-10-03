BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\scripts\VerifiedId.psm1') -Force -DisableNameChecking
    $preprovisionPath = Join-Path $PSScriptRoot '..\scripts\preprovision.ps1'

    function Invoke-TestPreprovision {
        param([string]$Skip, [string]$OrphanId = '')

        $state = [pscustomobject]@{ GraphPreflightCalls = 0; CleanupCalls = 0 }
        $oldSubscription = $env:AZURE_SUBSCRIPTION_ID
        $oldTenant = $env:AZURE_TENANT_ID
        $env:AZURE_SUBSCRIPTION_ID = '11111111-1111-1111-1111-111111111111'
        $env:AZURE_TENANT_ID = '22222222-2222-2222-2222-222222222222'
        try {
            & {
                param($path, $skipValue, $recordedId, $runState)
                function Import-Module {}
                function Import-VidAzdEnvironment {}
                function Initialize-VidEnvironmentDefaults {}
                function Normalize-VidHostname { param($Value) $Value }
                function Set-VidEnvironmentValue {}
                function ConvertTo-VidBoolean { param($Value) $Value -eq 'true' }
                function Get-VidEnvironmentValue {
                    param($Name, $Default, [switch]$Required)
                    switch ($Name) {
                        VERIFIED_ID_DOMAIN { 'did.example.test' }
                        VERIFIED_ID_KEY_VAULT_SKU { 'standard' }
                        VERIFIED_ID_EMPLOYEE_CARD_BACKGROUND_COLOR { '#000000' }
                        VERIFIED_ID_EMPLOYEE_CARD_TEXT_COLOR { '#FFFFFF' }
                        VERIFIED_ID_SKIP_TENANT_BOOTSTRAP { $skipValue }
                        VERIFIED_ID_TEMP_APPLICATION_OBJECT_ID { $recordedId }
                        VERIFIED_ID_ALLOW_PREMIUM { 'false' }
                        VERIFIED_ID_ENABLE_PURGE_PROTECTION { 'false' }
                        default { '' }
                    }
                }
                function az {
                    $global:LASTEXITCODE = 0
                    '{"id":"11111111-1111-1111-1111-111111111111","tenantId":"22222222-2222-2222-2222-222222222222","environmentName":"AzureCloud","name":"test"}'
                }
                function azd {}
                function Assert-VidGraphBootstrapPermission { $runState.GraphPreflightCalls++ }
                function Remove-VidOrphanedAdminApplication { $runState.CleanupCalls++ }
                function Write-VidStep {}
                function Write-VidInfo {}
                function Write-VidSuccess {}
                & $path
            } $preprovisionPath $Skip $OrphanId $state
        } finally {
            $env:AZURE_SUBSCRIPTION_ID = $oldSubscription
            $env:AZURE_TENANT_ID = $oldTenant
        }
        return $state
    }
}

Describe 'Verified ID tenant bootstrap safety' {
    It 'does not request Graph write scopes or remove old objects in infrastructure-only mode' {
        $state = Invoke-TestPreprovision -Skip 'true' -OrphanId 'old-object-id'
        $state.GraphPreflightCalls | Should -Be 0
        $state.CleanupCalls | Should -Be 0
    }

    It 'blocks a new tenant bootstrap while an orphan ID remains' {
        { Invoke-TestPreprovision -Skip 'false' -OrphanId 'old-object-id' } | Should -Throw '*explicit orphan recovery*'
    }

    It 'checks Graph permissions for a clean tenant bootstrap' {
        $state = Invoke-TestPreprovision -Skip 'false'
        $state.GraphPreflightCalls | Should -Be 1
        $state.CleanupCalls | Should -Be 0
    }

    It 'rejects a Graph token from another tenant' {
        $payload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('{"tid":"33333333-3333-3333-3333-333333333333","oid":"test-user","scp":"Application.ReadWrite.All"}')).TrimEnd('=').Replace('+','-').Replace('/','_')
        $token = "header.$payload.signature"
        { Assert-VidGraphTokenTenant -Token $token -TenantId ([guid]'22222222-2222-2222-2222-222222222222') } | Should -Throw '*tenant*'
    }

    It 'accepts a selected-tenant delegated token and rejects an app-only token' {
        $delegated = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('{"tid":"22222222-2222-2222-2222-222222222222","oid":"test-user","scp":"Application.ReadWrite.All"}')).TrimEnd('=').Replace('+','-').Replace('/','_')
        $appOnly = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('{"tid":"22222222-2222-2222-2222-222222222222","oid":"test-app","roles":["Application.ReadWrite.All"]}')).TrimEnd('=').Replace('+','-').Replace('/','_')
        { Assert-VidGraphTokenTenant -Token "header.$delegated.signature" -TenantId ([guid]'22222222-2222-2222-2222-222222222222') } | Should -Not -Throw
        { Assert-VidGraphTokenTenant -Token "header.$appOnly.signature" -TenantId ([guid]'22222222-2222-2222-2222-222222222222') } | Should -Throw '*delegated*'
    }
}
