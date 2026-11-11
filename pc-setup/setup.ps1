#Requires -Version 7
<#
.SYNOPSIS
PC 를 선언된 상태로 맞춘다 (셋업). 지금은 뼈대다: -Check 만 받는다.
#>
[CmdletBinding()]
param(
    [switch]$Check
)

if (-not $Check) {
    Write-Error '셋업은 아직 구현되지 않았다. -Check 만 받는다.'
    exit 1
}

exit 0
