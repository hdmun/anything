#Requires -Version 7
# Codex 설정 폴더(CODEX_HOME)마다 statusline.py 를 복사하고 config.toml 에 statusline 키 세 개를 맞춘다.
#
#   pwsh -NoProfile -File codex-statusline/install.ps1           맞춘다
#   pwsh -NoProfile -File codex-statusline/install.ps1 -Check    아무것도 쓰지 않고 결과만 본다
#   -Python     python 명령 (기본 python). 이 명령의 sys.executable 을 MCP 서버 명령으로 쓴다
#
# 대상: ~/.codex 와 ~/.agent-accounts/codex/* (폴더가 있을 때만). 출력 약속은 README.md 에 있다.
[CmdletBinding()]
param(
    [switch]$Check,
    [string]$HomeDir = $HOME,
    [string]$Python = 'python'
)

$script:Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$script:Source = Join-Path $PSScriptRoot 'statusline.py'
$script:Server = 'codex-statusline'

function ConvertTo-TomlString([string]$Value) {
    return '"' + $Value.Replace('\', '\\').Replace('"', '\"') + '"'
}

function Get-TargetDirs {
    $dirs = [System.Collections.Generic.List[object]]::new()
    $main = Join-Path $HomeDir '.codex'
    if (Test-Path -LiteralPath $main -PathType Container) {
        $dirs.Add([pscustomobject]@{ Path = $main; Shown = '~/.codex' })
    }
    $accounts = Join-Path $HomeDir '.agent-accounts' 'codex'
    if (Test-Path -LiteralPath $accounts -PathType Container) {
        foreach ($d in (Get-ChildItem -LiteralPath $accounts -Directory | Sort-Object Name)) {
            $dirs.Add([pscustomobject]@{ Path = $d.FullName; Shown = "~/.agent-accounts/codex/$($d.Name)" })
        }
    }
    return $dirs.ToArray()
}

# python 명령의 실제 실행 파일 경로를 / 로 돌려준다. 없으면 $null.
# Microsoft Store 별칭(python.exe 스텁)은 실행에 실패하므로 여기서 걸러진다.
function Get-PythonPath {
    if (-not (Get-Command $Python -CommandType Application -ErrorAction SilentlyContinue)) { return $null }
    try {
        $exe = & $Python -c 'import sys; print(sys.executable)' 2>$null
    } catch {
        return $null
    }
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($exe)) { return $null }
    return ([string]@($exe)[0]).Trim().Replace('\', '/')
}

# TOML 표 머리 줄이면 표 이름(따옴표·공백 정리)을, 아니면 $null 을 돌려준다. [[배열 표]] 도 경계로 본다.
function Get-TableName([string]$Line) {
    if ($Line -match '^\s*\[\[?\s*([^\[\]]+?)\s*\]\]?\s*(#.*)?$') {
        return (($Matches[1] -split '\.') | ForEach-Object { $_.Trim().Trim('"').Trim("'") }) -join '.'
    }
    return $null
}

# 값이 여러 줄에 걸친 배열이면 그 끝 줄 번호를 돌려준다(문자열 안의 괄호는 세지 않는다).
function Get-ValueEnd([System.Collections.Generic.List[string]]$Lines, [int]$Start) {
    $depth = 0
    for ($i = $Start; $i -lt $Lines.Count; $i++) {
        $s = $Lines[$i] -replace '"(\\.|[^"\\])*"', '""' -replace "'[^']*'", "''"
        $s = $s -replace '#.*$', ''
        $depth += ([regex]::Matches($s, '[\[{]')).Count - ([regex]::Matches($s, '[\]}]')).Count
        if ($i -eq $Start) {
            # 키 = 다음의 값만 센다
            $eq = $s.IndexOf('=')
            $depth = ([regex]::Matches($s.Substring($eq + 1), '[\[{]')).Count - ([regex]::Matches($s.Substring($eq + 1), '[\]}]')).Count
        }
        if ($depth -le 0) { return $i }
    }
    return $Lines.Count - 1
}

# [Table] 안의 Key 를 "Key = Value" 한 줄로 맞춘다. 바꿨으면 $true.
function Set-TomlKey([System.Collections.Generic.List[string]]$Lines, [string]$Table, [string]$Key, [string]$Value) {
    $want = "$Key = $Value"
    $header = -1
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ((Get-TableName $Lines[$i]) -ceq $Table -and $Lines[$i] -notmatch '^\s*\[\[') { $header = $i; break }
    }
    if ($header -lt 0) {
        if ($Lines.Count -and $Lines[$Lines.Count - 1].Trim() -ne '') { $Lines.Add('') }
        $Lines.Add("[$Table]")
        $Lines.Add($want)
        return $true
    }

    $end = $Lines.Count
    for ($i = $header + 1; $i -lt $Lines.Count; $i++) {
        if ($null -ne (Get-TableName $Lines[$i])) { $end = $i; break }
    }
    $keyPattern = '^\s*["'']?' + [regex]::Escape($Key) + '["'']?\s*='
    for ($i = $header + 1; $i -lt $end; $i++) {
        if ($Lines[$i] -match $keyPattern) {
            $last = Get-ValueEnd $Lines $i
            if ($last -eq $i -and $Lines[$i].Trim() -ceq $want) { return $false }
            $Lines.RemoveRange($i, $last - $i + 1)
            $Lines.Insert($i, $want)
            return $true
        }
    }
    # 표의 마지막 내용 줄 뒤에 넣는다
    $at = $end
    while ($at - 1 -gt $header -and $Lines[$at - 1].Trim() -eq '') { $at-- }
    $Lines.Insert($at, $want)
    return $true
}

