[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path $PSScriptRoot -Parent

Write-Host 'Validating PowerShell syntax...'
$syntaxErrors = @()
Get-ChildItem -LiteralPath $repositoryRoot -Recurse -File -Include '*.ps1', '*.psm1' | ForEach-Object {
    $tokens = $null
    $parserErrors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$parserErrors)
    foreach ($parserError in @($parserErrors)) {
        $syntaxErrors += "$($parserError.Extent.File):$($parserError.Extent.StartLineNumber): $($parserError.Message)"
    }
}
if ($syntaxErrors.Count -gt 0) { throw ($syntaxErrors -join [Environment]::NewLine) }

$analyzer = Get-Module -ListAvailable -Name PSScriptAnalyzer | Sort-Object Version -Descending | Select-Object -First 1
if ($null -ne $analyzer) {
    Import-Module $analyzer.Path -Force
    $analysisErrors = @(Invoke-ScriptAnalyzer -Path (Join-Path $repositoryRoot 'scripts') -Recurse -Severity Error)
    if ($analysisErrors.Count -gt 0) {
        $analysisErrors | Format-Table -AutoSize
        throw "$($analysisErrors.Count) PSScriptAnalyzer error(s) found."
    }
}

Write-Host 'Building Bicep...'
& az bicep build --file (Join-Path $repositoryRoot 'infra\main.bicep') --stdout | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Bicep build failed.' }

$pester = Get-Module -ListAvailable -Name Pester | Where-Object { $_.Version -ge [Version]'5.0.0' } | Sort-Object Version -Descending | Select-Object -First 1
if ($null -eq $pester) {
    Write-Warning 'Pester 5 is not installed; unit tests were not run.'
} else {
    Import-Module $pester.Path -Force
    $result = Invoke-Pester -Path (Join-Path $repositoryRoot 'tests') -PassThru
    if ($result.Result -ne 'Passed') { throw "Pester validation failed: $($result.Result)." }
}

Write-Host 'Repository validation passed.' -ForegroundColor Green
