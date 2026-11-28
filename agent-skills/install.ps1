#Requires -Version 7
# 직접 만든 스킬 원본(agent-skills/<묶음>/<스킬>/)을 에이전트의 skills 폴더로 복사한다.
#
#   pwsh -NoProfile -File agent-skills/install.ps1           복사한다
#   pwsh -NoProfile -File agent-skills/install.ps1 -Check    아무것도 쓰지 않고 결과만 본다
#   -Force      생성 표시가 없고 내용이 다른 폴더도 덮어쓴다 (이전 폴더는 <skills 폴더>.prev/<스킬> 로 옮긴다)
#   -Verbose    대상마다 결과 한 줄을 더 보여 준다
#
# 묶음·출력 약속은 agent-skills/README.md 에 있다.
[CmdletBinding()]
param(
    [switch]$Check,
    [switch]$Force,
    [string]$HomeDir = $HOME,
    [string]$SourceDir = $PSScriptRoot
)

$script:MarkerName = '.agent-skills'

# 묶음 → 대상 도구 폴더(홈 폴더 기준). 처리 순서도 이 순서다. CLAUDE_CONFIG_DIR 는 일부러 보지 않는다.
$script:Groups = [ordered]@{
    shared = @('.claude', '.agents')
    claude = @('.claude')
    agents = @('.agents')
}

$script:Utf8NoBom = [System.Text.UTF8Encoding]::new($false)

function Get-MarkerText([string]$Group, [string]$Skill) {
    return "생성 폴더: 직접 고치지 않는다. 원본은 hdmun/anything 저장소의 agent-skills/$Group/$Skill/ 이고 그 저장소 루트에서 pwsh -NoProfile -File agent-skills/install.ps1 로 다시 만든다`n"
}

# 원본을 읽어 대상 목록을 만든다. 같은 skills 폴더에 같은 이름이 두 묶음에서 들어가면 실패 문장을 돌려준다.
function Get-SkillPlan([string]$Dir) {
    $items = [System.Collections.Generic.List[object]]::new()
    $owners = @{}
    foreach ($group in $script:Groups.Keys) {
        $groupDir = Join-Path $Dir $group
        if (-not (Test-Path -LiteralPath $groupDir -PathType Container)) { continue }
        $names = [string[]]@(Get-ChildItem -LiteralPath $groupDir -Directory -Force | ForEach-Object Name)
        [Array]::Sort($names, [StringComparer]::Ordinal)
        foreach ($skill in $names) {
            foreach ($tool in $script:Groups[$group]) {
                $key = "$tool/$skill".ToLowerInvariant()
                if ($owners.ContainsKey($key)) {
                    return @{ Error = "실패: $skill 이 $($owners[$key]), $group 에 함께 있다" }
                }
                $owners[$key] = $group
                $items.Add([pscustomobject]@{
                        Group  = $group
                        Skill  = $skill
                        Source = Join-Path $groupDir $skill
                        Tool   = $tool
                        Shown  = "~/$tool/skills/$skill"
                    })
            }
        }
    }
    return @{ Items = $items.ToArray() }
}

