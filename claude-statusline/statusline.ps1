$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$raw = [Console]::In.ReadToEnd()
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
foreach ($c in @($j.effort, $j.model.effort, $j.effort_level)) {
    if ($c -is [string] -and $c) { $effort = $c; break }
    if ($c -and $c.level) { $effort = $c.level; break }
}
if (-not $effort) { $effort = $env:CLAUDE_CODE_EFFORT_LEVEL }
if ($j.model.display_name) {
    $m = (Emoji 0x1F916) + ' ' + (C "1;$Cyan" $j.model.display_name)
    if ($effort) { $m += ' ' + (C $Dim "($effort)") }
    $line1 += $m
}

$dir = $j.workspace.current_dir
if (-not $dir) { $dir = $j.cwd }
if ($dir) {
    $leaf = Split-Path -Leaf $dir
    if (-not $leaf) { $leaf = $dir }
    $line1 += (Emoji 0x1F4C1) + ' ' + (C $Blue $leaf)
}

if ($dir -and (Test-Path -LiteralPath $dir)) {
    $branch = git --no-optional-locks -C $dir symbolic-ref --short -q HEAD 2>$null
    if (-not $branch) { $branch = git --no-optional-locks -C $dir rev-parse --short HEAD 2>$null }
    if ($branch) {
        $st = git --no-optional-locks -C $dir status --porcelain 2>$null
        $b = (Emoji 0x1F33F) + ' ' + (C $Magenta $branch)
        if ($st) { $b += C $Yellow '*' }
        $line1 += $b
    }
}

# ---------- line 2: context / limits / cost / time ----------
$line2 = @()

$cw = $j.context_window
# always shown: no usage yet (new session / after /clear) -> empty gauge, 0%
$pct = if ($cw -and $null -ne $cw.used_percentage) { [math]::Min(100, [math]::Max(0, [double]$cw.used_percentage)) } else { 0 }
$width = 10
$filled = [int][math]::Round($pct / 100 * $width)
$col = Level-Color $pct
$bar = (C $col ([string][char]0x2588 * $filled)) + (C $Gray ([string][char]0x2591 * ($width - $filled)))
$line2 += (Emoji 0x1F9E0) + ' ' + $bar + ' ' + (C $col ('{0:0}%' -f $pct))
$used = if ($cw -and $null -ne $cw.total_input_tokens) { $cw.total_input_tokens } else { 0 }
$size = if ($cw -and $cw.context_window_size) { Fmt-Tokens $cw.context_window_size } else { '?' }
$line2 += C $Dim ((Fmt-Tokens $used) + '/' + $size)

$now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$rl = $j.rate_limits
if ($rl) {
    $lims = @()
    foreach ($w in @(@('five_hour', '5h'), @('seven_day', '7d'), @('spend_limit', 'spend'))) {
        $o = $rl.($w[0])
        if ($o -and $null -ne $o.used_percentage) {
            $used = [double]$o.used_percentage
            $left = [math]::Max(0, 100 - $used)
            $s = $w[1] + ' ' + (C (Level-Color $used) ('{0:0}% left' -f $left))
            if ($o.resets_at) { $s += ' ' + (C $Dim ('(' + (Emoji 0x1F504) + ' ' + (Fmt-Span ($o.resets_at - $now)) + ')')) }
            $lims += $s
        }
    }
    if ($lims) { $line2 += (Emoji 0x23F3) + ' ' + ($lims -join '  ') }
}

if ($null -ne $j.cost.total_cost_usd) {
    $line2 += (Emoji 0x1F4B0) + ' ' + (C $Green ('${0:0.00}' -f [double]$j.cost.total_cost_usd))
}
if ($null -ne $j.cost.total_duration_ms) {
    $line2 += (Emoji 0x23F1) + ' ' + (Fmt-Span ([double]$j.cost.total_duration_ms / 1000))
}

# ---------- line 3: latest recap (away_summary) from transcript ----------
$recap = $null
$tp = $j.transcript_path
if ($tp -and (Test-Path -LiteralPath $tp)) {
    try {
        # read only the tail of the transcript to stay fast
        $fs = [System.IO.File]::Open($tp, 'Open', 'Read', 'ReadWrite')
        try {
            $len = $fs.Length
            $take = [long][math]::Min($len, 2MB)
            $fs.Seek($len - $take, 'Begin') | Out-Null
            $buf = New-Object byte[] $take
            $read = $fs.Read($buf, 0, $take)
            $text = [System.Text.Encoding]::UTF8.GetString($buf, 0, $read)
        } finally { $fs.Dispose() }
        $lines = $text -split "`n"
        for ($i = $lines.Length - 1; $i -ge 0; $i--) {
            if ($lines[$i] -notlike '*"away_summary"*') { continue }
            try { $o = $lines[$i] | ConvertFrom-Json } catch { continue }
            if ($o.subtype -eq 'away_summary' -and $o.content) { $recap = [string]$o.content; break }
        }
    } catch {}
}
if ($recap) {
    $recap = (($recap -replace '\s*\(turn off recaps in /config\)\s*$', '') -replace '\s+', ' ').Trim()
    # fit to terminal width: wide chars (Hangul/CJK/emoji) take 2 columns
    $cols = 0; [int]::TryParse("$env:COLUMNS", [ref]$cols) | Out-Null
    if ($cols -le 0) { $cols = 120 }
    $max = $cols - 14   # emoji + 'recap: ' + margin for Claude Code's own spacing
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
