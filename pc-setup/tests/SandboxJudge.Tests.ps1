using module ../lib/Declaration.psm1

BeforeAll {
    $declarationPath = Join-Path $PSScriptRoot '..' 'lib' 'Declaration.psm1'
    Import-Module $declarationPath -Force
    $reportPath = Join-Path $PSScriptRoot '..' 'lib' 'Report.psm1'
    Import-Module $reportPath -Force
    $judgePath = Join-Path $PSScriptRoot '..' 'test' 'SandboxJudge.psm1'
    Import-Module $judgePath -Force

    function script:New-RunResultObj {
        param(
            [string]$Name,
            [int]$ExitCode = 0,
            [object[]]$Results = @(),
            [int]$ElevationRequests = 1,
            [double]$DurationSeconds = 10.0,
            [bool]$NullResult = $false
        )

        if ($NullResult) {
            return [pscustomobject]@{
                Name     = $Name
                ExitCode = $ExitCode
                Result   = $null
            }
        }

        return [pscustomobject]@{
            Name     = $Name
            ExitCode = $ExitCode
            Result   = [pscustomobject]@{
                Check             = $false
                ElevationRequests = $ElevationRequests
                DurationSeconds   = $DurationSeconds
                Results           = $Results
            }
        }
    }

    function script:New-ItemResult {
        param(
            [string]$Stage = 'Windows 설정',
            [string]$Id,
            [string]$Status = '그대로',
            [string]$Detail = ''
        )
        return [pscustomobject]@{
            Stage  = $Stage
            Id     = $Id
            Status = $Status
            Detail = $Detail
        }
    }

    function script:New-DefaultBootstrapResults {
        return @(
            (New-ItemResult -Stage '부트스트랩' -Id 'winget' -Status '그대로')
            (New-ItemResult -Stage '부트스트랩' -Id 'Git.Git' -Status '바꿈')
            (New-ItemResult -Stage '부트스트랩' -Id 'Microsoft.PowerShell' -Status '바꿈')
            (New-ItemResult -Stage '부트스트랩' -Id 'clone' -Status '바꿈')
        )
    }

    function script:New-DefaultRun {
        param(
            [string]$ErrorText = '',
            [object[]]$BootstrapResults = (New-DefaultBootstrapResults),
            [object[]]$Setup1Results = @(
                (New-ItemResult -Id 'LongPaths' -Status '바꿈')
                (New-ItemResult -Id 'DarkModeApps' -Status '바꿈')
            ),
            [object[]]$Setup2Results = @(
                (New-ItemResult -Id 'LongPaths' -Status '그대로')
                (New-ItemResult -Id 'DarkModeApps' -Status '그대로')
            ),
            [int]$BootElev = 1,
            [int]$Setup1Elev = 1,
            [int]$Setup2Elev = 1
        )

        return [pscustomobject]@{
            Error = $ErrorText
            Runs  = @(
                (New-RunResultObj -Name 'bootstrap' -ExitCode 0 -Results $BootstrapResults -ElevationRequests $BootElev -DurationSeconds 95.2)
                (New-RunResultObj -Name 'setup-1' -ExitCode 0 -Results $Setup1Results -ElevationRequests $Setup1Elev -DurationSeconds 2290.0)
                (New-RunResultObj -Name 'setup-2' -ExitCode 0 -Results $Setup2Results -ElevationRequests $Setup2Elev -DurationSeconds 362.0)
            )
        }
    }
}

