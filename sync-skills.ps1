#!/usr/bin/env pwsh
# 이 저장소의 skills/ 아래 스킬을 Claude Code 설정 디렉터리로 복사한다.
#
# 심볼릭 링크나 junction 이 아니라 복사다. 따라서 스킬을 고칠 때마다
# 이 스크립트를 다시 실행해야 설정 디렉터리에 반영된다.
#
# 드리프트 감지:
#   설치본을 직접 고치면 다음 동기화에서 그 수정이 조용히 사라진다.
#   이를 막기 위해 동기화할 때마다 각 대상에 .sync-manifest.json 을 남기고,
#   다음 실행에서 설치본이 그 기록과 다르면 덮어쓰지 않고 멈춘다.
#   의도한 덮어쓰기라면 -Force 를 준다.
#
# 사용:
#   ./sync-skills.ps1            # 드리프트가 있으면 멈춤 (종료코드 1)
#   ./sync-skills.ps1 -Force     # 드리프트를 무시하고 덮어씀

[CmdletBinding()]
param(
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$src = Join-Path $PSScriptRoot 'skills'
$targets = @(
    (Join-Path $env:USERPROFILE '.claude\skills'),
    (Join-Path $env:USERPROFILE '.claude-max\skills')
)
$manifestName = '.sync-manifest.json'

if (-not (Test-Path $src)) {
    throw "소스 디렉터리가 없습니다: $src"
}

# 디렉터리 안 모든 파일의 상대경로 -> 해시 맵을 만든다.
function Get-DirHashMap {
    param([string]$Path)
    $map = [ordered]@{}
    if (-not (Test-Path $Path)) { return $map }
    $root = (Resolve-Path $Path).Path
    foreach ($f in Get-ChildItem -Path $root -Recurse -File | Sort-Object FullName) {
        $rel = $f.FullName.Substring($root.Length).TrimStart('\', '/')
        $map[$rel] = (Get-FileHash -Path $f.FullName -Algorithm SHA256).Hash
    }
    return $map
}

# 두 해시 맵의 차이를 사람이 읽을 수 있는 줄로 돌려준다.
function Compare-HashMap {
    param($Expected, $Actual)
    $diff = @()
    foreach ($k in $Expected.Keys) {
        if (-not $Actual.Contains($k)) { $diff += "  삭제됨: $k" }
        elseif ($Actual[$k] -ne $Expected[$k]) { $diff += "  수정됨: $k" }
    }
    foreach ($k in $Actual.Keys) {
        if (-not $Expected.Contains($k)) { $diff += "  추가됨: $k" }
    }
    return $diff
}

$skills = @(Get-ChildItem -Path $src -Directory)
if ($skills.Count -eq 0) {
    Write-Output "복사할 스킬이 없습니다: $src"
    return
}

$drifted = @()

foreach ($target in $targets) {
    if (-not (Test-Path $target)) {
        New-Item -ItemType Directory -Path $target -Force | Out-Null
        Write-Output "생성: $target"
    }

    $manifestPath = Join-Path $target $manifestName
    $manifest = @{}
    if (Test-Path $manifestPath) {
        try {
            $raw = Get-Content -Path $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($p in $raw.PSObject.Properties) {
                $inner = [ordered]@{}
                foreach ($q in $p.Value.PSObject.Properties) { $inner[$q.Name] = $q.Value }
                $manifest[$p.Name] = $inner
            }
        } catch {
            Write-Warning "매니페스트를 읽을 수 없어 무시합니다: $manifestPath"
            $manifest = @{}
        }
    }

    foreach ($skill in $skills) {
        $name = $skill.Name
        $dest = Join-Path $target $name
        $srcMap = Get-DirHashMap -Path $skill.FullName

        if (Test-Path $dest) {
            $destMap = Get-DirHashMap -Path $dest
            $recorded = $manifest[$name]

            if ($null -eq $recorded) {
                # 매니페스트가 없다 — 이 기능 도입 전에 복사된 설치본이다.
                # 소스와 같으면 안전하다고 보고 기록만 남긴다. 다르면 판단할 수 없으므로 멈춘다.
                $vsSource = Compare-HashMap -Expected $srcMap -Actual $destMap
                if ($vsSource.Count -gt 0 -and -not $Force) {
                    Write-Output ""
                    Write-Warning "드리프트 판정 불가: $name -> $dest"
                    Write-Output "  매니페스트가 없고 설치본이 소스와 다릅니다. 어느 쪽이 최신인지 알 수 없습니다."
                    $vsSource | ForEach-Object { Write-Output $_ }
                    Write-Output "  설치본을 버려도 되면 -Force 로 다시 실행하세요."
                    $drifted += "$name -> $target"
                    continue
                }
            }
            else {
                # 설치본이 지난 동기화 기록과 다르면 누군가 직접 고친 것이다.
                $vsManifest = Compare-HashMap -Expected $recorded -Actual $destMap
                if ($vsManifest.Count -gt 0 -and -not $Force) {
                    Write-Output ""
                    Write-Warning "드리프트 감지: $name -> $dest"
                    Write-Output "  마지막 동기화 이후 설치본이 직접 수정되었습니다. 덮어쓰면 그 수정이 사라집니다."
                    $vsManifest | ForEach-Object { Write-Output $_ }
                    Write-Output "  수정 내용을 소스(skills/$name)에 옮긴 뒤 다시 실행하거나,"
                    Write-Output "  버려도 되면 -Force 로 다시 실행하세요."
                    $drifted += "$name -> $target"
                    continue
                }
            }
        }

        $action = if (Test-Path $dest) { '교체' } else { '신규' }
        if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
        Copy-Item -Recurse -Path $skill.FullName -Destination $dest
        $manifest[$name] = $srcMap
        Write-Output ("{0}: {1} -> {2}" -f $action, $name, $dest)
    }

    $manifest | ConvertTo-Json -Depth 5 | Set-Content -Path $manifestPath -Encoding UTF8
}

if ($drifted.Count -gt 0) {
    # Write-Error 를 쓰면 $ErrorActionPreference='Stop' 때문에 예외로 렌더링되어
    # 통제된 거부가 크래시처럼 보인다. 경고로 알리고 종료코드로만 실패를 전한다.
    Write-Output ""
    Write-Warning ("동기화하지 않은 항목 {0}개: {1}" -f $drifted.Count, ($drifted -join ', '))
    exit 1
}
