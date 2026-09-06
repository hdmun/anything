#!/usr/bin/env pwsh
# 이 저장소의 skills/ 아래 스킬을 Claude Code 설정 디렉터리로 복사한다.
#
# 심볼릭 링크나 junction이 아니라 복사다. 따라서 스킬을 고칠 때마다
# 이 스크립트를 다시 실행해야 설정 디렉터리에 반영된다.
#
# 주의: 대상에 같은 이름의 스킬 디렉터리가 있으면 통째로 교체한다.
# skills/ 아래 이름이 기존 스킬과 겹치지 않는지 확인할 것.

$ErrorActionPreference = 'Stop'

$src = Join-Path $PSScriptRoot 'skills'
$targets = @(
    (Join-Path $env:USERPROFILE '.claude\skills'),
    (Join-Path $env:USERPROFILE '.claude-max\skills')
)

if (-not (Test-Path $src)) {
    throw "소스 디렉터리가 없습니다: $src"
}

$skills = @(Get-ChildItem -Path $src -Directory)
if ($skills.Count -eq 0) {
    Write-Output "복사할 스킬이 없습니다: $src"
    return
}

foreach ($target in $targets) {
    if (-not (Test-Path $target)) {
        New-Item -ItemType Directory -Path $target -Force | Out-Null
        Write-Output "생성: $target"
    }

    foreach ($skill in $skills) {
        $dest = Join-Path $target $skill.Name
        $action = if (Test-Path $dest) { '교체' } else { '신규' }
        if (Test-Path $dest) {
            Remove-Item -Recurse -Force $dest
        }
        Copy-Item -Recurse -Path $skill.FullName -Destination $dest
        Write-Output ("{0}: {1} -> {2}" -f $action, $skill.Name, $dest)
    }
}