Describe 'Test-SandboxRun 표 1~17' {
    It '1: 세 실행 모두 정상, 첫 실행 바꿈 여럿, 재실행 모두 그대로, 승격 1·1·1 -> 합격' {
        $run = New-DefaultRun
        $j = Test-SandboxRun -Run $run -Expected @()
        $j.Passed | Should -BeTrue
        $j.Failures.Count | Should -Be 0
        $j.Warnings.Count | Should -Be 0
        $j.ExpectedHits | Should -Be 0
    }

    It '2: Error 있음 -> 불합격 Sandbox 안 스크립트 오류: …' {
        $run = New-DefaultRun -ErrorText '권한 오류'
        $j = Test-SandboxRun -Run $run -Expected @()
        $j.Passed | Should -BeFalse
        $j.Failures | Should -Contain 'Sandbox 안 스크립트 오류: 권한 오류'
    }

    It '3: setup-2 없음 -> 불합격 setup-2 결과 없음 (실행 안 됨)' {
        $run = [pscustomobject]@{
            Error = ''
            Runs  = @(
                (New-RunResultObj -Name 'bootstrap' -Results (New-DefaultBootstrapResults))
                (New-RunResultObj -Name 'setup-1' -Results @((New-ItemResult -Id 'LongPaths' -Status '바꿈')))
            )
        }
        $j = Test-SandboxRun -Run $run -Expected @()
        $j.Passed | Should -BeFalse
        $j.Failures | Should -Contain 'setup-2 결과 없음 (실행 안 됨)'
    }

    It '4: setup-1 의 Result 가 null, 종료 코드 1 -> 불합격 setup-1 결과 없음 (종료 코드 1)' {
        $run = [pscustomobject]@{
            Error = ''
            Runs  = @(
                (New-RunResultObj -Name 'bootstrap' -Results (New-DefaultBootstrapResults))
                (New-RunResultObj -Name 'setup-1' -ExitCode 1 -NullResult $true)
                (New-RunResultObj -Name 'setup-2' -Results @((New-ItemResult -Id 'LongPaths' -Status '그대로')))
            )
        }
        $j = Test-SandboxRun -Run $run -Expected @()
        $j.Passed | Should -BeFalse
        $j.Failures | Should -Contain 'setup-1 결과 없음 (종료 코드 1)'
    }

    It '5: setup-1 종료 코드 2 -> 불합격 setup-1 시작 못 함' {
        $run = [pscustomobject]@{
            Error = ''
            Runs  = @(
                (New-RunResultObj -Name 'bootstrap' -Results (New-DefaultBootstrapResults))
                (New-RunResultObj -Name 'setup-1' -ExitCode 2 -NullResult $true)
                (New-RunResultObj -Name 'setup-2' -Results @((New-ItemResult -Id 'LongPaths' -Status '그대로')))
            )
        }
        $j = Test-SandboxRun -Run $run -Expected @()
        $j.Passed | Should -BeFalse
        $j.Failures | Should -Contain 'setup-1 시작 못 함'
        $j.Failures | Should -Not -Contain 'setup-1 결과 없음 (종료 코드 2)'
    }

    It '6: bootstrap 의 clone 이 실패: … -> 불합격' {
        $boot = @(
            (New-ItemResult -Stage '부트스트랩' -Id 'winget' -Status '그대로')
            (New-ItemResult -Stage '부트스트랩' -Id 'clone' -Status '실패' -Detail 'git clone 종료 코드 128')
        )
        $run = New-DefaultRun -BootstrapResults $boot
        $j = Test-SandboxRun -Run $run -Expected @()
        $j.Passed | Should -BeFalse
        $j.Failures | Should -Contain '[bootstrap] clone: 실패: git clone 종료 코드 128'
    }

    It '7: 예상 없음, setup-1 에 실패 -> 불합격' {
        $s1 = @(
            (New-ItemResult -Stage 'Windows 설정' -Id 'LongPaths' -Status '실패' -Detail '접근 거부')
        )
        $s2 = @(
            (New-ItemResult -Stage 'Windows 설정' -Id 'LongPaths' -Status '그대로')
        )
        $run = New-DefaultRun -Setup1Results $s1 -Setup2Results $s2
        $j = Test-SandboxRun -Run $run -Expected @()
        $j.Passed | Should -BeFalse
        $j.Failures | Should -Contain '[setup-1] [Windows 설정] LongPaths: 실패: 접근 거부'
    }

    It '8: 예상 없음, setup-2 에 바꿈 -> 불합격' {
        $s1 = @(
            (New-ItemResult -Stage 'Windows 설정' -Id 'LongPaths' -Status '바꿈')
        )
        $s2 = @(
            (New-ItemResult -Stage 'Windows 설정' -Id 'LongPaths' -Status '바꿈' -Detail '다시 씀')
        )
        $run = New-DefaultRun -Setup1Results $s1 -Setup2Results $s2
        $j = Test-SandboxRun -Run $run -Expected @()
        $j.Passed | Should -BeFalse
        $j.Failures | Should -Contain '[setup-2] [Windows 설정] LongPaths: 바꿈 (다시 씀)'
    }

    It '9: 예상 없음, setup-2 에 할 일 -> 합격' {
        $s1 = @(
            (New-ItemResult -Stage '앱' -Id 'wsl' -Status '할 일' -Detail '재부팅 후 셋업 다시 실행')
        )
        $s2 = @(
            (New-ItemResult -Stage '앱' -Id 'wsl' -Status '할 일' -Detail '재부팅 후 셋업 다시 실행')
        )
        $run = New-DefaultRun -Setup1Results $s1 -Setup2Results $s2
        $j = Test-SandboxRun -Run $run -Expected @()
        $j.Passed | Should -BeTrue
        $j.Failures.Count | Should -Be 0
    }

    It '10: 예상 실패, 두 실행 모두 실패 -> 합격, ExpectedHits 2' {
        $expected = @(
            [pscustomobject]@{ Id = 'iCloud'; Result = '실패'; Reason = 'Store 없음'; Line = 3 }
        )
        $s1 = @(
            (New-ItemResult -Stage '앱' -Id 'iCloud' -Status '실패' -Detail 'Store 없음')
        )
        $s2 = @(
            (New-ItemResult -Stage '앱' -Id 'iCloud' -Status '실패' -Detail 'Store 없음')
        )
        $run = New-DefaultRun -Setup1Results $s1 -Setup2Results $s2
        $j = Test-SandboxRun -Run $run -Expected $expected
        $j.Passed | Should -BeTrue
        $j.ExpectedHits | Should -Be 2
        $j.Warnings.Count | Should -Be 0
    }

    It '11: 예상 건너뜀, 두 실행 모두 건너뜀 -> 합격' {
        $expected = @(
            [pscustomobject]@{ Id = 'wsl'; Result = '건너뜀'; Reason = 'Sandbox 불가'; Line = 3 }
        )
        $s1 = @(
            (New-ItemResult -Stage '앱' -Id 'wsl' -Status '건너뜀')
        )
        $s2 = @(
            (New-ItemResult -Stage '앱' -Id 'wsl' -Status '건너뜀')
        )
        $run = New-DefaultRun -Setup1Results $s1 -Setup2Results $s2
        $j = Test-SandboxRun -Run $run -Expected $expected
        $j.Passed | Should -BeTrue
        $j.ExpectedHits | Should -Be 2
    }

    It '12: 예상 실패, 실제 그대로 -> 합격 + 경고 예상 결과 ''<Id>'' 가 필요 없어 보인다 (...)' {
        $expected = @(
            [pscustomobject]@{ Id = 'iCloud'; Result = '실패'; Reason = 'Store 없음'; Line = 3 }
        )
        $s1 = @(
            (New-ItemResult -Stage '앱' -Id 'iCloud' -Status '그대로')
        )
        $s2 = @(
            (New-ItemResult -Stage '앱' -Id 'iCloud' -Status '그대로')
        )
        $run = New-DefaultRun -Setup1Results $s1 -Setup2Results $s2
        $j = Test-SandboxRun -Run $run -Expected $expected
        $j.Passed | Should -BeTrue
        $j.Warnings | Should -Contain "예상 결과 'iCloud' 가 필요 없어 보인다 (setup-1 에서 그대로)"
        $j.Warnings | Should -Contain "예상 결과 'iCloud' 가 필요 없어 보인다 (setup-2 에서 그대로)"
    }

    It '13: 예상 할 일, 실제 실패 -> 불합격 (예상 할 일)' {
        $expected = @(
            [pscustomobject]@{ Id = 'wsl'; Result = '할 일'; Reason = '재부팅 필요'; Line = 3 }
        )
        $s1 = @(
            (New-ItemResult -Stage '앱' -Id 'wsl' -Status '실패' -Detail '설치 실패')
        )
        $s2 = @(
            (New-ItemResult -Stage '앱' -Id 'wsl' -Status '할 일' -Detail '재부팅 필요')
        )
        $run = New-DefaultRun -Setup1Results $s1 -Setup2Results $s2
        $j = Test-SandboxRun -Run $run -Expected $expected
        $j.Passed | Should -BeFalse
        $j.Failures | Should -Contain '[setup-1] [앱] wsl: 실패: 설치 실패 (예상 할 일)'
    }

    It '14: 예상 Id 가 결과에 없음 -> 경고 … 셋업 결과에 없다' {
        $expected = @(
            [pscustomobject]@{ Id = 'GhostItem'; Result = '실패'; Reason = '없음'; Line = 3 }
        )
        $run = New-DefaultRun
        $j = Test-SandboxRun -Run $run -Expected $expected
        $j.Passed | Should -BeTrue
        $j.Warnings | Should -Contain "예상 결과 'GhostItem' 가 셋업 결과에 없다"
    }

    It '15: 첫 실행 승격 3회 -> 불합격 승격 요청 횟수: 첫 실행 3회 (기준 2회)' {
        $run = New-DefaultRun -BootElev 2 -Setup1Elev 1 -Setup2Elev 1
        $j = Test-SandboxRun -Run $run -Expected @()
        $j.Passed | Should -BeFalse
        $j.Failures | Should -Contain '승격 요청 횟수: 첫 실행 3회 (기준 2회)'
    }

    It '16: 재실행 승격 0회 -> 불합격 … 재실행 0회 (기준 1회)' {
        $run = New-DefaultRun -BootElev 1 -Setup1Elev 1 -Setup2Elev 0
        $j = Test-SandboxRun -Run $run -Expected @()
        $j.Passed | Should -BeFalse
        $j.Failures | Should -Contain '승격 요청 횟수: 재실행 0회 (기준 1회)'
    }

    It '17: 불합격 이유 여럿 -> 모두 Failures 에 담김' {
        $boot = @(
            (New-ItemResult -Stage '부트스트랩' -Id 'clone' -Status '실패' -Detail 'clone 오류')
        )
        $s1 = @(
            (New-ItemResult -Stage 'Windows 설정' -Id 'LongPaths' -Status '실패' -Detail '거부')
        )
        $s2 = @(
            (New-ItemResult -Stage 'Windows 설정' -Id 'LongPaths' -Status '바꿈')
        )
        $run = New-DefaultRun -ErrorText '스크립트 중단' -BootstrapResults $boot -Setup1Results $s1 -Setup2Results $s2 -BootElev 2 -Setup1Elev 1 -Setup2Elev 0
        $j = Test-SandboxRun -Run $run -Expected @()
        $j.Passed | Should -BeFalse
        $j.Failures.Count | Should -Be 6
        $j.Failures | Should -Contain 'Sandbox 안 스크립트 오류: 스크립트 중단'
        $j.Failures | Should -Contain '[bootstrap] clone: 실패: clone 오류'
        $j.Failures | Should -Contain '[setup-1] [Windows 설정] LongPaths: 실패: 거부'
        $j.Failures | Should -Contain '[setup-2] [Windows 설정] LongPaths: 바꿈'
        $j.Failures | Should -Contain '승격 요청 횟수: 첫 실행 3회 (기준 2회)'
        $j.Failures | Should -Contain '승격 요청 횟수: 재실행 0회 (기준 1회)'
    }

    It '속성이 빠진 입력에서도 예외 없이 불합격 이유로 바꾼다' {
        $malformed = [pscustomobject]@{}
        $j = Test-SandboxRun -Run $malformed -Expected @()
        $j.Passed | Should -BeFalse
        $j.Failures | Should -Contain 'bootstrap 결과 없음 (실행 안 됨)'
        $j.Failures | Should -Contain 'setup-1 결과 없음 (실행 안 됨)'
        $j.Failures | Should -Contain 'setup-2 결과 없음 (실행 안 됨)'
    }
}

