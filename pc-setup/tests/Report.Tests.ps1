using module ../lib/Report.psm1

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'lib' 'Report.psm1'
    Import-Module $modulePath -Force
}

Describe 'New-SetupResult' {
    It '기본 속성(Stage, Id, Status, Detail)을 갖는 객체를 만든다' {
        $res = New-SetupResult -Stage 'Windows 설정' -Id 'LongPaths' -Status '그대로'
        $res.Stage | Should -Be 'Windows 설정'
        $res.Id | Should -Be 'LongPaths'
        $res.Status | Should -Be '그대로'
        $res.Detail | Should -Be ''
    }

    It 'Detail 지정 시 해당 값이 설정된다' {
        $res = New-SetupResult -Stage '앱' -Id 'wsl' -Status '할 일' -Detail '재부팅 필요'
        $res.Detail | Should -Be '재부팅 필요'
    }

    It '허용되지 않은 Status 는 오류를 발생시킨다' {
        { New-SetupResult -Stage '앱' -Id 'x' -Status '알수없음' } | Should -Throw
    }
}

Describe 'ConvertFrom-ResultText 표 1~12' {
    It '1: 그대로 (Check 미지정) -> 그대로' {
        $res = ConvertFrom-ResultText -Text '그대로'
        $res.Status | Should -Be '그대로'
        $res.Detail | Should -Be ''
    }

    It '1: 그대로 (-Check) -> 그대로' {
        $res = ConvertFrom-ResultText -Text '그대로' -Check
        $res.Status | Should -Be '그대로'
        $res.Detail | Should -Be ''
    }

    It '2: 바꿈 (Check 미지정) -> 바꿈, Detail 빈 값' {
        $res = ConvertFrom-ResultText -Text '바꿈'
        $res.Status | Should -Be '바꿈'
        $res.Detail | Should -Be ''
    }

    It '2: 바꿈 (백업: C:\a.bak) (Check 미지정) -> 바꿈, Detail 백업: C:\a.bak' {
        $res = ConvertFrom-ResultText -Text '바꿈 (백업: C:\a.bak)'
        $res.Status | Should -Be '바꿈'
        $res.Detail | Should -Be '백업: C:\a.bak'
    }

    It '3: 바꿈 (-Check) -> $null' {
        $res = ConvertFrom-ResultText -Text '바꿈' -Check
        $null -eq $res | Should -BeTrue

        $resWithDetail = ConvertFrom-ResultText -Text '바꿈 (x)' -Check
        $null -eq $resWithDetail | Should -BeTrue
    }

    It '4: 다름 (값 0, 선언 1) (-Check) -> 다름, Detail 값 0, 선언 1' {
        $res = ConvertFrom-ResultText -Text '다름 (값 0, 선언 1)' -Check
        $res.Status | Should -Be '다름'
        $res.Detail | Should -Be '값 0, 선언 1'
    }

    It '4: 다름 (-Check) -> 다름, Detail 빈 값' {
        $res = ConvertFrom-ResultText -Text '다름' -Check
        $res.Status | Should -Be '다름'
        $res.Detail | Should -Be ''
    }

    It '5: 다름 (Check 미지정) -> $null' {
        $res = ConvertFrom-ResultText -Text '다름'
        $null -eq $res | Should -BeTrue

        $resWithDetail = ConvertFrom-ResultText -Text '다름 (x)'
        $null -eq $resWithDetail | Should -BeTrue
    }

    It '6: 할 일: 재부팅 후 셋업 다시 실행 (Check 미지정) -> 할 일' {
        $res = ConvertFrom-ResultText -Text '할 일: 재부팅 후 셋업 다시 실행'
        $res.Status | Should -Be '할 일'
        $res.Detail | Should -Be '재부팅 후 셋업 다시 실행'
    }

    It '6: 할 일: 재부팅 후 셋업 다시 실행 (-Check) -> 할 일' {
        $res = ConvertFrom-ResultText -Text '할 일: 재부팅 후 셋업 다시 실행' -Check
        $res.Status | Should -Be '할 일'
        $res.Detail | Should -Be '재부팅 후 셋업 다시 실행'
    }

    It '7: 실패: 접근 거부 (Check 미지정) -> 실패' {
        $res = ConvertFrom-ResultText -Text '실패: 접근 거부'
        $res.Status | Should -Be '실패'
        $res.Detail | Should -Be '접근 거부'
    }

    It '7: 실패: 접근 거부 (-Check) -> 실패' {
        $res = ConvertFrom-ResultText -Text '실패: 접근 거부' -Check
        $res.Status | Should -Be '실패'
        $res.Detail | Should -Be '접근 거부'
    }

    It '8: 확인 못 함: 관리자 필요 (-Check) -> 확인 못 함' {
        $res = ConvertFrom-ResultText -Text '확인 못 함: 관리자 필요' -Check
        $res.Status | Should -Be '확인 못 함'
        $res.Detail | Should -Be '관리자 필요'
    }

    It '8: 확인 못 함: 관리자 필요 (Check 미지정) -> $null' {
        $res = ConvertFrom-ResultText -Text '확인 못 함: 관리자 필요'
        $null -eq $res | Should -BeTrue
    }

    It '9: 할 일: (뒤가 빔) -> $null' {
        $res1 = ConvertFrom-ResultText -Text '할 일:'
        $null -eq $res1 | Should -BeTrue

        $res2 = ConvertFrom-ResultText -Text '할 일:' -Check
        $null -eq $res2 | Should -BeTrue

        $res3 = ConvertFrom-ResultText -Text '실패:'
        $null -eq $res3 | Should -BeTrue

        $res4 = ConvertFrom-ResultText -Text '확인 못 함:' -Check
        $null -eq $res4 | Should -BeTrue
    }

    It '10:   그대로   (앞뒤 공백) -> 그대로' {
        $res1 = ConvertFrom-ResultText -Text '  그대로  '
        $res1.Status | Should -Be '그대로'
        $res1.Detail | Should -Be ''

        $res2 = ConvertFrom-ResultText -Text '  그대로  ' -Check
        $res2.Status | Should -Be '그대로'
        $res2.Detail | Should -Be ''
    }

    It '11: OK, 빈 문자열 -> $null' {
        $res1 = ConvertFrom-ResultText -Text 'OK'
        $null -eq $res1 | Should -BeTrue

        $res2 = ConvertFrom-ResultText -Text ''
        $null -eq $res2 | Should -BeTrue
    }

    It '12: 건너뜀 -> 둘 다 $null' {
        $res1 = ConvertFrom-ResultText -Text '건너뜀'
        $null -eq $res1 | Should -BeTrue

        $res2 = ConvertFrom-ResultText -Text '건너뜀' -Check
        $null -eq $res2 | Should -BeTrue
    }
}

