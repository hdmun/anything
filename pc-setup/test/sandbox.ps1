#Requires -Version 7
[CmdletBinding()]
param(
    [string[]]$Skip = @(),
    [int]$TimeoutMinutes = 90
)

if (-not (Get-Module -Name 'SandboxHost')) {
    Import-Module (Join-Path $PSScriptRoot 'SandboxHost.psm1')
}

$normalizedSkip = @(
    foreach ($item in $Skip) {
        foreach ($part in ($item -split ',')) {
            $trimmed = $part.Trim()
            if ($trimmed -ne '') {
                $trimmed
            }
        }
    }
)

$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$exitCode = Invoke-SandboxHarness -RepoRoot $repoRoot -Skip $normalizedSkip -TimeoutMinutes $TimeoutMinutes
exit $exitCode