Describe 'Read-SandboxExpected' {
    It '저장소의 sandbox-expected.psd1 이 검사를 통과한다' {
        $path = Join-Path $PSScriptRoot '..' 'test' 'sandbox-expected.psd1'
        $items = Read-SandboxExpected -Path $path
        $null -ne $items | Should -BeTrue
        $items.Count | Should -Be 0
    }

    It 'TestDrive 파일로 Result = 그대로(허용 값 밖) 와 Reason 빠짐이 문제가 된다' {
        $content = @"
@{
    Items = @(
        @{
            Id     = 'ItemA'
            Result = '그대로'
            Reason = '이유'
        }
        @{
            Id     = 'ItemB'
            Result = '실패'
        }
    )
}
"@
        Set-Content -Path 'TestDrive:/bad-expected.psd1' -Value $content -Encoding UTF8
        try {
            Read-SandboxExpected -Path 'TestDrive:/bad-expected.psd1'
            throw '예외가 발생해야 합니다'
        } catch [DeclarationException] {
            $_.Exception.Problems.Count | Should -Be 2
            $_.Exception.Problems[0] | Should -Match "bad-expected\.psd1:3: 'Result' 값 '그대로' 은 허용되지 않는다"
            $_.Exception.Problems[1] | Should -Match "bad-expected\.psd1:8: 필수 키 'Reason' 가 없다"
        }
    }
}

