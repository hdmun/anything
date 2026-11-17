BeforeAll {
    $envPathModule = Join-Path $PSScriptRoot '..' 'lib' 'EnvPath.psm1'
    Import-Module $envPathModule -Force
    $appWingetModule = Join-Path $PSScriptRoot '..' 'lib' 'AppWinget.psm1'
    Import-Module $appWingetModule -Force
}

Describe 'Invoke-WingetApp' {
    It '1: list 0 -> 그대로, install 안 불림 (-Check <Check>)' -ForEach @(
        @{ Check = $false }
        @{ Check = $true }
    ) {
        $script:calls = [System.Collections.Generic.List[object]]::new()
        Mock -ModuleName AppWinget Invoke-Winget {
            $script:calls.Add($Arguments)
            return @{ ExitCode = 0; Output = @() }
        }
        Mock -ModuleName AppWinget Update-SessionPath {}

        $entry = [pscustomobject]@{ Id = 'Git.Git'; Scope = 'machine' }
        $res = Invoke-WingetApp -Entry $entry -Check $Check

        $res.Status | Should -Be '그대로'
        $res.Detail | Should -Be ''
        $script:calls.Count | Should -Be 1
        $script:calls[0][0] | Should -Be 'list'
    }

    It '2: list 0x8A150014, -Check $true -> 다름 (설치 안 됨), install 안 불림' {
        $script:calls = [System.Collections.Generic.List[object]]::new()
        Mock -ModuleName AppWinget Invoke-Winget {
            $script:calls.Add($Arguments)
            return @{ ExitCode = -1978335212; Output = @() }
        }
        Mock -ModuleName AppWinget Update-SessionPath {}

        $entry = [pscustomobject]@{ Id = 'Git.Git'; Scope = 'machine' }
        $res = Invoke-WingetApp -Entry $entry -Check $true

        $res.Status | Should -Be '다름'
        $res.Detail | Should -Be '설치 안 됨'
        $script:calls.Count | Should -Be 1
        $script:calls[0][0] | Should -Be 'list'
    }

    It '3: list 0x8A150014, install 0 -> 바꿈, Update-SessionPath 1번' {
        $script:pathCalls = 0
        Mock -ModuleName AppWinget Invoke-Winget {
            if ($Arguments[0] -eq 'list') {
                return @{ ExitCode = -1978335212; Output = @() }
            }
            return @{ ExitCode = 0; Output = @() }
        }
        Mock -ModuleName AppWinget Update-SessionPath { $script:pathCalls++ }

        $entry = [pscustomobject]@{ Id = 'Git.Git'; Scope = 'user' }
        $res = Invoke-WingetApp -Entry $entry -Check $false

        $res.Status | Should -Be '바꿈'
        $res.Detail | Should -Be ''
        $script:pathCalls | Should -Be 1
    }

    It '4: install 0x8A150109 -> Update-SessionPath 부르고 할 일: 재부팅 후 셋업 다시 실행' {
        $script:pathCalls = 0
        Mock -ModuleName AppWinget Invoke-Winget {
            if ($Arguments[0] -eq 'list') {
                return @{ ExitCode = -1978335212; Output = @() }
            }
            return @{ ExitCode = -1978334967; Output = @() }
        }
        Mock -ModuleName AppWinget Update-SessionPath { $script:pathCalls++ }

        $entry = [pscustomobject]@{ Id = 'Docker.DockerDesktop'; Scope = 'machine' }
        $res = Invoke-WingetApp -Entry $entry -Check $false

        $res.Status | Should -Be '할 일'
        $res.Detail | Should -Be '재부팅 후 셋업 다시 실행'
        $script:pathCalls | Should -Be 1
    }

    It '5: install 0x8A150056 (ElevationProhibited) -> 실패: winget install 종료 코드 0x8A150056' {
        Mock -ModuleName AppWinget Invoke-Winget {
            if ($Arguments[0] -eq 'list') {
                return @{ ExitCode = -1978335212; Output = @() }
            }
            return @{ ExitCode = -1978335146; Output = @() }
        }
        Mock -ModuleName AppWinget Update-SessionPath {}

        $entry = [pscustomobject]@{ Id = 'Git.Git'; Scope = 'machine' }
        $res = Invoke-WingetApp -Entry $entry -Check $false

        $res.Status | Should -Be '실패'
        $res.Detail | Should -Be 'winget install 종료 코드 0x8A150056'
    }

    It '5b: install 실패 시 출력에 오류 설명 줄이 있으면 마지막 비어 있지 않은 줄을 붙인다' {
        Mock -ModuleName AppWinget Invoke-Winget {
            if ($Arguments[0] -eq 'list') {
                return @{ ExitCode = -1978335212; Output = @() }
            }
            return @{ ExitCode = -1978335146; Output = @('진행 중...', '  관리자 권한이 필요합니다  ', '') }
        }
        Mock -ModuleName AppWinget Update-SessionPath {}

        $entry = [pscustomobject]@{ Id = 'Git.Git'; Scope = 'machine' }
        $res = Invoke-WingetApp -Entry $entry -Check $false

        $res.Status | Should -Be '실패'
        $res.Detail | Should -Be 'winget install 종료 코드 0x8A150056 (관리자 권한이 필요합니다)'
    }

    It '6: list 0x8A15000F -> 실패: winget list 종료 코드 0x8A15000F (-Check <Check>)' -ForEach @(
        @{ Check = $false }
        @{ Check = $true }
    ) {
        Mock -ModuleName AppWinget Invoke-Winget {
            return @{ ExitCode = -1978335217; Output = @() }
        }
        Mock -ModuleName AppWinget Update-SessionPath {}

        $entry = [pscustomobject]@{ Id = 'Git.Git'; Scope = 'machine' }
        $res = Invoke-WingetApp -Entry $entry -Check $Check

        $res.Status | Should -Be '실패'
        $res.Detail | Should -Be 'winget list 종료 코드 0x8A15000F'
    }

    It '7: winget 없음 (ExitCode $null) -> 실패: winget 이 없다 (-Check <Check>)' -ForEach @(
        @{ Check = $false }
        @{ Check = $true }
    ) {
        Mock -ModuleName AppWinget Invoke-Winget {
            return @{ ExitCode = $null; Output = @() }
        }
        Mock -ModuleName AppWinget Update-SessionPath {}

        $entry = [pscustomobject]@{ Id = 'Git.Git'; Scope = 'user' }
        $res = Invoke-WingetApp -Entry $entry -Check $Check

        $res.Status | Should -Be '실패'
        $res.Detail | Should -Be 'winget 이 없다'
    }

    It '8: Scope=machine -> install 인자에 --scope machine, --source winget, --no-upgrade' {
        $script:installArgs = $null
        Mock -ModuleName AppWinget Invoke-Winget {
            if ($Arguments[0] -eq 'list') {
                return @{ ExitCode = -1978335212; Output = @() }
            }
            $script:installArgs = $Arguments
            return @{ ExitCode = 0; Output = @() }
        }
        Mock -ModuleName AppWinget Update-SessionPath {}

        $entry = [pscustomobject]@{ Id = 'Git.Git'; Scope = 'machine' }
        $null = Invoke-WingetApp -Entry $entry -Check $false

        $joined = $script:installArgs -join ' '
        $joined | Should -Match '--scope machine'
        $joined | Should -Match '--source winget'
        $script:installArgs | Should -Contain '--no-upgrade'
    }

    It '9: msstore -> list 와 install 인자에 --source msstore, --scope 없음' {
        $script:calls = [System.Collections.Generic.List[object]]::new()
        Mock -ModuleName AppWinget Invoke-Winget {
            $script:calls.Add($Arguments)
            if ($Arguments[0] -eq 'list') {
                return @{ ExitCode = -1978335212; Output = @() }
            }
            return @{ ExitCode = 0; Output = @() }
        }
        Mock -ModuleName AppWinget Update-SessionPath {}

        $entry = [pscustomobject]@{ Id = '9PKTQ5699M62'; WingetSource = 'msstore' }
        $res = Invoke-WingetApp -Entry $entry -Check $false

        $res.Status | Should -Be '바꿈'
        $script:calls.Count | Should -Be 2
        foreach ($argsForCall in $script:calls) {
            ($argsForCall -join ' ') | Should -Match '--source msstore'
            $argsForCall | Should -Not -Contain '--scope'
        }
    }

    It '10: 모든 호출에 --accept-source-agreements·--disable-interactivity, install 에는 --accept-package-agreements 도 포함' {
        $script:calls = [System.Collections.Generic.List[object]]::new()
        Mock -ModuleName AppWinget Invoke-Winget {
            $script:calls.Add($Arguments)
            if ($Arguments[0] -eq 'list') {
                return @{ ExitCode = -1978335212; Output = @() }
            }
            return @{ ExitCode = 0; Output = @() }
        }
        Mock -ModuleName AppWinget Update-SessionPath {}

        $entry = [pscustomobject]@{ Id = 'Microsoft.VSCode'; Scope = 'user' }
        $null = Invoke-WingetApp -Entry $entry -Check $false

        $script:calls.Count | Should -Be 2
        foreach ($argsForCall in $script:calls) {
            $argsForCall | Should -Contain '--accept-source-agreements'
            $argsForCall | Should -Contain '--disable-interactivity'
        }
        $script:calls[1] | Should -Contain '--accept-package-agreements'
    }
}

Describe 'Invoke-Winget' {
    It 'Get-Command winget 이 없으면 ExitCode $null 을 돌려준다' {
        Mock -ModuleName AppWinget Get-Command { return $null }

        $res = Invoke-Winget -Arguments @('list', '--id', 'Git.Git', '-e')

        $res.ExitCode | Should -BeNullOrEmpty
        $null -eq $res.ExitCode | Should -BeTrue
    }
}