# 폴더 안 파일(하위 폴더·숨김 포함)을 상대 경로('/' 구분, 대소문자 무시) → 전체 경로로 돌려준다. 맨 위의 표시 파일은 뺀다.
function Get-FileMap([string]$Dir) {
    $map = [System.Collections.Generic.Dictionary[string, string]]::new([StringComparer]::OrdinalIgnoreCase)
    $root = [System.IO.Path]::GetFullPath($Dir).TrimEnd('\', '/')
    foreach ($f in Get-ChildItem -LiteralPath $Dir -Recurse -File -Force) {
        $rel = $f.FullName.Substring($root.Length + 1).Replace('\', '/')
        if ($rel -ieq $script:MarkerName) { continue }
        $map[$rel] = $f.FullName
    }
    return $map
}

# 파일 바이트에서 CRLF·CR 을 LF 로 바꿔 돌려준다. git 의 줄바꿈 변환이 PC 마다 달라도 같은 내용으로 보기 위해서다.
function Read-NormalizedBytes([string]$Path) {
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $out = [System.Collections.Generic.List[byte]]::new($bytes.Length)
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        if ($bytes[$i] -eq 13) {
            $out.Add(10)
            if (($i + 1) -lt $bytes.Length -and $bytes[$i + 1] -eq 10) { $i++ }
        } else {
            $out.Add($bytes[$i])
        }
    }
    return , $out.ToArray()
}

function Test-SameContent([string]$SourceDir, [string]$DestDir) {
    $src = Get-FileMap $SourceDir
    $dst = Get-FileMap $DestDir
    if ($src.Count -ne $dst.Count) { return $false }
    foreach ($rel in $src.Keys) {
        if (-not $dst.ContainsKey($rel)) { return $false }
        $a = Read-NormalizedBytes $src[$rel]
        $b = Read-NormalizedBytes $dst[$rel]
        if (-not [System.Linq.Enumerable]::SequenceEqual([byte[]]$a, [byte[]]$b)) { return $false }
    }
    return $true
}

function Test-IsLink($Item) {
    return $Item.LinkType -in @('SymbolicLink', 'Junction')
}

# 링크 항목 자체만 지운다. 재귀로 지우면 junction 이 가리키던 폴더의 내용까지 지워질 수 있다.
function Remove-LinkOnly([string]$Path) {
    [System.IO.Directory]::Delete($Path, $false)
}

function Write-Marker([string]$DestDir, [string]$Group, [string]$Skill) {
    [System.IO.File]::WriteAllText((Join-Path $DestDir $script:MarkerName), (Get-MarkerText $Group $Skill), $script:Utf8NoBom)
}

# 원본 파일을 바이트 그대로 복사하고 표시 파일을 쓴다. 대상 폴더가 있으면 먼저 비운다.
function Copy-Skill($Item, [string]$DestDir) {
    if (Test-Path -LiteralPath $DestDir) {
        foreach ($child in Get-ChildItem -LiteralPath $DestDir -Force) {
            if (Test-IsLink $child) { Remove-LinkOnly $child.FullName; continue }
            Remove-Item -LiteralPath $child.FullName -Recurse -Force
        }
    } else {
        New-Item -ItemType Directory -Path $DestDir -Force | Out-Null
    }
    $src = Get-FileMap $Item.Source
    foreach ($rel in $src.Keys) {
        $target = Join-Path $DestDir $rel
        $parent = Split-Path -Parent $target
        if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        [System.IO.File]::WriteAllBytes($target, [System.IO.File]::ReadAllBytes($src[$rel]))
    }
    Write-Marker $DestDir $Item.Group $Item.Skill
}

# 대상 하나를 처리하고 결과(Status, Shown, Message)를 돌려준다.
function Sync-Skill($Item) {
    $toolDir = Join-Path $HomeDir $Item.Tool
    if (-not (Test-Path -LiteralPath $toolDir -PathType Container)) {
        Write-Verbose "$($Item.Shown): 건너뜀 ($($Item.Tool) 폴더가 없다)"
        return $null
    }
    $skillsDir = Join-Path $toolDir 'skills'
    $dest = Join-Path $skillsDir $Item.Skill
    $changed = if ($Check) { '다름' } else { '바꿈' }
    $result = { param($status, $message) [pscustomobject]@{ Status = $status; Shown = $Item.Shown; Message = $message } }

    try {
        $destItem = Get-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue

        if ($null -eq $destItem) {
            Write-Verbose "$($Item.Shown): $changed (없음)"
            if (-not $Check) { Copy-Skill $Item $dest }
            return (& $result $changed)
        }

        if (Test-IsLink $destItem) {
            Write-Verbose "$($Item.Shown): $changed (링크)"
            if (-not $Check) {
                Remove-LinkOnly $dest
                Copy-Skill $Item $dest
            }
            return (& $result $changed)
        }

        if (-not $destItem.PSIsContainer) {
            return (& $result '실패' "실패: $($Item.Shown) 자리에 파일이 있다")
        }

        $hasMarker = Test-Path -LiteralPath (Join-Path $dest $script:MarkerName) -PathType Leaf
        $same = Test-SameContent $Item.Source $dest

        if ($same -and $hasMarker) {
            Write-Verbose "$($Item.Shown): 그대로"
            return (& $result '그대로')
        }

        if ($same) {
            Write-Verbose "$($Item.Shown): $changed (생성 표시만 없다)"
            if (-not $Check) { Write-Marker $dest $Item.Group $Item.Skill }
            return (& $result $changed)
        }

        if (-not $hasMarker -and -not ($Force -and -not $Check)) {
            Write-Verbose "$($Item.Shown): 할 일 (생성 표시가 없고 내용이 다르다)"
            return (& $result '할 일' "할 일: $($Item.Shown) 에 생성 표시가 없고 내용이 다르다. 손으로 고친 내용을 agent-skills/$($Item.Group)/$($Item.Skill)/ 로 옮긴 뒤 -Force 로 다시 실행한다")
        }

        Write-Verbose "$($Item.Shown): $changed (내용 다름)"
        if (-not $Check) {
            if (-not $hasMarker) {
                $backupRoot = "$skillsDir.prev"
                $backup = Join-Path $backupRoot $Item.Skill
                $old = Get-Item -LiteralPath $backup -Force -ErrorAction SilentlyContinue
                if ($null -ne $old) {
                    if (Test-IsLink $old) { Remove-LinkOnly $backup } else { Remove-Item -LiteralPath $backup -Recurse -Force }
                }
                New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
                Move-Item -LiteralPath $dest -Destination $backup
            }
            Copy-Skill $Item $dest
        }
        return (& $result $changed)
    } catch {
        return (& $result '실패' "실패: $($Item.Shown) 을 맞추지 못했다: $($_.Exception.Message)")
    }
}

function Invoke-Main {
    if (-not (Test-Path -LiteralPath $SourceDir -PathType Container)) {
        Write-Output "실패: 원본 폴더 $SourceDir 가 없다"
        return
    }
    $plan = Get-SkillPlan $SourceDir
    if ($plan.Error) {
        Write-Output $plan.Error
        return
    }

    $results = @(foreach ($item in $plan.Items) { Sync-Skill $item })

    foreach ($status in '실패', '할 일') {
        $first = $results | Where-Object Status -EQ $status | Select-Object -First 1
        if ($first) {
            Write-Output $first.Message
            return
        }
    }
    $changed = @($results | Where-Object { $_.Status -in '다름', '바꿈' })
    if ($changed.Count) {
        Write-Output "$($changed[0].Status) ($(($changed | ForEach-Object Shown) -join ', '))"
        return
    }
    Write-Output '그대로'
}

# bash 등에서 pwsh -File 로 부를 때 콘솔 코드 페이지와 상관없이 한국어 한 줄이 깨지지 않게,
# 실행하는 동안만 출력 인코딩을 BOM 없는 UTF-8 로 두고 끝나면(실패 포함) 되돌린다.
$savedOutputEncoding = [Console]::OutputEncoding
try {
    [Console]::OutputEncoding = $script:Utf8NoBom
    Invoke-Main
} finally {
    [Console]::OutputEncoding = $savedOutputEncoding
}
