Import-Module (Join-Path $PSScriptRoot '..' 'lib' 'Declaration.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..' 'lib' 'Report.psm1') -Force

function Get-PropValue {
    param(
        $Object,
        [Parameter(Mandatory)][string]$Name,
        $Default = $null
    )

    if ($null -eq $Object) {
        return $Default
    }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) {
            return $Object[$Name]
        }
        return $Default
    }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -ne $prop) {
        return $prop.Value
    }
    return $Default
}

function Format-ResultTextOnly {
    param(
        [string]$Status,
        [string]$Detail = ''
    )

    $validStatuses = @('그대로', '바꿈', '할 일', '실패', '다름', '확인 못 함', '건너뜀')
    if ($validStatuses -contains $Status) {
        return (Format-ResultLine @{
            Stage  = ''
            Id     = ''
            Status = $Status
            Detail = $Detail
        })
    }
    if ([string]::IsNullOrEmpty($Status)) {
        return '알 수 없는 상태'
    }
    if ([string]::IsNullOrEmpty($Detail)) {
        return $Status
    }
    return "${Status}: $Detail"
}

function Format-SandboxDuration {
    param([double]$Seconds)

    $ts = [TimeSpan]::FromSeconds([Math]::Max(0, $Seconds))
    $totalHours = [int][Math]::Floor($ts.TotalHours)
    if ($totalHours -ge 1) {
        return "${totalHours}:$($ts.Minutes.ToString('d2')):$($ts.Seconds.ToString('d2'))"
    }
    return "$($ts.Minutes.ToString('d2')):$($ts.Seconds.ToString('d2'))"
}

function Read-SandboxExpected {
    # sandbox-expected.psd1 을 Read-Declaration 으로 읽는다 → 항목(Id, Result, Reason, Line)
    param([Parameter(Mandatory)][string]$Path)

    $schema = @{
        Key      = 'Id'
        Required = @('Id', 'Result', 'Reason')
        Allowed  = @('Id', 'Result', 'Reason')
        Enums    = @{ Result = @('건너뜀', '실패', '할 일') }
    }

    $items = Read-Declaration -Path $Path -Schema $schema
    return ,([pscustomobject[]]$items)
}

function Test-SandboxExpectedIds {
    # 예상 결과 Id 가운데 선언 Id 목록에 없는 것 → 문제 문자열 배열('sandbox-expected.psd1:<줄>: 선언에 없는 Id '<Id>'')
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Expected,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$DeclaredIds
    )

    $declaredSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($id in $DeclaredIds) {
        if (-not [string]::IsNullOrEmpty($id)) {
            $null = $declaredSet.Add($id)
        }
    }

    $problems = [System.Collections.Generic.List[string]]::new()
    foreach ($item in $Expected) {
        $id = [string](Get-PropValue -Object $item -Name 'Id' -Default '')
        $line = Get-PropValue -Object $item -Name 'Line' -Default 0
        if (-not $declaredSet.Contains($id)) {
            $problems.Add("sandbox-expected.psd1:${line}: 선언에 없는 Id '$id'")
        }
    }

    return ,([string[]]$problems.ToArray())
}

function Get-SandboxSkipIds {
    # Result 가 '건너뜀' 인 예상 결과 Id
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Expected)

    $skipIds = [System.Collections.Generic.List[string]]::new()
    foreach ($item in $Expected) {
        $result = [string](Get-PropValue -Object $item -Name 'Result' -Default '')
        if ($result -ceq '건너뜀') {
            $id = [string](Get-PropValue -Object $item -Name 'Id' -Default '')
            $skipIds.Add($id)
        }
    }

    return ,([string[]]$skipIds.ToArray())
}