Describe 'Test-SandboxExpectedIds' {
    It '모두 있음 -> 빈 배열' {
        $expected = @(
            [pscustomobject]@{ Id = 'LongPaths'; Result = '실패'; Reason = '이유'; Line = 3 }
            [pscustomobject]@{ Id = 'Power'; Result = '할 일'; Reason = '이유'; Line = 8 }
        )
        $problems = Test-SandboxExpectedIds -Expected $expected -DeclaredIds @('LongPaths', 'Power', 'DarkModeApps')
        $problems.Count | Should -Be 0
    }

    It '하나 없음 -> 문제 하나(줄 번호 포함)' {
        $expected = @(
            [pscustomobject]@{ Id = 'LongPaths'; Result = '실패'; Reason = '이유'; Line = 3 }
            [pscustomobject]@{ Id = 'RemovedItem'; Result = '실패'; Reason = '이유'; Line = 8 }
        )
        $problems = Test-SandboxExpectedIds -Expected $expected -DeclaredIds @('LongPaths', 'Power')
        $problems.Count | Should -Be 1
        $problems[0] | Should -Be "sandbox-expected.psd1:8: 선언에 없는 Id 'RemovedItem'"
    }
}

Describe 'Get-SandboxSkipIds' {
    It '건너뜀 둘·실패 하나 -> 두 Id' {
        $expected = @(
            [pscustomobject]@{ Id = 'wsl'; Result = '건너뜀'; Reason = '이유'; Line = 3 }
            [pscustomobject]@{ Id = 'iCloud'; Result = '실패'; Reason = '이유'; Line = 4 }
            [pscustomobject]@{ Id = 'hyper-v'; Result = '건너뜀'; Reason = '이유'; Line = 5 }
        )
        $ids = Get-SandboxSkipIds -Expected $expected
        $ids.Count | Should -Be 2
        $ids[0] | Should -Be 'wsl'
        $ids[1] | Should -Be 'hyper-v'
    }
}

