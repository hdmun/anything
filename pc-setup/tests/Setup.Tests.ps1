using module ../lib/Declaration.psm1

BeforeAll {
    $declarationPath = Join-Path $PSScriptRoot '..' 'lib' 'Declaration.psm1'
    Import-Module $declarationPath -Force
    $reportPath = Join-Path $PSScriptRoot '..' 'lib' 'Report.psm1'
    Import-Module $reportPath -Force
    $elevationPath = Join-Path $PSScriptRoot '..' 'lib' 'Elevation.psm1'
    Import-Module $elevationPath -Force
    $setupPath = Join-Path $PSScriptRoot '..' 'lib' 'Setup.psm1'
    Import-Module $setupPath -Force
}

Describe 'setup.ps1 진입점' {
    It '-Check 는 종료 코드 0 으로 끝난다' {
        $setup = Join-Path $PSScriptRoot '..' 'setup.ps1'
        pwsh -NoProfile -File $setup -Check
        $LASTEXITCODE | Should -Be 0
    }

    It '-Skip ''a, b'' 를 넘기면 Invoke-Setup 이 @(''a'',''b'') 를 받는다' {
        $setup = Join-Path $PSScriptRoot '..' 'setup.ps1'
        $output = pwsh -NoProfile -File $setup -Check -Skip 'a, b' 2>&1
        $LASTEXITCODE | Should -Be 2
        ($output -join "`n") | Should -Match '모르는 -Skip Id: a'
    }
}

