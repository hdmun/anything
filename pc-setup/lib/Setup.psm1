Import-Module (Join-Path $PSScriptRoot 'Report.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Elevation.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Declaration.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'WindowsSettings.psm1') -Force

$script:DefaultStageProviders = @(
    { param($Root) Get-WindowsSettingItems -Root $Root }
)

function Set-AnythingRepo {
    # 사용자 환경 변수 ANYTHING_REPO 를 $Path 로 쓴다. 테스트는 이 함수를 Mock 한다.
    param([Parameter(Mandatory)][string]$Path)

    [System.Environment]::SetEnvironmentVariable('ANYTHING_REPO', $Path, [System.EnvironmentVariableTarget]::User)
    $env:ANYTHING_REPO = $Path
}

function Invoke-Setup {
    # → 종료 코드 [int]. 결과 줄과 요약은 Write-Host 로 출력한다.
    param(
        [Parameter(Mandatory)][string]$Root,                 # pc-setup 폴더
        [switch]$Check,
        [string[]]$Skip = @(),
        [string]$Phase = '',                                 # '' 또는 'Elevated'
        [string]$ResultPath = '',
        [scriptblock[]]$StageProviders = $script:DefaultStageProviders   # 각각 param($Root) → 항목 목록
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    # 1. 관리자 창 검사
    if ((Test-AdminWindow) -and (-not $Check) -and ($Phase -ne 'Elevated')) {
        Write-Host '셋업은 일반 권한 창에서 실행한다 (관리자 창이면 일부 앱 설치가 실패한다)'
        return 2
    }

    # 2. 선언 검사
    $allItems = [System.Collections.Generic.List[object]]::new()
    $allProblems = [System.Collections.Generic.List[string]]::new()

    if ($null -ne $StageProviders) {
        foreach ($provider in $StageProviders) {
            try {
                $items = & $provider $Root
                if ($null -ne $items) {
                    foreach ($it in $items) {
                        $allItems.Add($it)
                    }
                }
            }
            catch {
                $ex = $_.Exception
                while ($null -ne $ex) {
                    if ($ex.GetType().Name -eq 'DeclarationException' -or $ex.PSObject.Properties['Problems']) {
                        break
                    }
                    $ex = $ex.InnerException
                }
                if ($null -ne $ex -and $null -ne $ex.Problems) {
                    foreach ($p in $ex.Problems) {
                        $allProblems.Add($p)
                    }
                } else {
                    throw
                }
            }
        }
    }

    if ($allProblems.Count -gt 0) {
        Write-Host '선언 오류:'
        foreach ($p in $allProblems) {
            Write-Host "  $p"
        }
        return 2
    }

    # 3. -Skip 검사
    $normalizedSkip = [System.Collections.Generic.List[string]]::new()
    if ($null -ne $Skip) {
        foreach ($s in $Skip) {
            foreach ($part in ($s -split ',')) {
                $trimmed = $part.Trim()
                if ($trimmed -ne '') {
                    $normalizedSkip.Add($trimmed)
                }
            }
        }
    }

    $knownIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($item in $allItems) {
        $idVal = if ($item -is [System.Collections.IDictionary]) { $item['Id'] } else { $item.Id }
        if (-not [string]::IsNullOrEmpty($idVal)) {
            $null = $knownIds.Add($idVal)
        }
    }

    foreach ($skipId in $normalizedSkip) {
        if (-not $knownIds.Contains($skipId)) {
            Write-Host "모르는 -Skip Id: $skipId"
            return 2
        }
    }

    # 4. Phase Elevated
    if ($Phase -eq 'Elevated') {
        $elevatedResults = [System.Collections.Generic.List[object]]::new()
        foreach ($item in $allItems) {
            $itemElevated = if ($item -is [System.Collections.IDictionary]) { $item['Elevated'] } else { $item.Elevated }
            if ($itemElevated -ne $true) {
                continue
            }

            $itemId = if ($item -is [System.Collections.IDictionary]) { $item['Id'] } else { $item.Id }
            $itemStage = if ($item -is [System.Collections.IDictionary]) { $item['Stage'] } else { $item.Stage }
            $itemInvoke = if ($item -is [System.Collections.IDictionary]) { $item['Invoke'] } else { $item.Invoke }

            $r = $null
            if ($normalizedSkip -contains $itemId) {
                $r = New-SetupResult -Stage $itemStage -Id $itemId -Status '건너뜀' -Detail ''
            } else {
                try {
                    $res = & $itemInvoke $false
                    $status = if ($res -is [System.Collections.IDictionary]) { $res['Status'] } else { $res.Status }
                    $detail = if ($res -is [System.Collections.IDictionary]) { $res['Detail'] } else { $res.Detail }

                    if ([string]::IsNullOrEmpty($status) -or @('그대로', '바꿈', '할 일', '실패', '건너뜀') -notcontains $status) {
                        $r = New-SetupResult -Stage $itemStage -Id $itemId -Status '실패' -Detail "모르는 결과: $status"
                    } else {
                        $r = New-SetupResult -Stage $itemStage -Id $itemId -Status $status -Detail ($detail ?? '')
                    }
                } catch {
                    $r = New-SetupResult -Stage $itemStage -Id $itemId -Status '실패' -Detail $_.Exception.Message
                }
            }
            Write-Host (Format-ResultLine $r)
            $elevatedResults.Add($r)
        }

        if (-not [string]::IsNullOrEmpty($ResultPath)) {
            $jsonObj = [ordered]@{
                Check             = $false
                ElevationRequests = 1
                DurationSeconds   = [Math]::Round($stopwatch.Elapsed.TotalSeconds, 1)
                Results           = [object[]]$elevatedResults.ToArray()
            }
            $jsonText = $jsonObj | ConvertTo-Json -Depth 5
            [System.IO.File]::WriteAllText($ResultPath, $jsonText, [System.Text.Encoding]::UTF8)
        }
        return 0
    }

    # 5. 승격 단계 & 6. 일반 단계
    $allResults = [System.Collections.Generic.List[object]]::new()
    $totalElevationRequests = 0

    if (-not $Check) {
        # 5. 승격 단계 (고치는 실행)
        $elevatedItems = [System.Collections.Generic.List[object]]::new()
        $unskippedElevatedCount = 0
        foreach ($item in $allItems) {
            $itemElevated = if ($item -is [System.Collections.IDictionary]) { $item['Elevated'] } else { $item.Elevated }
            if ($itemElevated -eq $true) {
                $elevatedItems.Add($item)
                $itemId = if ($item -is [System.Collections.IDictionary]) { $item['Id'] } else { $item.Id }
                if (-not ($normalizedSkip -contains $itemId)) {
                    $unskippedElevatedCount++
                }
            }
        }

        if ($unskippedElevatedCount -gt 0) {
            $setupScript = Join-Path $Root 'setup.ps1'
            $elevatedOutcome = Invoke-ElevatedPhase -SetupScript $setupScript -Skip ([string[]]$normalizedSkip.ToArray())
            $totalElevationRequests += $elevatedOutcome.Requested

            foreach ($item in $elevatedItems) {
                $itemId = if ($item -is [System.Collections.IDictionary]) { $item['Id'] } else { $item.Id }
                $itemStage = if ($item -is [System.Collections.IDictionary]) { $item['Stage'] } else { $item.Stage }

                $r = $null
                if ($normalizedSkip -contains $itemId) {
                    $r = New-SetupResult -Stage $itemStage -Id $itemId -Status '건너뜀' -Detail ''
                } elseif (-not [string]::IsNullOrEmpty($elevatedOutcome.Error)) {
                    $r = New-SetupResult -Stage $itemStage -Id $itemId -Status '실패' -Detail $elevatedOutcome.Error
                } else {
                    $matched = $null
                    if ($null -ne $elevatedOutcome.Results) {
                        foreach ($resObj in $elevatedOutcome.Results) {
                            $resId = if ($resObj -is [System.Collections.IDictionary]) { $resObj['Id'] } else { $resObj.Id }
                            if ($resId -eq $itemId) {
                                $matched = $resObj
                                break
                            }
                        }
                    }
                    if ($null -ne $matched) {
                        $mStatus = if ($matched -is [System.Collections.IDictionary]) { $matched['Status'] } else { $matched.Status }
                        $mDetail = if ($matched -is [System.Collections.IDictionary]) { $matched['Detail'] } else { $matched.Detail }
                        $r = New-SetupResult -Stage $itemStage -Id $itemId -Status $mStatus -Detail ($mDetail ?? '')
                    } else {
                        $r = New-SetupResult -Stage $itemStage -Id $itemId -Status '실패' -Detail '승격 단계 결과 없음'
                    }
                }
                Write-Host (Format-ResultLine $r)
                $allResults.Add($r)
            }
        } else {
            foreach ($item in $elevatedItems) {
                $itemId = if ($item -is [System.Collections.IDictionary]) { $item['Id'] } else { $item.Id }
                $itemStage = if ($item -is [System.Collections.IDictionary]) { $item['Stage'] } else { $item.Stage }
                $r = New-SetupResult -Stage $itemStage -Id $itemId -Status '건너뜀' -Detail ''
                Write-Host (Format-ResultLine $r)
                $allResults.Add($r)
            }
        }

        # 6. 일반 단계 (고치는 실행: Elevated 가 아닌 항목)
        foreach ($item in $allItems) {
            $itemElevated = if ($item -is [System.Collections.IDictionary]) { $item['Elevated'] } else { $item.Elevated }
            if ($itemElevated -eq $true) {
                continue
            }

            $itemId = if ($item -is [System.Collections.IDictionary]) { $item['Id'] } else { $item.Id }
            $itemStage = if ($item -is [System.Collections.IDictionary]) { $item['Stage'] } else { $item.Stage }
            $itemInvoke = if ($item -is [System.Collections.IDictionary]) { $item['Invoke'] } else { $item.Invoke }

            $r = $null
            if ($normalizedSkip -contains $itemId) {
                $r = New-SetupResult -Stage $itemStage -Id $itemId -Status '건너뜀' -Detail ''
            } else {
                try {
                    $res = & $itemInvoke $false
                    $status = if ($res -is [System.Collections.IDictionary]) { $res['Status'] } else { $res.Status }
                    $detail = if ($res -is [System.Collections.IDictionary]) { $res['Detail'] } else { $res.Detail }

                    if ([string]::IsNullOrEmpty($status) -or @('그대로', '바꿈', '할 일', '실패', '건너뜀') -notcontains $status) {
                        $r = New-SetupResult -Stage $itemStage -Id $itemId -Status '실패' -Detail "모르는 결과: $status"
                    } else {
                        $r = New-SetupResult -Stage $itemStage -Id $itemId -Status $status -Detail ($detail ?? '')
                    }
                } catch {
                    $r = New-SetupResult -Stage $itemStage -Id $itemId -Status '실패' -Detail $_.Exception.Message
                }
            }
            Write-Host (Format-ResultLine $r)
            $allResults.Add($r)
        }
    } else {
        # -Check 모드: 모든 항목을 순서대로 처리
        foreach ($item in $allItems) {
            $itemId = if ($item -is [System.Collections.IDictionary]) { $item['Id'] } else { $item.Id }
            $itemStage = if ($item -is [System.Collections.IDictionary]) { $item['Stage'] } else { $item.Stage }
            $itemInvoke = if ($item -is [System.Collections.IDictionary]) { $item['Invoke'] } else { $item.Invoke }

            $r = $null
            if ($normalizedSkip -contains $itemId) {
                $r = New-SetupResult -Stage $itemStage -Id $itemId -Status '건너뜀' -Detail ''
            } else {
                try {
                    $res = & $itemInvoke $true
                    $status = if ($res -is [System.Collections.IDictionary]) { $res['Status'] } else { $res.Status }
                    $detail = if ($res -is [System.Collections.IDictionary]) { $res['Detail'] } else { $res.Detail }

                    if ([string]::IsNullOrEmpty($status) -or @('그대로', '다름', '할 일', '확인 못 함', '실패', '건너뜀') -notcontains $status) {
                        $r = New-SetupResult -Stage $itemStage -Id $itemId -Status '실패' -Detail "모르는 결과: $status"
                    } else {
                        $r = New-SetupResult -Stage $itemStage -Id $itemId -Status $status -Detail ($detail ?? '')
                    }
                } catch {
                    $r = New-SetupResult -Stage $itemStage -Id $itemId -Status '실패' -Detail $_.Exception.Message
                }
            }
            Write-Host (Format-ResultLine $r)
            $allResults.Add($r)
        }
    }

    # 7. 끝
    $summaryLines = Format-SetupSummary -Results ([object[]]$allResults.ToArray()) -ElevationRequests $totalElevationRequests -Duration $stopwatch.Elapsed -Check:$Check
    foreach ($line in $summaryLines) {
        Write-Host $line
    }

    if (-not $Check) {
        Set-AnythingRepo (Split-Path $Root -Parent)
    }

    if (-not [string]::IsNullOrEmpty($ResultPath)) {
        $jsonObj = [ordered]@{
            Check             = [bool]$Check
            ElevationRequests = $totalElevationRequests
            DurationSeconds   = [Math]::Round($stopwatch.Elapsed.TotalSeconds, 1)
            Results           = [object[]]$allResults.ToArray()
        }
        $jsonText = $jsonObj | ConvertTo-Json -Depth 5
        [System.IO.File]::WriteAllText($ResultPath, $jsonText, [System.Text.Encoding]::UTF8)
    }

    return (Get-SetupExitCode -Results ([object[]]$allResults.ToArray()))
}

Export-ModuleMember -Function Invoke-Setup, Set-AnythingRepo
