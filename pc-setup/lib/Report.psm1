function New-SetupResult {
    # → [pscustomobject]@{ Stage; Id; Status; Detail }
    param(
        [Parameter(Mandatory)][string]$Stage,
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][ValidateSet('그대로','바꿈','할 일','실패','다름','확인 못 함','건너뜀')][string]$Status,
        [string]$Detail = ''
    )

    [pscustomobject]@{
        Stage  = $Stage
        Id     = $Id
        Status = $Status
        Detail = $Detail
    }
}

function ConvertFrom-ResultText {
    # 결과 글 한 줄('바꿈 (백업: x)', '할 일: 재부팅 후 셋업 다시 실행' 등) → @{ Status; Detail }
    # 모양이 맞지 않으면 $null.
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text, [switch]$Check)

    if ($null -eq $Text) {
        return $null
    }
    $trimmed = $Text.Trim()
    if ($trimmed -eq '') {
        return $null
    }

    if ($trimmed -eq '그대로') {
        return @{ Status = '그대로'; Detail = '' }
    }

    if (-not $Check) {
        if ($trimmed -eq '바꿈') {
            return @{ Status = '바꿈'; Detail = '' }
        }
        if ($trimmed -match '^바꿈 \((?<detail>.+)\)$') {
            return @{ Status = '바꿈'; Detail = $Matches.detail }
        }
    }

    if ($Check) {
        if ($trimmed -eq '다름') {
            return @{ Status = '다름'; Detail = '' }
        }
        if ($trimmed -match '^다름 \((?<detail>.+)\)$') {
            return @{ Status = '다름'; Detail = $Matches.detail }
        }
        if ($trimmed -match '^확인 못 함:\s*(?<detail>.+)$') {
            $d = $Matches.detail.Trim()
            if ($d -ne '') {
                return @{ Status = '확인 못 함'; Detail = $d }
            }
        }
    }

    if ($trimmed -match '^할 일:\s*(?<detail>.+)$') {
        $d = $Matches.detail.Trim()
        if ($d -ne '') {
            return @{ Status = '할 일'; Detail = $d }
        }
    }

    if ($trimmed -match '^실패:\s*(?<detail>.+)$') {
        $d = $Matches.detail.Trim()
        if ($d -ne '') {
            return @{ Status = '실패'; Detail = $d }
        }
    }

    return $null
}

function Format-ResultLine {
    # 결과 → '[<Stage>] <Id>: <결과 글>'
    param([Parameter(Mandatory)]$Result)

    $status = if ($Result -is [System.Collections.IDictionary]) { $Result['Status'] } else { $Result.Status }
    $detail = if ($Result -is [System.Collections.IDictionary]) { $Result['Detail'] } else { $Result.Detail }
    $stage  = if ($Result -is [System.Collections.IDictionary]) { $Result['Stage'] } else { $Result.Stage }
    $id     = if ($Result -is [System.Collections.IDictionary]) { $Result['Id'] } else { $Result.Id }

    $text = switch ($status) {
        '그대로'     { '그대로' }
        '건너뜀'     { '건너뜀' }
        '바꿈'       { if ([string]::IsNullOrEmpty($detail)) { '바꿈' } else { "바꿈 ($detail)" } }
        '다름'       { if ([string]::IsNullOrEmpty($detail)) { '다름' } else { "다름 ($detail)" } }
        '할 일'      { "할 일: $detail" }
        '실패'       { "실패: $detail" }
        '확인 못 함' { "확인 못 함: $detail" }
        default     { throw "알 수 없는 상태: $status" }
    }

    if (-not [string]::IsNullOrEmpty($stage) -and -not [string]::IsNullOrEmpty($id)) {
        return "[$stage] ${id}: $text"
    }
    return $text
}