Describe 'Format-ResultLine' {
    It 'ConvertFrom-ResultText 로 만든 결과가 원래 글로 돌아온다 (그대로·바꿈 (x)·할 일: x·실패: x·다름 (x))' {
        Format-ResultLine (ConvertFrom-ResultText '그대로') | Should -Be '그대로'
        Format-ResultLine (ConvertFrom-ResultText '바꿈 (x)') | Should -Be '바꿈 (x)'
        Format-ResultLine (ConvertFrom-ResultText '할 일: x') | Should -Be '할 일: x'
        Format-ResultLine (ConvertFrom-ResultText '실패: x') | Should -Be '실패: x'
        Format-ResultLine (ConvertFrom-ResultText '다름 (x)' -Check) | Should -Be '다름 (x)'
    }

    It 'Stage 와 Id 가 있는 결과는 [<Stage>] <Id>: <글> 모양으로 바뀐다' {
        $r1 = New-SetupResult -Stage 'Windows 설정' -Id 'LongPaths' -Status '그대로'
        Format-ResultLine $r1 | Should -Be '[Windows 설정] LongPaths: 그대로'

        $r2 = New-SetupResult -Stage '앱' -Id 'wsl' -Status '할 일' -Detail '재부팅 후 셋업 다시 실행'
        Format-ResultLine $r2 | Should -Be '[앱] wsl: 할 일: 재부팅 후 셋업 다시 실행'

        $r3 = New-SetupResult -Stage '앱' -Id 'git' -Status '바꿈' -Detail '2.40 설치'
        Format-ResultLine $r3 | Should -Be '[앱] git: 바꿈 (2.40 설치)'

        $r4 = New-SetupResult -Stage '앱' -Id 'git' -Status '바꿈'
        Format-ResultLine $r4 | Should -Be '[앱] git: 바꿈'

        $r5 = New-SetupResult -Stage 'Windows 설정' -Id 'DevMode' -Status '건너뜀'
        Format-ResultLine $r5 | Should -Be '[Windows 설정] DevMode: 건너뜀'
    }
}