Describe 'Format-SandboxReport' {
    It '합격·경고 없음 -> Sandbox 판정: 합격, 경고: 없음, 불합격 이유: 없음' {
        $run = New-DefaultRun
        $j = Test-SandboxRun -Run $run -Expected @()
        $lines = Format-SandboxReport -Judgment $j
        $lines[0] | Should -Be 'Sandbox 판정: 합격'
        ($lines -match '^실행\s+종료').Count | Should -Be 1
        ($lines -match '^bootstrap\s+').Count | Should -Be 1
        ($lines -match '^setup-1\s+').Count | Should -Be 1
        ($lines -match '^setup-2\s+').Count | Should -Be 1
        $lines | Should -Contain '예상 결과로 뺀 결과: 0개'
        ($lines -eq '경고:').Count | Should -Be 0
        ($lines -eq '불합격 이유:').Count | Should -Be 0
    }

    It '불합격·경고 있음 -> Sandbox 판정: 불합격, 경고: 있음, 불합격 이유: 있음' {
        $expected = @(
            [pscustomobject]@{ Id = 'MissingId'; Result = '실패'; Reason = '없음'; Line = 3 }
        )
        $run = New-DefaultRun -BootElev 2 -Setup1Elev 1
        $j = Test-SandboxRun -Run $run -Expected $expected
        $lines = Format-SandboxReport -Judgment $j
        $lines[0] | Should -Be 'Sandbox 판정: 불합격'
        $lines | Should -Contain '경고:'
        $lines | Should -Contain "  - 예상 결과 'MissingId' 가 셋업 결과에 없다"
        $lines | Should -Contain '불합격 이유:'
        $lines | Should -Contain '  - 승격 요청 횟수: 첫 실행 3회 (기준 2회)'
    }
}
