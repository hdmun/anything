# 설정 파일을 저장소 정본에 연결하는 단독 스크립트.
# 사용: pwsh -NoProfile -File link-config.ps1 -Source <정본 파일> -Target <원래 자리> -Mode Link|GitInclude [-Check]
#   Link       : Target 에 Source 를 가리키는 심볼릭 링크가 있게 한다. 내용이 다른 기존 파일은 <Target>.bak-<yyyyMMdd-HHmmss> 로 백업한다.
#   GitInclude : Target(로컬 gitconfig) 맨 위 [include] 에 Source 를 불러오는 path 줄이 있게 한다.
# 표준 출력에 한 줄(그대로 | 다름: … | 바꿈: … | 실패: …)을 쓰고, 실패면 종료 코드 1, 나머지는 0 이다.
param(
    [string]$Source,
    [string]$Target,
    [string]$Mode,
    [switch]$Check
)

function Get-BackupStamp {
    (Get-Date).ToString('yyyyMMdd-HHmmss')
}

function New-SymbolicLink {
    param(
        [string]$Path,
        [string]$Target
    )
    New-Item -ItemType SymbolicLink -Path $Path -Target $Target -Force -ErrorAction Stop | Out-Null
}

function Test-DeveloperMode {
    # HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock 의 AllowDevelopmentWithoutDevLicense 가 1 이면 $true
    try {
        $regPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock'
        if (-not (Test-Path -LiteralPath $regPath)) {
            return $false
        }
        $val = (Get-ItemProperty -LiteralPath $regPath -Name 'AllowDevelopmentWithoutDevLicense' -ErrorAction SilentlyContinue).AllowDevelopmentWithoutDevLicense
        return ($val -eq 1)
    } catch {
        return $false
    }
}

function Resolve-SetupFullPath {
    param([Parameter(Mandatory)][string]$Path)
    $unresolved = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    return [System.IO.Path]::GetFullPath($unresolved)
}

