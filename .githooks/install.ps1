[CmdletBinding()]
param([switch]$Check)

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Output '실패: git 이 없다'
    return
}

$repoRoot = Split-Path -Path $PSScriptRoot -Parent

$current = & git -C $repoRoot config --local --get core.hooksPath 2>$null
$getExit = $LASTEXITCODE

if ($getExit -ne 0 -and $getExit -ne 1) {
    Write-Output "실패: git config 종료 코드 $getExit"
    return
}

$hasValue = ($getExit -eq 0)
$currentValue = if ($hasValue) { ($current -join "`n").Trim() } else { '' }

if ($hasValue -and ($currentValue -ceq '.githooks')) {
    Write-Output '그대로'
    return
}

if ($Check) {
    if (-not $hasValue) {
        Write-Output '다름 (없음)'
    } else {
        Write-Output '다름 (.githooks 가 아니다)'
    }
    return
}

& git -C $repoRoot config --local core.hooksPath .githooks 2>$null | Out-Null
$setExit = $LASTEXITCODE
if ($setExit -eq 0) {
    Write-Output '바꿈'
} else {
    Write-Output "실패: git config 종료 코드 $setExit"
}
