#Requires -Version 7
[CmdletBinding()]
param(
    [switch]$Check,
    [string[]]$Skip = @(),
    [ValidateSet('Elevated')][string]$Phase,
    [string]$ResultPath
)

Import-Module (Join-Path $PSScriptRoot 'lib' 'Setup.psm1') -Force

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

$exitCode = Invoke-Setup -Root $PSScriptRoot -Check:$Check -Skip $normalizedSkip -Phase $Phase -ResultPath ($ResultPath ?? '')
exit $exitCode