function Format-SetupSummary {
    # → 끝 요약 줄들 [string[]]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Results,
        [int]$ElevationRequests = 0,
        [TimeSpan]$Duration = [TimeSpan]::Zero,
        [switch]$Check
    )

    $cnt = @{}
    foreach ($status in @('그대로', '바꿈', '다름', '할 일', '확인 못 함', '실패', '건너뜀')) {
        $cnt[$status] = 0
    }
    foreach ($r in $Results) {
        $s = if ($r -is [System.Collections.IDictionary]) { $r['Status'] } else { $r.Status }
        if ($cnt.ContainsKey($s)) {
            $cnt[$s]++
        }
    }

    $summaryParts = if ($Check) {
        @(
            "그대로 $($cnt['그대로'])"
            "다름 $($cnt['다름'])"
            "할 일 $($cnt['할 일'])"
            "확인 못 함 $($cnt['확인 못 함'])"
            "실패 $($cnt['실패'])"
            "건너뜀 $($cnt['건너뜀'])"
        )
    } else {
        @(
            "그대로 $($cnt['그대로'])"
            "바꿈 $($cnt['바꿈'])"
            "할 일 $($cnt['할 일'])"
            "실패 $($cnt['실패'])"
            "건너뜀 $($cnt['건너뜀'])"
        )
    }

    $totalHours = [int][Math]::Floor($Duration.TotalHours)
    $durationStr = if ($totalHours -ge 1) {
        "${totalHours}:$($Duration.Minutes.ToString('d2')):$($Duration.Seconds.ToString('d2'))"
    } else {
        "$($Duration.Minutes.ToString('d2')):$($Duration.Seconds.ToString('d2'))"
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("요약: $($summaryParts -join ' · ')")
    $lines.Add("승격 요청: ${ElevationRequests}회")
    $lines.Add("걸린 시간: $durationStr")

    $todoGroups = [ordered]@{}
    $hasTodo = $false
    $hasFail = $false

    foreach ($r in $Results) {
        $s = if ($r -is [System.Collections.IDictionary]) { $r['Status'] } else { $r.Status }
        $d = if ($r -is [System.Collections.IDictionary]) { $r['Detail'] } else { $r.Detail }
        $id = if ($r -is [System.Collections.IDictionary]) { $r['Id'] } else { $r.Id }

        if ($s -eq '할 일') {
            $hasTodo = $true
            if (-not $todoGroups.Contains($d)) {
                $todoGroups[$d] = [System.Collections.Generic.List[string]]::new()
            }
            $todoGroups[$d].Add($id)
        }
        if ($s -eq '실패') {
            $hasFail = $true
        }
    }

    if ($hasTodo) {
        $lines.Add("할 일:")
        foreach ($entry in $todoGroups.GetEnumerator()) {
            $idList = $entry.Value -join ', '
            $lines.Add("  - $($entry.Key) ($idList)")
        }
    }

    if ($hasFail) {
        $lines.Add("실패:")
        foreach ($r in $Results) {
            $s = if ($r -is [System.Collections.IDictionary]) { $r['Status'] } else { $r.Status }
            if ($s -eq '실패') {
                $d = if ($r -is [System.Collections.IDictionary]) { $r['Detail'] } else { $r.Detail }
                $id = if ($r -is [System.Collections.IDictionary]) { $r['Id'] } else { $r.Id }
                $stage = if ($r -is [System.Collections.IDictionary]) { $r['Stage'] } else { $r.Stage }
                $lines.Add("  - [$stage] ${id}: $d")
            }
        }
    }

    return [string[]]$lines.ToArray()
}

function Get-SetupExitCode {
    # 실패 0개 → 0, 1개 이상 → 1
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Results)

    foreach ($r in $Results) {
        $s = if ($r -is [System.Collections.IDictionary]) { $r['Status'] } else { $r.Status }
        if ($s -eq '실패') {
            return 1
        }
    }
    return 0
}

Export-ModuleMember -Function New-SetupResult, ConvertFrom-ResultText, Format-ResultLine, Format-SetupSummary, Get-SetupExitCode
