#Requires -Version 7
# 규칙 원본(agent-rules/global/)을 합쳐 사용자 전역 규칙 파일 3개를 만든다.
#
#   pwsh -NoProfile -File agent-rules/install.ps1           만든다
#   pwsh -NoProfile -File agent-rules/install.ps1 -Check    아무것도 쓰지 않고 결과만 본다
#   -Force      생성 표시가 없는 파일도 덮어쓴다 (이전 파일은 <파일>.prev 로 남긴다)
#   -Verbose    파일마다 결과 한 줄과 바뀌는 줄을 더 보여 준다
#
# 출력 약속과 파일 이름 규칙은 agent-rules/README.md 에 있다.
[CmdletBinding()]
param(
    [switch]$Check,
    [switch]$Force,
    [string]$HomeDir = $HOME,
    [string]$SourceDir = (Join-Path $PSScriptRoot 'global')
)

$script:Marker = '<!-- 생성 파일'
$script:MarkerLine = '<!-- 생성 파일: 직접 고치지 않는다. 원본은 hdmun/anything 저장소의 agent-rules/global/ 이고 그 저장소 루트에서 pwsh -NoProfile -File agent-rules/install.ps1 로 다시 만든다 -->'
$script:CodexLimit = 32768 # Codex 기본 project_doc_max_bytes

# 도구 이름 → 홈 폴더 기준 대상 파일. CLAUDE_CONFIG_DIR·CODEX_HOME 은 일부러 보지 않는다.
$script:Targets = [ordered]@{
    claude = @('.claude', 'CLAUDE.md')
    codex  = @('.codex', 'AGENTS.md')
    gemini = @('.gemini', 'GEMINI.md')
}

$script:Utf8NoBom = [System.Text.UTF8Encoding]::new($false)

function ConvertTo-Lf([string]$Text) {
    return $Text.Replace("`r`n", "`n").Replace("`r", "`n")
}

# 원본 목록을 읽는다. 이름이 규칙에 어긋나면 실패 문장을 돌려준다.
function Get-RuleSources([string]$Dir) {
    if (-not (Test-Path -LiteralPath $Dir -PathType Container)) {
        return @{ Error = "실패: 원본 폴더 $Dir 가 없다" }
    }
    $names = [string[]]@(Get-ChildItem -LiteralPath $Dir -File | Where-Object { $_.Name.EndsWith('.md') } | ForEach-Object Name)
    [Array]::Sort($names, [StringComparer]::Ordinal)

    foreach ($name in $names) {
        foreach ($tool in ($name.Substring(0, $name.Length - 3).Split('.') | Select-Object -Skip 1)) {
            if (-not $script:Targets.Contains($tool)) {
                return @{ Error = "실패: $name 의 '$tool' 는 도구 이름이 아니다 ($($script:Targets.Keys -join ', ') 중에서 붙인다)" }
            }
        }
    }

    $sources = foreach ($name in $names) {
        $tools = @($name.Substring(0, $name.Length - 3).Split('.') | Select-Object -Skip 1)
        $text = ConvertTo-Lf ([System.IO.File]::ReadAllText((Join-Path $Dir $name), $script:Utf8NoBom))
        if (-not $text.EndsWith("`n")) { $text += "`n" }
        [pscustomobject]@{
            Name  = $name
            Tools = if ($tools.Count) { $tools } else { @($script:Targets.Keys) }
            Text  = $text
        }
    }
    return @{ Sources = @($sources) }
}

function Get-RenderedRules($Sources, [string]$Tool) {
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append($script:MarkerLine).Append("`n")
    foreach ($s in $Sources) {
        if ($s.Tools -contains $Tool) { [void]$sb.Append("`n").Append($s.Text) }
    }
    return $sb.ToString()
}

# 바뀌는 줄만 보여 주는 간단한 줄 단위 diff (LCS)
function Write-LineDiff([string]$Old, [string]$New) {
    $a = $Old.TrimEnd("`n").Split("`n")
    $b = $New.TrimEnd("`n").Split("`n")
    if ($Old -eq '') { $a = @() }
    $n = $a.Count; $m = $b.Count
    $lcs = [int[, ]]::new($n + 1, $m + 1)
    for ($i = $n - 1; $i -ge 0; $i--) {
        for ($j = $m - 1; $j -ge 0; $j--) {
            $lcs[$i, $j] = if ($a[$i] -ceq $b[$j]) { $lcs[($i + 1), ($j + 1)] + 1 }
            else { [Math]::Max($lcs[($i + 1), $j], $lcs[$i, ($j + 1)]) }
        }
    }
    $i = 0; $j = 0
    while ($i -lt $n -or $j -lt $m) {
        if ($i -lt $n -and $j -lt $m -and $a[$i] -ceq $b[$j]) { $i++; $j++ }
        elseif ($j -lt $m -and ($i -ge $n -or $lcs[$i, ($j + 1)] -ge $lcs[($i + 1), $j])) { Write-Verbose "  + $($b[$j])"; $j++ }
        else { Write-Verbose "  - $($a[$i])"; $i++ }
    }
}