Describe 'Invoke-Setup 표 1~16' {
    It '1: 관리자 창 + 고치는 실행 -> 2, Invoke 안 불림, 멈춤 문구' {
        Mock -ModuleName Setup Test-AdminWindow { return $true }
        $script:invoked1 = $false
        $p = { @(@{ Stage = 'S'; Id = '1'; Elevated = $false; Invoke = { $script:invoked1 = $true } }) }

        $script:lines = [System.Collections.Generic.List[string]]::new()
        Mock -ModuleName Setup Write-Host { $script:lines.Add([string]$Object) }

        $ret = Invoke-Setup -Root 'dummy' -StageProviders @($p)
        $ret | Should -Be 2
        $script:invoked1 | Should -BeFalse
        $script:lines | Should -Contain '셋업은 일반 권한 창에서 실행한다 (관리자 창이면 일부 앱 설치가 실패한다)'
    }

    It '2: 관리자 창 + -Check -> 계속 진행' {
        Mock -ModuleName Setup Test-AdminWindow { return $true }
        $script:invoked2 = $false
        $p = { @(@{ Stage = 'S'; Id = '1'; Elevated = $false; Invoke = { param($c) $script:invoked2 = $true; @{ Status = '그대로'; Detail = '' } } }) }

        $script:lines = [System.Collections.Generic.List[string]]::new()
        Mock -ModuleName Setup Write-Host { $script:lines.Add([string]$Object) }

        $ret = Invoke-Setup -Root 'dummy' -Check -StageProviders @($p)
        $ret | Should -Be 0
        $script:invoked2 | Should -BeTrue
    }

    It '3: 두 단계가 각각 DeclarationException -> 두 단계의 문제가 모두 출력, 2, Invoke 안 불림' {
        Mock -ModuleName Setup Test-AdminWindow { return $false }
        $p1 = { throw [DeclarationException]::new(@('문제 1')) }
        $p2 = { throw [DeclarationException]::new(@('문제 2')) }

        $script:lines = [System.Collections.Generic.List[string]]::new()
        Mock -ModuleName Setup Write-Host { $script:lines.Add([string]$Object) }

        $ret = Invoke-Setup -Root 'dummy' -StageProviders @($p1, $p2)
        $ret | Should -Be 2
        $script:lines | Should -Contain '선언 오류:'
        $script:lines | Should -Contain '  문제 1'
        $script:lines | Should -Contain '  문제 2'
    }

    It '4: 모르는 -Skip Id -> 2' {
        Mock -ModuleName Setup Test-AdminWindow { return $false }
        $p = { @(@{ Stage = 'S'; Id = 'item1'; Elevated = $false; Invoke = { @{ Status = '그대로'; Detail = '' } } }) }

        $script:lines = [System.Collections.Generic.List[string]]::new()
        Mock -ModuleName Setup Write-Host { $script:lines.Add([string]$Object) }

        $ret = Invoke-Setup -Root 'dummy' -Skip @('unknown_id') -StageProviders @($p)
        $ret | Should -Be 2
        $script:lines | Should -Contain '모르는 -Skip Id: unknown_id'
    }

    It '5: 고치는 실행, Elevated 항목 2 + 일반 항목 2 -> Invoke-ElevatedPhase 1번, 일반 항목은 $Check=$false 로 불림, 출력 순서는 승격 결과 -> 일반 결과, 요약 승격 요청: 1회' {
        Mock -ModuleName Setup Test-AdminWindow { return $false }
        Mock -ModuleName Setup Set-AnythingRepo {}

        $script:elevCallCount = 0
        Mock -ModuleName Setup Invoke-ElevatedPhase {
            $script:elevCallCount++
            return @{
                Requested = 1
                Results   = @(
                    [pscustomobject]@{ Stage = 'S'; Id = 'E1'; Status = '바꿈'; Detail = 'elev1' },
                    [pscustomobject]@{ Stage = 'S'; Id = 'E2'; Status = '그대로'; Detail = '' }
                )
                Error     = ''
            }
        }

        $script:n1Check = $null
        $script:n2Check = $null
        $items = @(
            @{ Stage = 'S'; Id = 'E1'; Elevated = $true; Invoke = { throw 'should not be called' } },
            @{ Stage = 'S'; Id = 'E2'; Elevated = $true; Invoke = { throw 'should not be called' } },
            @{ Stage = 'S'; Id = 'N1'; Elevated = $false; Invoke = { param($c) $script:n1Check = $c; @{ Status = '바꿈'; Detail = 'mod1' } } },
            @{ Stage = 'S'; Id = 'N2'; Elevated = $false; Invoke = { param($c) $script:n2Check = $c; @{ Status = '그대로'; Detail = '' } } }
        )
        $p = { $items }

        $script:lines = [System.Collections.Generic.List[string]]::new()
        Mock -ModuleName Setup Write-Host { $script:lines.Add([string]$Object) }

        $ret = Invoke-Setup -Root 'C:\repo\pc-setup' -StageProviders @($p)
        $ret | Should -Be 0
        $script:elevCallCount | Should -Be 1
        $script:n1Check | Should -BeFalse
        $script:n2Check | Should -BeFalse

        $e1Index = $script:lines.IndexOf('[S] E1: 바꿈 (elev1)')
        $e2Index = $script:lines.IndexOf('[S] E2: 그대로')
        $n1Index = $script:lines.IndexOf('[S] N1: 바꿈 (mod1)')
        $n2Index = $script:lines.IndexOf('[S] N2: 그대로')

        $e1Index | Should -BeGreaterThan -1
        $e2Index | Should -BeGreaterThan -1
        $n1Index | Should -BeGreaterThan $e2Index
        $n2Index | Should -BeGreaterThan $n1Index

        $script:lines | Should -Contain '승격 요청: 1회'
    }

    It '6-1: Elevated 항목 없음 -> Invoke-ElevatedPhase 안 불림, 승격 요청: 0회' {
        Mock -ModuleName Setup Test-AdminWindow { return $false }
        Mock -ModuleName Setup Set-AnythingRepo {}
        Mock -ModuleName Setup Invoke-ElevatedPhase { throw 'should not be called' }

        $p = { @(@{ Stage = 'S'; Id = 'N1'; Elevated = $false; Invoke = { @{ Status = '그대로'; Detail = '' } } }) }

        $script:lines = [System.Collections.Generic.List[string]]::new()
        Mock -ModuleName Setup Write-Host { $script:lines.Add([string]$Object) }

        $ret = Invoke-Setup -Root 'C:\repo\pc-setup' -StageProviders @($p)
        $ret | Should -Be 0
        $script:lines | Should -Contain '승격 요청: 0회'
    }

    It '6-2: Elevated 항목이 모두 -Skip -> Invoke-ElevatedPhase 안 불림, 승격 요청: 0회' {
        Mock -ModuleName Setup Test-AdminWindow { return $false }
        Mock -ModuleName Setup Set-AnythingRepo {}
        Mock -ModuleName Setup Invoke-ElevatedPhase { throw 'should not be called' }

        $p = { @(
            @{ Stage = 'S'; Id = 'E1'; Elevated = $true; Invoke = { throw 'should not be called' } },
            @{ Stage = 'S'; Id = 'N1'; Elevated = $false; Invoke = { @{ Status = '그대로'; Detail = '' } } }
        ) }

        $script:lines = [System.Collections.Generic.List[string]]::new()
        Mock -ModuleName Setup Write-Host { $script:lines.Add([string]$Object) }

        $ret = Invoke-Setup -Root 'C:\repo\pc-setup' -Skip @('E1') -StageProviders @($p)
        $ret | Should -Be 0
        $script:lines | Should -Contain '[S] E1: 건너뜀'
        $script:lines | Should -Contain '승격 요청: 0회'
    }

    It '7: Invoke-ElevatedPhase 가 Error=''승격 거부됨'' -> Elevated 항목 모두 실패: 승격 거부됨, 일반 항목은 처리됨, 종료 코드 1' {
        Mock -ModuleName Setup Test-AdminWindow { return $false }
        Mock -ModuleName Setup Set-AnythingRepo {}
        Mock -ModuleName Setup Invoke-ElevatedPhase {
            return @{ Requested = 1; Results = @(); Error = '승격 거부됨' }
        }

        $script:nInvoked7 = $false
        $p = { @(
            @{ Stage = 'S'; Id = 'E1'; Elevated = $true; Invoke = { throw 'should not be called' } },
            @{ Stage = 'S'; Id = 'N1'; Elevated = $false; Invoke = { $script:nInvoked7 = $true; @{ Status = '그대로'; Detail = '' } } }
        ) }

        $script:lines = [System.Collections.Generic.List[string]]::new()
        Mock -ModuleName Setup Write-Host { $script:lines.Add([string]$Object) }

        $ret = Invoke-Setup -Root 'C:\repo\pc-setup' -StageProviders @($p)
        $ret | Should -Be 1
        $script:nInvoked7 | Should -BeTrue
        $script:lines | Should -Contain '[S] E1: 실패: 승격 거부됨'
    }

    It '8: Results 에 Elevated 항목 하나가 빠짐 -> 그 항목 실패: 승격 단계 결과 없음' {
        Mock -ModuleName Setup Test-AdminWindow { return $false }
        Mock -ModuleName Setup Set-AnythingRepo {}
        Mock -ModuleName Setup Invoke-ElevatedPhase {
            return @{
                Requested = 1
                Results   = @([pscustomobject]@{ Stage = 'S'; Id = 'E1'; Status = '그대로'; Detail = '' })
                Error     = ''
            }
        }

        $p = { @(
            @{ Stage = 'S'; Id = 'E1'; Elevated = $true; Invoke = { throw 'should not be called' } },
            @{ Stage = 'S'; Id = 'E2'; Elevated = $true; Invoke = { throw 'should not be called' } }
        ) }

        $script:lines = [System.Collections.Generic.List[string]]::new()
        Mock -ModuleName Setup Write-Host { $script:lines.Add([string]$Object) }

        $ret = Invoke-Setup -Root 'C:\repo\pc-setup' -StageProviders @($p)
        $ret | Should -Be 1
        $script:lines | Should -Contain '[S] E1: 그대로'
        $script:lines | Should -Contain '[S] E2: 실패: 승격 단계 결과 없음'
    }

    It '9: -Check -> Invoke-ElevatedPhase 안 불림, 모든 항목이 $Check=$true 로 불림, Set-AnythingRepo 안 불림' {
        Mock -ModuleName Setup Test-AdminWindow { return $false }
        Mock -ModuleName Setup Invoke-ElevatedPhase { throw 'should not be called' }
        Mock -ModuleName Setup Set-AnythingRepo { throw 'should not be called' }

        $script:checks = @()
        $p = { @(
            @{ Stage = 'S'; Id = 'E1'; Elevated = $true; Invoke = { param($c) $script:checks += $c; @{ Status = '그대로'; Detail = '' } } },
            @{ Stage = 'S'; Id = 'N1'; Elevated = $false; Invoke = { param($c) $script:checks += $c; @{ Status = '그대로'; Detail = '' } } }
        ) }

        $script:lines = [System.Collections.Generic.List[string]]::new()
        Mock -ModuleName Setup Write-Host { $script:lines.Add([string]$Object) }

        $ret = Invoke-Setup -Root 'C:\repo\pc-setup' -Check -StageProviders @($p)
        $ret | Should -Be 0
        $script:checks.Count | Should -Be 2
        $script:checks[0] | Should -BeTrue
        $script:checks[1] | Should -BeTrue
    }

    It '10: -Skip 한 일반 항목 -> 건너뜀, 그 Invoke 안 불림' {
        Mock -ModuleName Setup Test-AdminWindow { return $false }
        Mock -ModuleName Setup Set-AnythingRepo {}

        $script:invoked10 = $false
        $p = { @(@{ Stage = 'S'; Id = 'N1'; Elevated = $false; Invoke = { $script:invoked10 = $true; @{ Status = '그대로'; Detail = '' } } }) }

        $script:lines = [System.Collections.Generic.List[string]]::new()
        Mock -ModuleName Setup Write-Host { $script:lines.Add([string]$Object) }

        $ret = Invoke-Setup -Root 'C:\repo\pc-setup' -Skip @('N1') -StageProviders @($p)
        $ret | Should -Be 0
        $script:invoked10 | Should -BeFalse
        $script:lines | Should -Contain '[S] N1: 건너뜀'
    }

    It '11: 항목 Invoke 가 예외 -> 실패: <메시지>, 다음 항목 계속' {
        Mock -ModuleName Setup Test-AdminWindow { return $false }
        Mock -ModuleName Setup Set-AnythingRepo {}

        $p = { @(
            @{ Stage = 'S'; Id = 'N1'; Elevated = $false; Invoke = { throw '오류 발생' } },
            @{ Stage = 'S'; Id = 'N2'; Elevated = $false; Invoke = { @{ Status = '그대로'; Detail = '' } } }
        ) }

        $script:lines = [System.Collections.Generic.List[string]]::new()
        Mock -ModuleName Setup Write-Host { $script:lines.Add([string]$Object) }

        $ret = Invoke-Setup -Root 'C:\repo\pc-setup' -StageProviders @($p)
        $ret | Should -Be 1
        $script:lines | Should -Contain '[S] N1: 실패: 오류 발생'
        $script:lines | Should -Contain '[S] N2: 그대로'
    }

    It '12: 고치는 실행에서 Invoke 가 다름 을 돌려줌 -> 실패: 모르는 결과: 다름' {
        Mock -ModuleName Setup Test-AdminWindow { return $false }
        Mock -ModuleName Setup Set-AnythingRepo {}

        $p = { @(@{ Stage = 'S'; Id = 'N1'; Elevated = $false; Invoke = { @{ Status = '다름'; Detail = '' } } }) }

        $script:lines = [System.Collections.Generic.List[string]]::new()
        Mock -ModuleName Setup Write-Host { $script:lines.Add([string]$Object) }

        $ret = Invoke-Setup -Root 'C:\repo\pc-setup' -StageProviders @($p)
        $ret | Should -Be 1
        $script:lines | Should -Contain '[S] N1: 실패: 모르는 결과: 다름'
    }

    It '13: Phase Elevated -> Elevated 항목만 불림, JSON 씀, 요약 없음, 0, 관리자 창이어도 멈추지 않음, Set-AnythingRepo 안 불림' {
        Mock -ModuleName Setup Test-AdminWindow { return $true }
        Mock -ModuleName Setup Set-AnythingRepo { throw 'should not be called' }

        $tempFile = Join-Path $env:TEMP "setup-test-$([System.Guid]::NewGuid()).json"
        try {
            $script:eInvoked13 = $false
            $script:nInvoked13 = $false
            $p = { @(
                @{ Stage = 'S'; Id = 'E1'; Elevated = $true; Invoke = { $script:eInvoked13 = $true; @{ Status = '그대로'; Detail = '' } } },
                @{ Stage = 'S'; Id = 'N1'; Elevated = $false; Invoke = { $script:nInvoked13 = $true; @{ Status = '그대로'; Detail = '' } } }
            ) }

            $script:lines = [System.Collections.Generic.List[string]]::new()
            Mock -ModuleName Setup Write-Host { $script:lines.Add([string]$Object) }

            $ret = Invoke-Setup -Root 'dummy' -Phase Elevated -ResultPath $tempFile -StageProviders @($p)
            $ret | Should -Be 0
            $script:eInvoked13 | Should -BeTrue
            $script:nInvoked13 | Should -BeFalse
            $script:lines | Should -Contain '[S] E1: 그대로'
            ($script:lines | Where-Object { $_ -like '요약:*' }).Count | Should -Be 0

            Test-Path -LiteralPath $tempFile | Should -BeTrue
            $saved = Get-Content -LiteralPath $tempFile -Raw | ConvertFrom-Json
            $saved.Check | Should -BeFalse
            $saved.ElevationRequests | Should -Be 1
            $saved.Results.Count | Should -Be 1
            $saved.Results[0].Id | Should -Be 'E1'
        } finally {
            if (Test-Path -LiteralPath $tempFile) {
                Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It '14: 고치는 실행 + -ResultPath -> JSON 에 결과·ElevationRequests·DurationSeconds·Check=false' {
        Mock -ModuleName Setup Test-AdminWindow { return $false }
        Mock -ModuleName Setup Set-AnythingRepo {}
        Mock -ModuleName Setup Write-Host {}

        $tempFile = Join-Path $env:TEMP "setup-test-$([System.Guid]::NewGuid()).json"
        try {
            $p = { @(@{ Stage = 'S'; Id = 'N1'; Elevated = $false; Invoke = { @{ Status = '그대로'; Detail = '' } } }) }

            $ret = Invoke-Setup -Root 'C:\repo\pc-setup' -ResultPath $tempFile -StageProviders @($p)
            $ret | Should -Be 0

            Test-Path -LiteralPath $tempFile | Should -BeTrue
            $saved = Get-Content -LiteralPath $tempFile -Raw | ConvertFrom-Json
            $saved.Check | Should -BeFalse
            $saved.ElevationRequests | Should -Be 0
            $saved.DurationSeconds | Should -BeGreaterOrEqual 0
            $saved.Results.Count | Should -Be 1
            $saved.Results[0].Id | Should -Be 'N1'
        } finally {
            if (Test-Path -LiteralPath $tempFile) {
                Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It '15: 고치는 실행, 실패 있음 -> Set-AnythingRepo 가 저장소 루트로 불림, 종료 코드 1' {
        Mock -ModuleName Setup Test-AdminWindow { return $false }
        Mock -ModuleName Setup Write-Host {}
        $script:repoPath = $null
        Mock -ModuleName Setup Set-AnythingRepo { param($Path) $script:repoPath = $Path }

        $p = { @(@{ Stage = 'S'; Id = 'N1'; Elevated = $false; Invoke = { @{ Status = '실패'; Detail = 'failed' } } }) }

        $ret = Invoke-Setup -Root 'C:\repo\pc-setup' -StageProviders @($p)
        $ret | Should -Be 1
        $script:repoPath | Should -Be 'C:\repo'
    }

    It '16: 단계 없음(StageProviders 빈 목록) + -Check -> 0, 요약 줄 출력' {
        Mock -ModuleName Setup Test-AdminWindow { return $false }

        $script:lines = [System.Collections.Generic.List[string]]::new()
        Mock -ModuleName Setup Write-Host { $script:lines.Add([string]$Object) }

        $ret = Invoke-Setup -Root 'C:\repo\pc-setup' -Check -StageProviders @()
        $ret | Should -Be 0
        ($script:lines | Where-Object { $_ -like '요약:*' }).Count | Should -Be 1
    }
}
