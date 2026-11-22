#Requires -Version 7
# Antigravity CLI(agy) 의 settings.json 에 statusLine 을 이 폴더의 statusline.ps1 로 맞춘다.
#
#   pwsh -NoProfile -File agy-statusline/install.ps1           맞춘다
#   pwsh -NoProfile -File agy-statusline/install.ps1 -Check    아무것도 쓰지 않고 결과만 본다
#
# 대상: ~/.gemini/antigravity-cli/settings.json (폴더가 있을 때만). 출력 약속은 README.md 에 있다.
[CmdletBinding()]
param(
    [switch]$Check,
    [string]$HomeDir = $HOME
)

$script:Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$script:Command = "pwsh -NoProfile -File $((Join-Path $PSScriptRoot 'statusline.ps1').Replace('\', '/'))"

function Get-TargetDirs {
    $dir = Join-Path $HomeDir '.gemini' 'antigravity-cli'
    if (Test-Path -LiteralPath $dir -PathType Container) {
        return @([pscustomobject]@{ Path = $dir; Shown = '~/.gemini/antigravity-cli' })
    }
    return @()
}

# settings.json 하나의 statusLine 을 맞춘다. 다른 키와 키 순서는 그대로 둔다.
function Sync-Settings([string]$Path, [string]$Shown) {
    $desired = [pscustomobject][ordered]@{ type = 'command'; command = $script:Command }
    $text = $null
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        try {
            $text = [System.IO.File]::ReadAllText($Path, $script:Utf8NoBom)
        } catch {
            return [pscustomobject]@{ Status = '실패'; Message = "실패: $Shown 을 읽지 못했다: $($_.Exception.Message)" }
        }
    } elseif (Test-Path -LiteralPath $Path) {
        return [pscustomobject]@{ Status = '실패'; Message = "실패: $Shown 이 파일이 아니다" }
    }

    if ([string]::IsNullOrWhiteSpace($text)) {
        $obj = [pscustomobject]@{}
    } else {
        try {
            $obj = $text | ConvertFrom-Json -DateKind String -ErrorAction Stop
        } catch {
            return [pscustomobject]@{ Status = '실패'; Message = "실패: $Shown 의 JSON 을 읽지 못했다: $($_.Exception.Message)" }
        }
        if ($obj -isnot [pscustomobject]) {
            return [pscustomobject]@{ Status = '실패'; Message = "실패: $Shown 의 최상위가 객체가 아니다" }
        }
    }

    $current = $obj.PSObject.Properties['statusLine']
    if ($current -and ($current.Value | ConvertTo-Json -Depth 100 -Compress) -ceq ($desired | ConvertTo-Json -Compress)) {
        Write-Verbose "${Shown}: 그대로"
        return [pscustomobject]@{ Status = '그대로'; Name = $Shown }
    }

    $status = if ($Check) { '다름' } else { '바꿈' }
    Write-Verbose "${Shown}: $status"
    if ($Check) { return [pscustomobject]@{ Status = $status; Name = $Shown } }

    if ($current) { $current.Value = $desired }
    else { $obj | Add-Member -NotePropertyName 'statusLine' -NotePropertyValue $desired }

    $newline = if ($text -and $text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $json = ($obj | ConvertTo-Json -Depth 100).Replace("`r`n", "`n")
    if ($newline -ne "`n") { $json = $json.Replace("`n", $newline) }
    try {
        # 제자리에서 덮어쓴다. 링크면 링크 대상에 쓴다.
        [System.IO.File]::WriteAllText($Path, $json + $newline, $script:Utf8NoBom)
    } catch {
        return [pscustomobject]@{ Status = '실패'; Message = "실패: $Shown 을 쓰지 못했다: $($_.Exception.Message)" }
    }
    return [pscustomobject]@{ Status = $status; Name = $Shown }
}

function Invoke-Main {
    $results = @(foreach ($d in Get-TargetDirs) {
            Sync-Settings (Join-Path $d.Path 'settings.json') "$($d.Shown)/settings.json"
        })
    $failed = $results | Where-Object Status -EQ '실패' | Select-Object -First 1
    if ($failed) { Write-Output $failed.Message; return }
    $changed = @($results | Where-Object { $_.Status -in '다름', '바꿈' })
    if ($changed.Count) {
        Write-Output "$($changed[0].Status) ($(($changed | ForEach-Object Name) -join ', '))"
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
