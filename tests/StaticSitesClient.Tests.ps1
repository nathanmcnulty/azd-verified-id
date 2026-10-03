BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../scripts/modules/StaticWebApp.psm1') -Force
}

Describe 'Pinned StaticSitesClient acquisition' {
    It 'selects the reviewed build and hash for each supported platform' {
        $expected = @{
            'win-x64' = '58bc6533b9cbdd1d9564d3f36625308f4b20ec5a0c51b093cb35e4bf61545f82'
            'linux-x64' = 'f1a6771b0b72604fb1ce71c1f2462791394a418fa7c3638d771dbcf16f374687'
            'osx-x64' = 'f2df9be13941c6570f9d16ec1e3c176f2e286c0155272323c0335705beb1e638'
        }
        foreach ($platform in $expected.Keys) {
            $release = Get-VidStaticSitesClientRelease -Platform $platform
            $release.buildId | Should -BeExactly '689a6c1fe8fc32f40348cc41223a7e9d83dd43d2'
            $release.sha | Should -BeExactly $expected[$platform]
            $release.url | Should -Match "/downloads/$($release.buildId)/"
        }
    }

    It 'rejects an unsupported platform before attempting a download' {
        Mock Invoke-WebRequest { throw 'Network must not be used.' } -ModuleName StaticWebApp
        { Get-VidStaticSitesClient -Platform 'linux-arm64' -CacheRoot (Join-Path $TestDrive 'unsupported') } |
            Should -Throw "*No pinned StaticSitesClient binary for 'linux-arm64'*"
        Should -Invoke Invoke-WebRequest -ModuleName StaticWebApp -Times 0
    }

    It 'uses a cached binary only when its hash matches the lock' {
        $release = Get-VidStaticSitesClientRelease -Platform 'win-x64'
        $cacheRoot = Join-Path $TestDrive 'valid-cache'
        $releaseRoot = Join-Path $cacheRoot $release.buildId
        [IO.Directory]::CreateDirectory($releaseRoot) | Out-Null
        $binaryPath = Join-Path $releaseRoot 'StaticSitesClient.exe'
        'test cache bytes' | Set-Content -LiteralPath $binaryPath
        Mock Get-FileHash { [pscustomobject]@{ Hash = '58bc6533b9cbdd1d9564d3f36625308f4b20ec5a0c51b093cb35e4bf61545f82' } } -ModuleName StaticWebApp
        Mock Invoke-WebRequest { throw 'Network must not be used for a matching cache entry.' } -ModuleName StaticWebApp

        (Get-VidStaticSitesClient -Platform 'win-x64' -CacheRoot $cacheRoot) | Should -BeExactly $binaryPath
        Should -Invoke Invoke-WebRequest -ModuleName StaticWebApp -Times 0
    }

    It 'rejects a corrupt cached binary and a corrupt replacement without returning an executable' {
        $release = Get-VidStaticSitesClientRelease -Platform 'win-x64'
        $cacheRoot = Join-Path $TestDrive 'corrupt-cache'
        $releaseRoot = Join-Path $cacheRoot $release.buildId
        [IO.Directory]::CreateDirectory($releaseRoot) | Out-Null
        $binaryPath = Join-Path $releaseRoot 'StaticSitesClient.exe'
        'old bytes' | Set-Content -LiteralPath $binaryPath
        Mock Invoke-WebRequest {
            param($Uri, $OutFile)
            'new untrusted bytes' | Set-Content -LiteralPath $OutFile
        } -ModuleName StaticWebApp

        { Get-VidStaticSitesClient -Platform 'win-x64' -CacheRoot $cacheRoot } | Should -Throw '*checksum validation failed*'
        Should -Invoke Invoke-WebRequest -ModuleName StaticWebApp -Times 1
        Test-Path -LiteralPath $binaryPath | Should -BeFalse
    }
}
