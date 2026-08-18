Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$moduleRoot = Join-Path $PSScriptRoot 'modules'
Import-Module (Join-Path $moduleRoot 'Common.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $moduleRoot 'AzdEnvironment.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $moduleRoot 'GraphBootstrap.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $moduleRoot 'VerifiedIdAdmin.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $moduleRoot 'StaticWebApp.psm1') -Force -DisableNameChecking

Export-ModuleMember -Function *