# 대상 하나를 처리하고 결과(Status, Name, Message)를 돌려준다.
function Sync-Target([string]$Tool, $Sources) {
    $dirPart, $fileName = $script:Targets[$Tool]
    $dir = Join-Path $HomeDir $dirPart
    $dest = Join-Path $dir $fileName
    $shown = "~/$dirPart/$fileName"

    if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
        Write-Verbose "${shown}: 건너뜀 ($dirPart 폴더가 없다)"
        return $null
    }

    $new = Get-RenderedRules $Sources $Tool
    $newBytes = $script:Utf8NoBom.GetByteCount($new)
    if ($Tool -eq 'codex' -and $newBytes -gt $script:CodexLimit) {
        Write-Verbose "경고: $shown 가 ${newBytes}바이트다. Codex 는 기본 $($script:CodexLimit)바이트까지만 읽는다"
    }

    $exists = Test-Path -LiteralPath $dest -PathType Leaf
    $current = ''
    if ($exists) {
        try {
            $current = ConvertTo-Lf ([System.IO.File]::ReadAllText($dest, $script:Utf8NoBom))
        } catch {
            return [pscustomobject]@{ Status = '실패'; Name = $fileName; Message = "실패: $shown 을 읽지 못했다: $($_.Exception.Message)" }
        }
    }

    if ($exists -and $current -ceq $new) {
        Write-Verbose "${shown}: 그대로"
        return [pscustomobject]@{ Status = '그대로'; Name = $fileName }
    }

    $needsForce = $false
    if ($exists -and -not $current.TrimStart([char]0xFEFF).StartsWith($script:Marker)) {
        $body = $new.Substring($script:MarkerLine.Length + 1)
        $sameBody = $current.Trim() -ceq $body.Trim()
        $needsForce = -not ([string]::IsNullOrWhiteSpace($current) -or $sameBody)
    }
    if ($needsForce -and -not $Force) {
        Write-Verbose "${shown}: 할 일 (생성 표시가 없다)"
        return [pscustomobject]@{ Status = '할 일'; Name = $fileName; Message = "할 일: $shown 에 생성 표시가 없다. 내용을 agent-rules/global/ 로 옮긴 뒤 -Force 로 다시 실행한다" }
    }

    $status = if ($Check) { '다름' } else { '바꿈' }
    Write-Verbose "${shown}: $status"
    Write-LineDiff $current $new
    if ($Check) {
        return [pscustomobject]@{ Status = $status; Name = $fileName }
    }

    try {
        if ($needsForce) {
            # 링크일 수 있으니 내용만 복사한다
            [System.IO.File]::WriteAllBytes("$dest.prev", [System.IO.File]::ReadAllBytes($dest))
        }
        # 제자리에서 덮어쓴다. 심볼릭 링크(계정 폴더의 CLAUDE.md 등)를 지우거나 바꾸지 않고 링크 대상에 쓴다.
        [System.IO.File]::WriteAllText($dest, $new, $script:Utf8NoBom)
    } catch {
        return [pscustomobject]@{ Status = '실패'; Name = $fileName; Message = "실패: $shown 을 쓰지 못했다: $($_.Exception.Message)" }
    }
    return [pscustomobject]@{ Status = $status; Name = $fileName }
}

function Invoke-Main {
    $read = Get-RuleSources $SourceDir
    if ($read.Error) {
        Write-Output $read.Error
        return
    }

    $results = @(foreach ($tool in $script:Targets.Keys) { Sync-Target $tool $read.Sources })

    foreach ($status in '실패', '할 일') {
        $first = $results | Where-Object Status -EQ $status | Select-Object -First 1
        if ($first) {
            Write-Output $first.Message
            return
        }
    }
    $changed = @($results | Where-Object { $_.Status -in '다름', '바꿈' })
    if ($changed.Count) {
        Write-Output "$($changed[0].Status) ($(($changed | ForEach-Object Name) -join ', '))"
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
