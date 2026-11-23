$ErrorActionPreference = 'SilentlyContinue'
[Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$raw = [Console]::In.ReadToEnd()
if ($raw) { $raw = $raw.TrimStart([char]0xFEFF) }
try { $j = $raw | ConvertFrom-Json } catch { $j = $null }
if (-not $j) { Write-Output 'statusline: no input'; exit 0 }

# ---------- helpers ----------
$E = [char]27
function C($code, $text) { "$E[${code}m$text$E[0m" }
$Dim = '2'; $Cyan = '36'; $Blue = '34'; $Magenta = '35'; $Green = '32'; $Yellow = '33'; $Red = '31'; $Gray = '90'
function Emoji($cp) { [char]::ConvertFromUtf32($cp) }
$Sep = ' ' + (C $Gray '|') + ' '

function Fmt-Tokens($n) {
    if ($null -eq $n) { return '?' }
    if ($n -ge 1000000) { return ('{0:0.#}M' -f ($n / 1000000)) }
    if ($n -ge 1000) { return ('{0:0}k' -f ($n / 1000)) }
    return "$n"
}
function Fmt-Span([double]$sec) {
    if ($sec -lt 0) { $sec = 0 }
    $d = [int][math]::Floor($sec / 86400)
    $h = [int][math]::Floor(($sec % 86400) / 3600)
    $m = [int][math]::Floor(($sec % 3600) / 60)
    if ($d -gt 0) { return "${d}d${h}h" }
    if ($h -gt 0) { return "${h}h${m}m" }
    return "${m}m"
}
# used% -> color (green < 50 <= yellow < 80 <= red)
function Level-Color([double]$used) {
    if ($used -ge 80) { return $Red }
    if ($used -ge 50) { return $Yellow }
    return $Green
}

# ---------- line 1: model / directory / git ----------
$line1 = @()

$effort = $null
if ($j.model -and $j.model.effort -is [string] -and $j.model.effort) {
    $effort = $j.model.effort
}
if ($j.model -and $j.model.display_name) {
    $modelName = [string]$j.model.display_name
    if ($effort) {
        $modelName = ($modelName -replace ("\s*\(" + [regex]::Escape($effort) + "\)\s*$"), '').Trim()
    }
    $m = (Emoji 0x1F916) + ' ' + (C "1;$Cyan" $modelName)
    if ($effort) { $m += ' ' + (C $Dim "($effort)") }
    $line1 += $m
}

$dir = $null
if ($j.workspace -and $j.workspace.current_dir) { $dir = $j.workspace.current_dir }
if (-not $dir) { $dir = $j.cwd }
if ($dir) {
    $leaf = Split-Path -Leaf $dir
    if (-not $leaf) { $leaf = $dir }
    $line1 += (Emoji 0x1F4C1) + ' ' + (C $Blue $leaf)
}

$isGit = (-not $j.vcs) -or ($j.vcs.type -eq 'git')
if ($isGit -and $dir -and (Test-Path -LiteralPath $dir)) {
    $branch = git --no-optional-locks -C $dir symbolic-ref --short -q HEAD 2>$null
    if (-not $branch) { $branch = git --no-optional-locks -C $dir rev-parse --short HEAD 2>$null }
    if ($branch) {
        $st = git --no-optional-locks -C $dir status --porcelain 2>$null
        $b = (Emoji 0x1F33F) + ' ' + (C $Magenta $branch)
        if ($st) { $b += C $Yellow '*' }
        $line1 += $b
    }
}

# ---------- line 2: context / quota / cost ----------
$line2 = @()

$cw = $j.context_window
if ($cw -and $null -ne $cw.used_percentage -and ($cw.context_window_size -gt 0 -or [double]$cw.used_percentage -gt 0 -or $null -ne $cw.current_usage)) {
    $pct = [math]::Min(100, [math]::Max(0, [double]$cw.used_percentage))
    $width = 10
    $filled = [int][math]::Round($pct / 100 * $width)
    $col = Level-Color $pct
    $bar = (C $col ([string][char]0x2588 * $filled)) + (C $Gray ([string][char]0x2591 * ($width - $filled)))
    $line2 += (Emoji 0x1F9E0) + ' ' + $bar + ' ' + (C $col ('{0:0}%' -f $pct))
    if ($null -ne $cw.total_input_tokens -and $cw.context_window_size -gt 0) {
        $line2 += C $Dim ((Fmt-Tokens $cw.total_input_tokens) + '/' + (Fmt-Tokens $cw.context_window_size))
    }
}

$qt = $j.quota
$now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
# quota is absent before the first response -> keep the last value in the agy config dir.
# reset_in_seconds is relative, so the cache stores an absolute reset_at (unix seconds) instead.
$qtCache = Join-Path $HOME '.gemini' 'antigravity-cli' 'statusline-quota.json'
if ($qt) {
    try {
        $saved = [ordered]@{}
        foreach ($prop in $qt.PSObject.Properties) {
            $o = $prop.Value
            if ($o -is [pscustomobject]) {
                $c = [ordered]@{}
                foreach ($q in $o.PSObject.Properties) { if ($q.Name -ne 'reset_in_seconds') { $c[$q.Name] = $q.Value } }
                if ($null -ne $o.reset_in_seconds -and [double]$o.reset_in_seconds -gt 0) {
                    $c['reset_at'] = [long]($now + [math]::Round([double]$o.reset_in_seconds))
                }
                $saved[$prop.Name] = $c
            } else { $saved[$prop.Name] = $o }
        }
        $old = $null
        try { $old = [System.IO.File]::ReadAllText($qtCache) } catch {}
        # reset_at jitters by a second or two between calls: keep the cached one when close
        try {
            $prev = $old | ConvertFrom-Json -DateKind String
            foreach ($k in @($saved.Keys)) {
                $c = $saved[$k]; $pv = $prev.PSObject.Properties[$k]
                if ($c -is [System.Collections.IDictionary] -and $c.Contains('reset_at') -and $pv -and $null -ne $pv.Value.reset_at -and
                    [math]::Abs([double]$pv.Value.reset_at - $c['reset_at']) -le 5) { $c['reset_at'] = [long]$pv.Value.reset_at }
            }
        } catch {}
        $txt = $saved | ConvertTo-Json -Depth 5 -Compress
        # agy calls this every ~300ms: skip the write when nothing changed
        if ($old -cne $txt) { [System.IO.File]::WriteAllText($qtCache, $txt, [System.Text.UTF8Encoding]::new($false)) }
    } catch {}
} else {
    try { $qt = [System.IO.File]::ReadAllText($qtCache) | ConvertFrom-Json -DateKind String } catch { $qt = $null }
    if ($qt) {
        foreach ($prop in $qt.PSObject.Properties) {
            $o = $prop.Value
            if ($o -isnot [pscustomobject]) { continue }
            $resetAt = $null
            if ($null -ne $o.reset_at) { $resetAt = [double]$o.reset_at }
            elseif ($o.reset_time) { try { $resetAt = [DateTimeOffset]::Parse([string]$o.reset_time).ToUnixTimeSeconds() } catch {} }
            if ($null -ne $resetAt -and $resetAt -le $now) {
                # cached window already reset -> 0% used, no reset time
                $o.remaining_fraction = 1
                $o.PSObject.Properties.Remove('reset_time')
            } elseif ($null -ne $resetAt) {
                $o | Add-Member -NotePropertyName 'reset_in_seconds' -NotePropertyValue ($resetAt - $now) -Force
            }
        }
    }
}
if ($qt) {
    $modelKey = ''
    if ($j.model) { $modelKey = "$($j.model.id) $($j.model.display_name)" }
    $buckets = if ($modelKey -match '(?i)gemini') {
        @(@('gemini-5h', '5h'), @('gemini-weekly', '7d'))
    } else {
        @(@('3p-5h', '5h'), @('3p-weekly', '7d'))
    }
    $lims = @()
    foreach ($pair in $buckets) {
        $prop = $qt.PSObject.Properties[$pair[0]]
        if (-not $prop) { continue }
        $o = $prop.Value
        if (-not $o -or $o.disabled -eq $true -or $null -eq $o.remaining_fraction) { continue }
        $used = 100 - [math]::Min(100, [math]::Max(0, [double]$o.remaining_fraction * 100))
        $s = $pair[1] + ' ' + (C (Level-Color $used) ('{0:0}%' -f $used))
        $resetSec = 0.0
        if ($null -ne $o.reset_in_seconds -and [double]$o.reset_in_seconds -gt 0) {
            $resetSec = [double]$o.reset_in_seconds
        } elseif ($o.reset_time) {
            try {
                $dt = [DateTimeOffset]::Parse([string]$o.reset_time)
                if ($dt.ToUnixTimeSeconds() -gt $now) { $resetSec = $dt.ToUnixTimeSeconds() - $now }
            } catch {}
        }
        if ($resetSec -gt 0) {
            $s += ' ' + (C $Dim ('(' + (Emoji 0x1F504) + ' ' + (Fmt-Span $resetSec) + ')'))
        }
        $lims += $s
    }
    if (-not $lims) {
        foreach ($prop in $qt.PSObject.Properties) {
            $o = $prop.Value
            if (-not $o -or $o.disabled -eq $true -or $null -eq $o.remaining_fraction) { continue }
            $used = 100 - [math]::Min(100, [math]::Max(0, [double]$o.remaining_fraction * 100))
            $s = $prop.Name + ' ' + (C (Level-Color $used) ('{0:0}%' -f $used))
            if ($null -ne $o.reset_in_seconds -and [double]$o.reset_in_seconds -gt 0) {
                $s += ' ' + (C $Dim ('(' + (Emoji 0x1F504) + ' ' + (Fmt-Span ([double]$o.reset_in_seconds)) + ')'))
            }
            $lims += $s
        }
    }
    if ($lims) { $line2 += (Emoji 0x23F3) + ' ' + ($lims -join '  ') }
}

if ($j.cost -and $null -ne $j.cost.total_usd) {
    $line2 += (Emoji 0x1F4B0) + ' ' + (C $Green ('${0:0.00}' -f [double]$j.cost.total_usd))
}

# ---------- line 3: conversation title as summary ----------
$line3 = $null
$recap = $null
if ($j.conversation_title -is [string] -and $j.conversation_title) {
    $recap = ($j.conversation_title -replace '\s+', ' ').Trim()
}
if ($recap) {
    # fit to terminal width: wide chars (Hangul/CJK/emoji) take 2 columns
    $cols = 0; [int]::TryParse("$env:COLUMNS", [ref]$cols) | Out-Null
    if ($cols -le 0 -and $j.terminal_width) {
        [int]::TryParse("$($j.terminal_width)", [ref]$cols) | Out-Null
    }
    if ($cols -le 0) { $cols = 120 }
    $max = [math]::Max(10, $cols - 14)   # emoji + 'recap: ' + margin
    $sb = [System.Text.StringBuilder]::new(); $w = 0
    $te = [System.Globalization.StringInfo]::GetTextElementEnumerator($recap)
    while ($te.MoveNext()) {
        $g = $te.GetTextElement(); $cp = [char]::ConvertToUtf32($g, 0)
        $cw2 = if (($cp -ge 0x1100 -and $cp -le 0x115F) -or ($cp -ge 0x2E80 -and $cp -le 0xA4CF) -or ($cp -ge 0xAC00 -and $cp -le 0xD7A3) -or ($cp -ge 0xF900 -and $cp -le 0xFAFF) -or ($cp -ge 0xFF00 -and $cp -le 0xFF60) -or ($cp -ge 0x1F300)) { 2 } else { 1 }
        if ($w + $cw2 -gt $max - 1) { [void]$sb.Append([char]0x2026); break }
        [void]$sb.Append($g); $w += $cw2
    }
    $line3 = (Emoji 0x1F4DD) + ' ' + (C $Gray 'recap:') + ' ' + $sb.ToString()
}

# ---------- output ----------
if ($line1) { Write-Output ($line1 -join $Sep) }
if ($line2) { Write-Output ($line2 -join $Sep) }
if ($line3) { Write-Output $line3 }
