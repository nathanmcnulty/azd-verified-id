BeforeAll { $repository = Split-Path $PSScriptRoot -Parent }
Describe 'Source-backed partial permission manifest' {
    It 'matches the immutable canonical schema and keeps unknown permission requirements as gaps' {
        $manifestPath = Join-Path $repository 'azd-permissions.json'
        Test-Json -LiteralPath $manifestPath -SchemaFile (Join-Path $repository 'schemas/permission-requirements.schema.json') -ErrorAction Stop | Should -BeTrue
        $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
        $manifest.coverage | Should -Be 'partial'
        @($manifest.gaps).Count | Should -BeGreaterThan 0
        foreach ($requirement in $manifest.requirements) {
            foreach ($evidence in $requirement.evidence) {
                (Get-FileHash -LiteralPath (Join-Path $repository $evidence.path) -Algorithm SHA256).Hash.ToLowerInvariant() | Should -Be $evidence.sha256
            }
        }
        @($manifest.requirements | Where-Object feature -eq 'read-only-status').Count | Should -Be 1
    }
}