function Test-SandboxRun {
    # Sandbox 안 스크립트가 쓴 result.json(객체) + 예상 결과 → 판정
    # → [pscustomobject]@{ Passed = [bool]; Failures = [string[]]; Warnings = [string[]]; Runs = [object[]]; ExpectedHits = [int] }
    param(
        [Parameter(Mandatory)]$Run,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Expected,
        [int]$FirstRunElevations = 2,
        [int]$RerunElevations = 1
    )

    $failures = [System.Collections.Generic.List[string]]::new()
    $warnings = [System.Collections.Generic.List[string]]::new()
    $runSummaries = [System.Collections.Generic.List[object]]::new()
    $expectedHits = 0

    $expectedById = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($exp in $Expected) {
        if ($null -eq $exp) { continue }
        $expId = [string](Get-PropValue -Object $exp -Name 'Id' -Default '')
        if (-not [string]::IsNullOrEmpty($expId) -and -not $expectedById.ContainsKey($expId)) {
            $expectedById[$expId] = $exp
        }
    }

    # 1. Run.Error 검사
    $runError = [string](Get-PropValue -Object $Run -Name 'Error' -Default '')
    if (-not [string]::IsNullOrEmpty($runError)) {
        $failures.Add("Sandbox 안 스크립트 오류: $runError")
    }

    $runsRaw = Get-PropValue -Object $Run -Name 'Runs' -Default $null
    $runsByName = @{}
    if ($null -ne $runsRaw) {
        foreach ($r in $runsRaw) {
            if ($null -eq $r) { continue }
            $rName = [string](Get-PropValue -Object $r -Name 'Name' -Default '')
            if (-not [string]::IsNullOrEmpty($rName) -and -not $runsByName.ContainsKey($rName)) {
                $runsByName[$rName] = $r
            }
        }
    }

    $summaryByName = @{}
    $setup1Ids = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($runName in @('bootstrap', 'setup-1', 'setup-2')) {
        if (-not $runsByName.ContainsKey($runName)) {
            $failures.Add("$runName 결과 없음 (실행 안 됨)")
            $summary = [pscustomobject]@{
                Name              = $runName
                ExitCode          = $null
                HasResult         = $false
                Counts            = $null
                ElevationRequests = 0
                DurationSeconds   = 0.0
            }
            $runSummaries.Add($summary)
            $summaryByName[$runName] = $summary
            continue
        }

        $runEntry = $runsByName[$runName]
        $exitCode = Get-PropValue -Object $runEntry -Name 'ExitCode' -Default $null
        $resultObj = Get-PropValue -Object $runEntry -Name 'Result' -Default $null

        if ($exitCode -eq 2) {
            $failures.Add("$runName 시작 못 함")
        } elseif ($null -eq $resultObj) {
            $exitText = if ($null -ne $exitCode) { [string]$exitCode } else { '없음' }
            $failures.Add("$runName 결과 없음 (종료 코드 $exitText)")
        }

        if ($null -eq $resultObj) {
            $summary = [pscustomobject]@{
                Name              = $runName
                ExitCode          = $exitCode
                HasResult         = $false
                Counts            = $null
                ElevationRequests = 0
                DurationSeconds   = 0.0
            }
            $runSummaries.Add($summary)
            $summaryByName[$runName] = $summary
            continue
        }

        $counts = @{
            '그대로' = 0
            '바꿈'   = 0
            '할 일'  = 0
            '실패'   = 0
            '건너뜀' = 0
        }

        $resultsList = Get-PropValue -Object $resultObj -Name 'Results' -Default $null
        if ($null -ne $resultsList) {
            foreach ($item in $resultsList) {
                if ($null -eq $item) { continue }
                $stage = [string](Get-PropValue -Object $item -Name 'Stage' -Default '')
                $id = [string](Get-PropValue -Object $item -Name 'Id' -Default '')
                $status = [string](Get-PropValue -Object $item -Name 'Status' -Default '')
                $detail = [string](Get-PropValue -Object $item -Name 'Detail' -Default '')

                if ($counts.ContainsKey($status)) {
                    $counts[$status]++
                }

                if ($runName -eq 'bootstrap') {
                    if ($status -in @('실패', '할 일')) {
                        $resultText = Format-ResultTextOnly -Status $status -Detail $detail
                        $failures.Add("[bootstrap] ${id}: $resultText")
                    }
                } else {
                    if ($runName -eq 'setup-1' -and -not [string]::IsNullOrEmpty($id)) {
                        $null = $setup1Ids.Add($id)
                    }

                    if ($expectedById.ContainsKey($id)) {
                        $expResult = [string](Get-PropValue -Object $expectedById[$id] -Name 'Result' -Default '')
                        if ($status -ceq $expResult) {
                            $expectedHits++
                        } elseif ($status -in @('그대로', '바꿈')) {
                            $warnings.Add("예상 결과 '$id' 가 필요 없어 보인다 ($runName 에서 $status)")
                        } else {
                            $resultText = Format-ResultTextOnly -Status $status -Detail $detail
                            $failures.Add("[$runName] [$stage] ${id}: $resultText (예상 $expResult)")
                        }
                    } else {
                        $isFail = if ($runName -eq 'setup-1') {
                            $status -ceq '실패'
                        } else {
                            $status -in @('바꿈', '실패')
                        }
                        if ($isFail) {
                            $resultText = Format-ResultTextOnly -Status $status -Detail $detail
                            $failures.Add("[$runName] [$stage] ${id}: $resultText")
                        }
                    }
                }
            }
        }

        $elevRequests = [int](Get-PropValue -Object $resultObj -Name 'ElevationRequests' -Default 0)
        $durationSec = [double](Get-PropValue -Object $resultObj -Name 'DurationSeconds' -Default 0)

        $summary = [pscustomobject]@{
            Name              = $runName
            ExitCode          = $exitCode
            HasResult         = $true
            Counts            = $counts
            ElevationRequests = $elevRequests
            DurationSeconds   = $durationSec
        }
        $runSummaries.Add($summary)
        $summaryByName[$runName] = $summary
    }

    # 5. 예상 결과 Id 가 setup-1 결과에 없는 경우
    $setup1Summary = $summaryByName['setup-1']
    if ($null -ne $setup1Summary -and $setup1Summary.HasResult) {
        foreach ($exp in $Expected) {
            if ($null -eq $exp) { continue }
            $expId = [string](Get-PropValue -Object $exp -Name 'Id' -Default '')
            if (-not $setup1Ids.Contains($expId)) {
                $warnings.Add("예상 결과 '$expId' 가 셋업 결과에 없다")
            }
        }
    }

    # 6. 승격 요청 횟수 검사
    $bootSummary = $summaryByName['bootstrap']
    if ($null -ne $bootSummary -and $bootSummary.HasResult -and $null -ne $setup1Summary -and $setup1Summary.HasResult) {
        $firstTotal = $bootSummary.ElevationRequests + $setup1Summary.ElevationRequests
        if ($firstTotal -ne $FirstRunElevations) {
            $failures.Add("승격 요청 횟수: 첫 실행 ${firstTotal}회 (기준 ${FirstRunElevations}회)")
        }
    }

    $setup2Summary = $summaryByName['setup-2']
    if ($null -ne $setup2Summary -and $setup2Summary.HasResult) {
        $rerunTotal = $setup2Summary.ElevationRequests
        if ($rerunTotal -ne $RerunElevations) {
            $failures.Add("승격 요청 횟수: 재실행 ${rerunTotal}회 (기준 ${RerunElevations}회)")
        }
    }

    return [pscustomobject]@{
        Passed       = ($failures.Count -eq 0)
        Failures     = [string[]]$failures.ToArray()
        Warnings     = [string[]]$warnings.ToArray()
        Runs         = [object[]]$runSummaries.ToArray()
        ExpectedHits = $expectedHits
    }
}