function Sync-Target($Dir, [string]$PythonPath) {
    $changed = [System.Collections.Generic.List[string]]::new()

    # 1. statusline.py 복사본
    $copyDir = Join-Path $Dir.Path 'statusline'
    $copy = Join-Path $copyDir 'statusline.py'
    $srcBytes = [System.IO.File]::ReadAllBytes($script:Source)
    $sameCopy = (Test-Path -LiteralPath $copy -PathType Leaf) -and
        ([Convert]::ToBase64String([System.IO.File]::ReadAllBytes($copy)) -ceq [Convert]::ToBase64String($srcBytes))
    if (-not $sameCopy) { $changed.Add("$($Dir.Shown)/statusline/statusline.py") }

    # 2. config.toml
    $configPath = Join-Path $Dir.Path 'config.toml'
    $text = ''
    if (Test-Path -LiteralPath $configPath -PathType Leaf) {
        try {
            $text = [System.IO.File]::ReadAllText($configPath, $script:Utf8NoBom)
        } catch {
            return [pscustomobject]@{ Status = '실패'; Message = "실패: $($Dir.Shown)/config.toml 을 읽지 못했다: $($_.Exception.Message)" }
        }
    }
    $newline = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $body = $text.Replace("`r`n", "`n").TrimEnd("`n")
    $lines = [System.Collections.Generic.List[string]]::new()
    if ($body -ne '') { $lines.AddRange([string[]]$body.Split("`n")) }

    $scriptPath = ($copy.Replace('\', '/'))
    $argList = "[$(ConvertTo-TomlString '-u'), $(ConvertTo-TomlString $scriptPath)]"
    $edits = @(
        (Set-TomlKey $lines 'features' 'tui_extensions_statusline' 'true')
        (Set-TomlKey $lines "mcp_servers.$($script:Server)" 'command' (ConvertTo-TomlString $PythonPath))
        (Set-TomlKey $lines "mcp_servers.$($script:Server)" 'args' $argList)
        (Set-TomlKey $lines 'tui' 'status_line_provider' "{ server = $(ConvertTo-TomlString $script:Server), tool = `"statusline`" }")
    )
    $configChanged = $edits -contains $true
    if ($configChanged) { $changed.Add("$($Dir.Shown)/config.toml") }

    if (-not $changed.Count) {
        Write-Verbose "$($Dir.Shown): 그대로"
        return [pscustomobject]@{ Status = '그대로' }
    }
    $status = if ($Check) { '다름' } else { '바꿈' }
    Write-Verbose "$($Dir.Shown): $status ($($changed -join ', '))"
    if ($Check) { return [pscustomobject]@{ Status = $status; Names = $changed.ToArray() } }

    try {
        if (-not $sameCopy) {
            New-Item -ItemType Directory -Path $copyDir -Force | Out-Null
            [System.IO.File]::WriteAllBytes($copy, $srcBytes)
        }
        if ($configChanged) {
            # 제자리에서 덮어쓴다. 링크면 링크 대상에 쓴다.
            [System.IO.File]::WriteAllText($configPath, ($lines -join $newline) + $newline, $script:Utf8NoBom)
        }
    } catch {
        return [pscustomobject]@{ Status = '실패'; Message = "실패: $($Dir.Shown) 에 쓰지 못했다: $($_.Exception.Message)" }
    }
    return [pscustomobject]@{ Status = $status; Names = $changed.ToArray() }
}

function Invoke-Main {
    $dirs = @(Get-TargetDirs)
    if (-not $dirs.Count) { Write-Output '그대로'; return }

    $pythonPath = Get-PythonPath
    if (-not $pythonPath) {
        Write-Output "실패: $Python 을 실행하지 못했다 (Python 이 필요하다)"
        return
    }

    $results = @(foreach ($d in $dirs) { Sync-Target $d $pythonPath })
    $failed = $results | Where-Object Status -EQ '실패' | Select-Object -First 1
    if ($failed) { Write-Output $failed.Message; return }
    $changed = @($results | Where-Object { $_.Status -in '다름', '바꿈' })
    if ($changed.Count) {
        Write-Output "$($changed[0].Status) ($(($changed | ForEach-Object { $_.Names }) -join ', '))"
        return
    }
    Write-Output '그대로'
}

# pwsh -File 로 부를 때 콘솔 코드 페이지와 상관없이 한 줄이 깨지지 않게 한다.
$savedOutputEncoding = [Console]::OutputEncoding
try {
    [Console]::OutputEncoding = $script:Utf8NoBom
    Invoke-Main
} finally {
    [Console]::OutputEncoding = $savedOutputEncoding
}
