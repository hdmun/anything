using module ./Declaration.psm1

Import-Module (Join-Path $PSScriptRoot 'Declaration.psm1') -Force

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

$script:ConfigFilesSchema = @{
    Key      = 'Path'
    Required = @('Path', 'Method', 'Source')
    Allowed  = @('Path', 'Method', 'Source')
    Enums    = @{ Method = @('Link', 'GitInclude') }
    Validate = {
        param($item)
        $problems = [System.Collections.Generic.List[string]]::new()
        $props = $item.PSObject.Properties
        if ($props['Source']) {
            $src = [string]$item.Source
            $segments = $src -split '[/\\]'
            if ([System.IO.Path]::IsPathRooted($src) -or ($segments -contains '..')) {
                $problems.Add('Source 는 pc-setup 폴더 안의 상대 경로다')
            }
        }
        return [string[]]$problems.ToArray()
    }
}

function Get-ConfigFileItems {
    # <Root>\config-files.psd1 을 읽고 검사해 항목 목록을 돌려준다.
    # 항목: Stage = '설정 파일', Id = 선언의 Path 글 그대로, Elevated = $false.
    # 문제가 있으면 DeclarationException.
    param([Parameter(Mandatory)][string]$Root)

    $configFilesPath = Join-Path $Root 'config-files.psd1'
    $items = $null
    $problems = [System.Collections.Generic.List[string]]::new()

    try {
        $items = Read-Declaration -Path $configFilesPath -Schema $script:ConfigFilesSchema
    } catch [DeclarationException] {
        foreach ($p in $_.Exception.Problems) {
            $problems.Add($p)
        }
    }

    if ($null -ne $items) {
        $fileName = Split-Path -Leaf $configFilesPath
        foreach ($item in $items) {
            $sourcePath = Join-Path $Root $item.Source
            if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
                $problems.Add("${fileName}:$($item.Line): 저장소 파일이 없다: $($item.Source)")
            }
        }
    }

    if ($problems.Count -gt 0) {
        throw [DeclarationException]::new([string[]]$problems.ToArray())
    }

    $stageItems = [System.Collections.Generic.List[object]]::new()
    $thisModule = $ExecutionContext.SessionState.Module
    foreach ($item in $items) {
        $rawPath = [string]$item.Path
        $method = [string]$item.Method
        $sourceFull = Resolve-SetupFullPath -Path (Join-Path $Root $item.Source)

        $invoke = {
            param([bool]$Check)
            & $thisModule {
                param($p, $m, $s, $c)
                $dest = $null
                try {
                    $dest = Expand-SetupPath -Path $p
                } catch {
                    return @{ Status = '실패'; Detail = $_.Exception.Message }
                }
                if ($m -eq 'Link') {
                    return Invoke-LinkFile -Destination $dest -Source $s -Check $c
                } else {
                    return Invoke-GitIncludeFile -Destination $dest -Source $s -Check $c
                }
            } $rawPath $method $sourceFull $Check
        }.GetNewClosure()

        $stageItems.Add([pscustomobject]@{
            Stage    = '설정 파일'
            Id       = $rawPath
            Elevated = $false
            Invoke   = $invoke
        })
    }

    return ,([pscustomobject[]]$stageItems.ToArray())
}

function New-LinkWithFallback {
    param(
        [string]$Path,
        [string]$Target
    )
    try {
        New-SymbolicLink -Path $Path -Target $Target
        return @{ Status = '바꿈'; Detail = '' }
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
        [Parameter(Mandatory)][string]$Source,        # 저장소 파일 전체 경로
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
    return @{ Status = '바꿈'; Detail = "백업: $backupPath" }
}

function Invoke-GitIncludeFile {
    # Destination(로컬 gitconfig) 맨 위 [include] 에 Source 를 불러오는 줄이 있게 한다 → @{ Status; Detail }
    param(
        [Parameter(Mandatory)][string]$Destination,
        [Parameter(Mandatory)][string]$Source,
        [string]$SourceKey = 'pc-setup/config/gitconfig',   # 경로가 다른 기존 줄을 알아보는 끝부분
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
        return @{ Status = '바꿈'; Detail = '' }
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
        return @{ Status = '바꿈'; Detail = '' }
    }

    if ($Check) {
        return @{ Status = '다름'; Detail = '불러오는 줄 없음' }
    }

    $prefix = "[include]${nl}`tpath = `"$desiredForward`"${nl}"
    $newContent = $prefix + $raw
    [System.IO.File]::WriteAllText($destPath, $newContent, $utf8NoBom)
    return @{ Status = '바꿈'; Detail = '' }
}

Export-ModuleMember -Function Get-ConfigFileItems, Invoke-LinkFile, Invoke-GitIncludeFile