function Format-SandboxReport {
    # 판정 → 요약 표 줄들 [string[]]
    param([Parameter(Mandatory)]$Judgment)

    $passed = [bool](Get-PropValue -Object $Judgment -Name 'Passed' -Default $false)
    $verdict = if ($passed) { '합격' } else { '불합격' }

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("Sandbox 판정: $verdict")
    $lines.Add('실행       종료  그대로  바꿈  할 일  실패  건너뜀  승격  시간')

    $runs = Get-PropValue -Object $Judgment -Name 'Runs' -Default @()
    if ($null -ne $runs) {
        foreach ($r in $runs) {
            $name = [string](Get-PropValue -Object $r -Name 'Name' -Default '')
            $exitVal = Get-PropValue -Object $r -Name 'ExitCode' -Default $null
            $exitStr = if ($null -ne $exitVal) { [string]$exitVal } else { '-' }
            $hasResult = [bool](Get-PropValue -Object $r -Name 'HasResult' -Default $false)

            if ($hasResult) {
                $counts = Get-PropValue -Object $r -Name 'Counts' -Default @{}
                $same = [string](Get-PropValue -Object $counts -Name '그대로' -Default 0)
                $changed = [string](Get-PropValue -Object $counts -Name '바꿈' -Default 0)
                $todo = [string](Get-PropValue -Object $counts -Name '할 일' -Default 0)
                $fail = [string](Get-PropValue -Object $counts -Name '실패' -Default 0)
                $skip = [string](Get-PropValue -Object $counts -Name '건너뜀' -Default 0)
                $elev = [string](Get-PropValue -Object $r -Name 'ElevationRequests' -Default 0)
                $dur = Format-SandboxDuration -Seconds ([double](Get-PropValue -Object $r -Name 'DurationSeconds' -Default 0))
            } else {
                $same = '-'
                $changed = '-'
                $todo = '-'
                $fail = '-'
                $skip = '-'
                $elev = '-'
                $dur = '-'
            }

            $row = '{0,-10} {1,-5} {2,-7} {3,-5} {4,-6} {5,-5} {6,-7} {7,-5} {8}' -f $name, $exitStr, $same, $changed, $todo, $fail, $skip, $elev, $dur
            $lines.Add($row)
        }
    }

    $expectedHits = [int](Get-PropValue -Object $Judgment -Name 'ExpectedHits' -Default 0)
    $lines.Add("예상 결과로 뺀 결과: ${expectedHits}개")

    $warnings = Get-PropValue -Object $Judgment -Name 'Warnings' -Default @()
    if ($null -ne $warnings -and @($warnings).Count -gt 0) {
        $lines.Add('경고:')
        foreach ($w in $warnings) {
            $lines.Add("  - $w")
        }
    }

    $failures = Get-PropValue -Object $Judgment -Name 'Failures' -Default @()
    if (-not $passed -and $null -ne $failures -and @($failures).Count -gt 0) {
        $lines.Add('불합격 이유:')
        foreach ($f in $failures) {
            $lines.Add("  - $f")
        }
    }

    return ,([string[]]$lines.ToArray())
}

Export-ModuleMember -Function Read-SandboxExpected, Test-SandboxExpectedIds, Get-SandboxSkipIds, Test-SandboxRun, Format-SandboxReport