Describe 'Format-SetupSummary' {
    It '고치는 실행 요약 순서와 내용' {
        $results = @(
            (New-SetupResult -Stage 'Windows 설정' -Id 'LongPaths' -Status '그대로')
            (New-SetupResult -Stage '앱' -Id 'git' -Status '바꿈' -Detail '설치')
            (New-SetupResult -Stage '앱' -Id 'wsl' -Status '할 일' -Detail '재부팅 후 셋업 다시 실행')
        )
        $lines = Format-SetupSummary -Results $results -ElevationRequests 1 -Duration (New-TimeSpan -Minutes 4 -Seconds 12)
        $lines[0] | Should -Be '요약: 그대로 1 · 바꿈 1 · 할 일 1 · 실패 0 · 건너뜀 0'
        $lines[1] | Should -Be '승격 요청: 1회'
        $lines[2] | Should -Be '걸린 시간: 04:12'
        $lines[3] | Should -Be '할 일:'
        $lines[4] | Should -Be '  - 재부팅 후 셋업 다시 실행 (wsl)'
        $lines.Length | Should -Be 5
    }

    It '-Check 요약 순서와 내용' {
        $results = @(
            (New-SetupResult -Stage 'Windows 설정' -Id 'LongPaths' -Status '그대로')
            (New-SetupResult -Stage 'Windows 설정' -Id 'Hibernate' -Status '다름' -Detail '값 0')
            (New-SetupResult -Stage '앱' -Id 'ssh' -Status '확인 못 함' -Detail '권한 필요')
        )
        $lines = Format-SetupSummary -Results $results -ElevationRequests 0 -Duration (New-TimeSpan -Minutes 1 -Seconds 5) -Check
        $lines[0] | Should -Be '요약: 그대로 1 · 다름 1 · 할 일 0 · 확인 못 함 1 · 실패 0 · 건너뜀 0'
        $lines[1] | Should -Be '승격 요청: 0회'
        $lines[2] | Should -Be '걸린 시간: 01:05'
    }

    It '할 일 모음: 같은 Detail 은 한 줄로 모으고 Id 를 처음 나온 순서대로 쉼표로 잇는다' {
        $results = @(
            (New-SetupResult -Stage '앱' -Id 'wsl' -Status '할 일' -Detail '재부팅 후 셋업 다시 실행')
            (New-SetupResult -Stage 'Windows 설정' -Id 'Hibernate' -Status '할 일' -Detail '재부팅 후 셋업 다시 실행')
            (New-SetupResult -Stage '앱' -Id 'docker' -Status '할 일' -Detail '로그아웃 후 다시 로그인')
        )
        $lines = Format-SetupSummary -Results $results
        $lines[3] | Should -Be '할 일:'
        $lines[4] | Should -Be '  - 재부팅 후 셋업 다시 실행 (wsl, Hibernate)'
        $lines[5] | Should -Be '  - 로그아웃 후 다시 로그인 (docker)'
    }

    It '실패 블록: 결과마다 한 줄 [Stage] Id: Detail' {
        $results = @(
            (New-SetupResult -Stage '앱' -Id 'Foo' -Status '실패' -Detail '다운로드 실패')
            (New-SetupResult -Stage 'Windows 설정' -Id 'Bar' -Status '실패' -Detail '접근 거부')
        )
        $lines = Format-SetupSummary -Results $results
        $lines[3] | Should -Be '실패:'
        $lines[4] | Should -Be '  - [앱] Foo: 다운로드 실패'
        $lines[5] | Should -Be '  - [Windows 설정] Bar: 접근 거부'
    }

    It '1시간 넘는 시간은 h:mm:ss 로 포맷된다' {
        $duration = New-TimeSpan -Hours 1 -Minutes 2 -Seconds 3
        $lines = Format-SetupSummary -Results @() -Duration $duration
        $lines[2] | Should -Be '걸린 시간: 1:02:03'
    }
}

Describe 'Get-SetupExitCode' {
    It '빈 목록 -> 0' {
        Get-SetupExitCode -Results @() | Should -Be 0
    }

    It '실패 0개 (그대로·다름·할 일·확인 못 함만 있음) -> 0' {
        $results = @(
            (New-SetupResult -Stage 'a' -Id '1' -Status '그대로')
            (New-SetupResult -Stage 'a' -Id '2' -Status '다름')
            (New-SetupResult -Stage 'a' -Id '3' -Status '할 일' -Detail 'x')
            (New-SetupResult -Stage 'a' -Id '4' -Status '확인 못 함' -Detail 'y')
            (New-SetupResult -Stage 'a' -Id '5' -Status '건너뜀')
        )
        Get-SetupExitCode -Results $results | Should -Be 0
    }

    It '실패 1개 이상 -> 1' {
        $results = @(
            (New-SetupResult -Stage 'a' -Id '1' -Status '그대로')
            (New-SetupResult -Stage 'a' -Id '2' -Status '실패' -Detail '오류')
        )
        Get-SetupExitCode -Results $results | Should -Be 1
    }
}
