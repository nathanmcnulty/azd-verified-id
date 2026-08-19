[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'VerifiedId.psm1') -Force -DisableNameChecking

Import-VidAzdEnvironment
Initialize-VidEnvironmentDefaults