function Expand-SetupPath {
    # '~' 로 시작하면 $HOME 으로, '$env:<이름>' 은 그 환경 변수 값으로 바꾼다. 경로 구분자는 '\' 로 맞춘다.
    param([Parameter(Mandatory)][string]$Path)

    if ($Path -eq '~') {
        $Path = $HOME
    } elseif ($Path.StartsWith('~/') -or $Path.StartsWith('~\')) {
        $Path = $HOME + $Path.Substring(1)
    }

    $pattern = '\$env:([A-Za-z_][A-Za-z0-9_]*)'
    foreach ($m in [regex]::Matches($Path, $pattern)) {
        $varName = $m.Groups[1].Value
        if ($null -eq [System.Environment]::GetEnvironmentVariable($varName)) {
            throw "환경 변수 '$varName' 이 없다"
        }
    }
    $Path = [regex]::Replace($Path, $pattern, {
        param($m)
        [System.Environment]::GetEnvironmentVariable($m.Groups[1].Value)
    })

    return $Path.Replace('/', '\')
}

function Get-SourceKey {
    # 경로가 다른 기존 [include] 줄을 알아보는 끝부분: Source 전체 경로의 끝 세 부분('/' 로 잇는다).
    param([Parameter(Mandatory)][string]$Source)
    $parts = @($Source -split '[/\\]' | Where-Object { $_ -ne '' })
    $take = [Math]::Min(3, $parts.Count)
    return ($parts[($parts.Count - $take)..($parts.Count - 1)] -join '/')
}

function New-LinkWithFallback {
    param(
        [string]$Path,
        [string]$Target
    )
    try {
        New-SymbolicLink -Path $Path -Target $Target
        return @{ Status = '바꿈'; Detail = '링크 만듦' }
    } catch {
        if (-not (Test-DeveloperMode)) {
            return @{ Status = '실패'; Detail = 'Developer Mode 꺼짐' }
        }
        return @{ Status = '실패'; Detail = "링크를 만들지 못했다: $($_.Exception.Message)" }
    }
}

function Test-SameFileBytes {
    param(
        [string]$PathA,
        [string]$PathB
    )
    $bytesA = [System.IO.File]::ReadAllBytes($PathA)
    $bytesB = [System.IO.File]::ReadAllBytes($PathB)
    if ($bytesA.Length -ne $bytesB.Length) {
        return $false
    }
    for ($i = 0; $i -lt $bytesA.Length; $i++) {
        if ($bytesA[$i] -ne $bytesB[$i]) {
            return $false
        }
    }
    return $true
}

function Invoke-LinkFile {
    # Destination 에 Source 를 가리키는 symlink 가 있게 한다 → @{ Status; Detail }
    param(
        [Parameter(Mandatory)][string]$Destination,   # 펼친 원래 자리 전체 경로
        [Parameter(Mandatory)][string]$Source,        # 저장소 정본 전체 경로
        [bool]$Check
    )

    $destPath = Resolve-SetupFullPath -Path $Destination
    $sourceFull = Resolve-SetupFullPath -Path $Source
    $parentDir = Split-Path -Parent $destPath

    $destItem = Get-Item -LiteralPath $destPath -Force -ErrorAction SilentlyContinue

    if ($null -eq $destItem) {
        if ($Check) {
            return @{ Status = '다름'; Detail = '없음' }
        }
        if (-not [string]::IsNullOrEmpty($parentDir) -and -not (Test-Path -LiteralPath $parentDir -PathType Container)) {
            New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
        }
        return New-LinkWithFallback -Path $destPath -Target $sourceFull
    }

    if ($destItem.LinkType -eq 'SymbolicLink') {
        $rawTarget = @($destItem.Target)[0]
        $resolvedTarget = $null
        if (-not [string]::IsNullOrEmpty($rawTarget)) {
            if ([System.IO.Path]::IsPathRooted($rawTarget)) {
                $resolvedTarget = [System.IO.Path]::GetFullPath($rawTarget)
            } else {
                $resolvedTarget = [System.IO.Path]::GetFullPath((Join-Path $parentDir $rawTarget))
            }
        }

        if (($null -ne $resolvedTarget) -and ($resolvedTarget -ieq $sourceFull) -and (Test-Path -LiteralPath $resolvedTarget)) {
            return @{ Status = '그대로'; Detail = '' }
        }

        if ($Check) {
            return @{ Status = '다름'; Detail = '다른 곳을 가리키는 링크' }
        }
        Remove-Item -LiteralPath $destPath -Force
        return New-LinkWithFallback -Path $destPath -Target $sourceFull
    }

    if ($destItem.PSIsContainer) {
        return @{ Status = '실패'; Detail = '링크 자리에 폴더가 있다' }
    }

    if ($Check) {
        return @{ Status = '다름'; Detail = '일반 파일' }
    }

    if (Test-SameFileBytes -PathA $destPath -PathB $sourceFull) {
        Remove-Item -LiteralPath $destPath -Force
        return New-LinkWithFallback -Path $destPath -Target $sourceFull
    }

    $stamp = Get-BackupStamp
    $backupPath = "${destPath}.bak-${stamp}"
    Move-Item -LiteralPath $destPath -Destination $backupPath -Force
    $linkResult = New-LinkWithFallback -Path $destPath -Target $sourceFull
    if ($linkResult.Status -eq '실패') {
        return $linkResult
    }
    return @{ Status = '바꿈'; Detail = "링크 만듦 (백업: $backupPath)" }
}

function Invoke-GitIncludeFile {
    # Destination(로컬 gitconfig) 맨 위 [include] 에 Source 를 불러오는 줄이 있게 한다 → @{ Status; Detail }
    param(
        [Parameter(Mandatory)][string]$Destination,
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$SourceKey,   # 경로가 다른 기존 줄을 알아보는 끝부분
        [bool]$Check
    )

    $destPath = Resolve-SetupFullPath -Path $Destination
    $sourceFull = Resolve-SetupFullPath -Path $Source
    $desiredForward = $sourceFull.Replace('\', '/')
    $normalizedSourceKey = $SourceKey.Replace('\', '/')
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)

    if (-not (Test-Path -LiteralPath $destPath -PathType Leaf)) {
        if ($Check) {
            return @{ Status = '다름'; Detail = '파일 없음' }
        }
        $content = "[include]`npath = `"$desiredForward`"`n"
        [System.IO.File]::WriteAllText($destPath, $content, $utf8NoBom)
        return @{ Status = '바꿈'; Detail = '새 파일에 [include] 넣음' }
    }

    $raw = [System.IO.File]::ReadAllText($destPath, $utf8NoBom)
    $idxRN = $raw.IndexOf("`r`n")
    $idxN = $raw.IndexOf("`n")
    $nl = if ($idxRN -ge 0 -and ($idxRN + 1) -eq $idxN) { "`r`n" } else { "`n" }

    $lines = $raw -split "`r?`n"
    $inInclude = $false
    $matchedKeyLineIndex = -1

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $trimmed = $lines[$i].Trim()
        if ($trimmed -eq '' -or $trimmed.StartsWith('#') -or $trimmed.StartsWith(';')) {
            continue
        }
        if ($trimmed -match '^\[\s*([^\]]+?)\s*\](?:\s*[#;].*)?$') {
            $inInclude = ($Matches[1].Trim() -ieq 'include')
            continue
        }
        if ($inInclude -and $trimmed -match '^(?i)path\s*=\s*(.*)$') {
            $val = $Matches[1].Trim()
            if ($val.Length -ge 2 -and $val.StartsWith('"') -and $val.EndsWith('"')) {
                $val = $val.Substring(1, $val.Length - 2).Trim()
            }
            $normVal = $val.Replace('\', '/')
            if ($normVal -ieq $desiredForward) {
                return @{ Status = '그대로'; Detail = '' }
            }
            if ($matchedKeyLineIndex -lt 0 -and $normVal.EndsWith($normalizedSourceKey, [System.StringComparison]::OrdinalIgnoreCase)) {
                $matchedKeyLineIndex = $i
            }
        }
    }

    if ($matchedKeyLineIndex -ge 0) {
        if ($Check) {
            return @{ Status = '다름'; Detail = '경로 다름' }
        }
        $origLine = $lines[$matchedKeyLineIndex]
        if ($origLine -match '^(\s*(?i)path\s*=\s*)(.*)$') {
            $lines[$matchedKeyLineIndex] = "$($Matches[1])`"$desiredForward`""
        } else {
            $lines[$matchedKeyLineIndex] = "`tpath = `"$desiredForward`""
        }
        $updated = $lines -join $nl
        [System.IO.File]::WriteAllText($destPath, $updated, $utf8NoBom)
        return @{ Status = '바꿈'; Detail = '[include] 경로 고침' }
    }

    if ($Check) {
        return @{ Status = '다름'; Detail = '불러오는 줄 없음' }
    }

    $prefix = "[include]${nl}`tpath = `"$desiredForward`"${nl}"
    $newContent = $prefix + $raw
    [System.IO.File]::WriteAllText($destPath, $newContent, $utf8NoBom)
    return @{ Status = '바꿈'; Detail = '맨 위에 [include] 넣음' }
}

function Format-ResultLine {
    param([hashtable]$Result)
    if ($Result.Status -eq '그대로') {
        return '그대로'
    }
    return "$($Result.Status): $($Result.Detail)"
}

function Invoke-Main {
    # 매개변수 검사·경로 펼침·예외 처리를 맡는다 → [pscustomobject]@{ Line; ExitCode }
    param(
        [string]$Source,
        [string]$Target,
        [string]$Mode,
        [switch]$Check
    )

    $fail = { param($reason) [pscustomobject]@{ Line = "실패: $reason"; ExitCode = 1 } }

    try {
        foreach ($pair in @(@('Source', $Source), @('Target', $Target), @('Mode', $Mode))) {
            if ([string]::IsNullOrWhiteSpace($pair[1])) {
                return (& $fail "$($pair[0]) 가 없다")
            }
        }
        if ($Mode -notin @('Link', 'GitInclude')) {
            return (& $fail 'Mode 는 Link 또는 GitInclude 다')
        }

        $sourceFull = Resolve-SetupFullPath -Path $Source
        if (-not (Test-Path -LiteralPath $sourceFull -PathType Leaf)) {
            return (& $fail "정본 파일이 없다: $Source")
        }
        $destination = Expand-SetupPath -Path $Target

        if ($Mode -eq 'Link') {
            $result = Invoke-LinkFile -Destination $destination -Source $sourceFull -Check $Check.IsPresent
        } else {
            $result = Invoke-GitIncludeFile -Destination $destination -Source $sourceFull -SourceKey (Get-SourceKey $sourceFull) -Check $Check.IsPresent
        }
    } catch {
        return (& $fail $_.Exception.Message)
    }

    $code = if ($result.Status -eq '실패') { 1 } else { 0 }
    return [pscustomobject]@{ Line = (Format-ResultLine $result); ExitCode = $code }
}

if ($MyInvocation.InvocationName -ne '.') {
    $outcome = Invoke-Main -Source $Source -Target $Target -Mode $Mode -Check:$Check
    Write-Output $outcome.Line
    exit $outcome.ExitCode
}
