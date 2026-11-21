BeforeAll {
    $script:toolPath = Join-Path $PSScriptRoot '..' 'tools' 'add-user-path.ps1'
    . $script:toolPath
}

Describe 'add-user-path.ps1 (dot-source, 레지스트리 Mock)' {
    BeforeEach {
        $script:writtenEntries = $null
        $script:setCalls = 0
        $script:updateCalls = 0
        Mock Set-UserPathEntries { $script:setCalls++; $script:writtenEntries = $Entries }
        Mock Update-SessionPath { $script:updateCalls++ }
    }

    It '없음, 뒤에 넣기 -> -Check 다름(아무것도 안 바꿈), 실행 바꿈(맨 뒤), 두 번째 그대로' {
        Mock Get-UserPathEntries { @('C:\existing1', 'C:\existing2') }

        $rCheck = Invoke-Main -Entry 'C:\new\bin' -Check
        $rCheck.Line | Should -Be '다름: 사용자 PATH 에 C:\new\bin 없음'
        $rCheck.ExitCode | Should -Be 0
        $script:setCalls | Should -Be 0
        $script:updateCalls | Should -Be 0

        $rFix = Invoke-Main -Entry 'C:\new\bin'
        $rFix.Line | Should -Be '바꿈: 사용자 PATH 끝에 C:\new\bin 추가'
        $rFix.ExitCode | Should -Be 0
        $script:writtenEntries | Should -Be @('C:\existing1', 'C:\existing2', 'C:\new\bin')
        $script:setCalls | Should -Be 1
        $script:updateCalls | Should -Be 1

        $after = $script:writtenEntries
        Mock Get-UserPathEntries { $after }.GetNewClosure()
        (Invoke-Main -Entry 'C:\new\bin').Line | Should -Be '그대로'
        $script:setCalls | Should -Be 1
    }

    It '없음, 앞에 넣기 -> -Check 다름(아무것도 안 바꿈), 실행 바꿈(맨 앞), 두 번째 그대로' {
        Mock Get-UserPathEntries { @('C:\existing1', 'C:\existing2') }

        $rCheck = Invoke-Main -Entry 'C:\first\bin' -Prepend -Check
        $rCheck.Line | Should -Be '다름: C:\first\bin 가 맨 앞이 아님'
        $rCheck.ExitCode | Should -Be 0
        $script:setCalls | Should -Be 0
        $script:updateCalls | Should -Be 0

        $rFix = Invoke-Main -Entry 'C:\first\bin' -Prepend
        $rFix.Line | Should -Be '바꿈: 사용자 PATH 맨 앞에 C:\first\bin'
        $script:writtenEntries | Should -Be @('C:\first\bin', 'C:\existing1', 'C:\existing2')
        $script:updateCalls | Should -Be 1

        $after = $script:writtenEntries
        Mock Get-UserPathEntries { $after }.GetNewClosure()
        (Invoke-Main -Entry 'C:\first\bin' -Prepend).Line | Should -Be '그대로'
        $script:setCalls | Should -Be 1
    }

    It '이미 있음(대소문자·끝 \ 다름) -> -Check·실행 모두 그대로, 쓰기 없음' {
        Mock Get-UserPathEntries { @('C:\Existing\Bin\') }

        (Invoke-Main -Entry 'c:\existing\bin' -Check).Line | Should -Be '그대로'
        (Invoke-Main -Entry 'c:\existing\bin').Line | Should -Be '그대로'
        $script:setCalls | Should -Be 0
        $script:updateCalls | Should -Be 0
    }

    It '앞에 넣기인데 이미 맨 앞(대소문자·끝 \ 다름) -> -Check·실행 모두 그대로, 쓰기 없음' {
        Mock Get-UserPathEntries { @('C:\First\Bin\', 'C:\second') }

        (Invoke-Main -Entry 'c:\first\bin' -Prepend -Check).Line | Should -Be '그대로'
        (Invoke-Main -Entry 'c:\first\bin' -Prepend).Line | Should -Be '그대로'
        $script:setCalls | Should -Be 0
        $script:updateCalls | Should -Be 0
    }

    It '앞에 넣기인데 셋째에 있음 -> -Check 다름(쓰기 없음), 실행 맨 앞으로 옮김(나머지 순서 그대로)' {
        Mock Get-UserPathEntries { @('C:\first', 'C:\second', 'C:\target\bin') }

        (Invoke-Main -Entry 'C:\target\bin' -Prepend -Check).Line | Should -Be '다름: C:\target\bin 가 맨 앞이 아님'
        $script:setCalls | Should -Be 0

        (Invoke-Main -Entry 'C:\target\bin' -Prepend).Line | Should -Be '바꿈: 사용자 PATH 맨 앞에 C:\target\bin'
        $script:writtenEntries | Should -Be @('C:\target\bin', 'C:\first', 'C:\second')
        $script:updateCalls | Should -Be 1
    }

    It '앞에 넣기인데 둘째·넷째에 두 번 -> 둘 다 빠지고 첫 표기 하나만 맨 앞' {
        Mock Get-UserPathEntries { @('C:\first', 'C:\dup\bin', 'C:\middle', 'C:\DUP\BIN\') }

        (Invoke-Main -Entry 'C:\dup\bin' -Prepend).Line | Should -Be '바꿈: 사용자 PATH 맨 앞에 C:\dup\bin'
        $script:writtenEntries | Should -Be @('C:\dup\bin', 'C:\first', 'C:\middle')
    }

    It '앞에 넣기, 둘째가 %USERPROFILE%\.local\bin 이고 Entry 는 펼친 값 -> 원래 %VAR% 표기 그대로 맨 앞' {
        Mock Get-UserPathEntries { @('C:\other', '%USERPROFILE%\.local\bin', 'C:\third') }
        $expanded = [System.Environment]::ExpandEnvironmentVariables('%USERPROFILE%\.local\bin')

        (Invoke-Main -Entry $expanded -Prepend -Check).Line | Should -Be "다름: $expanded 가 맨 앞이 아님"
        $script:setCalls | Should -Be 0

        (Invoke-Main -Entry $expanded -Prepend).Line | Should -Be "바꿈: 사용자 PATH 맨 앞에 $expanded"
        $script:writtenEntries | Should -Be @('%USERPROFILE%\.local\bin', 'C:\other', 'C:\third')
    }

    It '뒤에 넣기, %LOCALAPPDATA%\pnpm 꼴로 이미 있고 Entry 는 펼친 값 -> 그대로, 쓰기 없음' {
        Mock Get-UserPathEntries { @('C:\first', '%LOCALAPPDATA%\pnpm') }
        $expanded = [System.Environment]::ExpandEnvironmentVariables('%LOCALAPPDATA%\pnpm')

        (Invoke-Main -Entry $expanded -Check).Line | Should -Be '그대로'
        (Invoke-Main -Entry $expanded).Line | Should -Be '그대로'
        $script:setCalls | Should -Be 0
    }

    It '사용자 PATH 가 비어 있음 -> 뒤에 넣기·앞에 넣기 모두 Entry 하나만 쓴다, -Check 는 쓰기 없음' {
        Mock Get-UserPathEntries { [string[]]@() }

        (Invoke-Main -Entry 'C:\only' -Check).Line | Should -Be '다름: 사용자 PATH 에 C:\only 없음'
        (Invoke-Main -Entry 'C:\only' -Prepend -Check).Line | Should -Be '다름: C:\only 가 맨 앞이 아님'
        $script:setCalls | Should -Be 0

        (Invoke-Main -Entry 'C:\only').Line | Should -Be '바꿈: 사용자 PATH 끝에 C:\only 추가'
        $script:writtenEntries | Should -Be @('C:\only')

        (Invoke-Main -Entry 'C:\only' -Prepend).Line | Should -Be '바꿈: 사용자 PATH 맨 앞에 C:\only'
        $script:writtenEntries | Should -Be @('C:\only')
    }

    It '-Entry 가 빠짐 -> 실패: Entry 가 없다, 종료 코드 1' {
        Mock Get-UserPathEntries { @() }
        $r = Invoke-Main
        $r.Line | Should -Be '실패: Entry 가 없다'
        $r.ExitCode | Should -Be 1
    }

    It '레지스트리 읽기 예외 -> 실패: 예외 메시지, 종료 코드 1' {
        Mock Get-UserPathEntries { throw 'reg boom' }
        $r = Invoke-Main -Entry 'C:\x'
        $r.Line | Should -Be '실패: reg boom'
        $r.ExitCode | Should -Be 1
    }
}

Describe 'Update-SessionPath (add-user-path.ps1)' {
    It '시스템(HKLM) 다음에 사용자(HKCU) 조각을 순서대로 잇고 빈 조각은 빼며 환경 변수를 펼친다' {
        $savedPath = $env:Path
        try {
            $env:Path = 'C:\before'
            Mock Get-EnvironmentPath {
                param($Target)
                if ($Target -eq [System.EnvironmentVariableTarget]::Machine) {
                    return 'C:\Windows\System32;;%SystemRoot%\System32\Wbem;'
                }
                return ';%USERPROFILE%\.local\bin;C:\UserTools;'
            }

            Update-SessionPath

            $expectedSysRoot = [System.Environment]::ExpandEnvironmentVariables('%SystemRoot%\System32\Wbem')
            $expectedUserBin = [System.Environment]::ExpandEnvironmentVariables('%USERPROFILE%\.local\bin')
            $env:Path | Should -Be "C:\Windows\System32;$expectedSysRoot;$expectedUserBin;C:\UserTools"
        } finally {
            $env:Path = $savedPath
        }
    }
}

Describe 'add-user-path.ps1 (자식 pwsh -File)' {
    It '-Entry 없이 실행 -> 한 줄 실패: Entry 가 없다, 종료 코드 1' {
        $out = @(& pwsh -NoProfile -File $script:toolPath)
        $LASTEXITCODE | Should -Be 1
        $out.Count | Should -Be 1
        $out[0] | Should -Be '실패: Entry 가 없다'
    }

    It '-Check 로 실행(읽기만 함) -> 한 줄 그대로 또는 다름, 종료 코드 0' {
        $entry = Join-Path ([System.IO.Path]::GetTempPath()) ('pc-setup-no-such-' + [guid]::NewGuid().ToString('N'))
        $out = @(& pwsh -NoProfile -File $script:toolPath -Entry $entry -Check)
        $LASTEXITCODE | Should -Be 0
        $out.Count | Should -Be 1
        $out[0] | Should -Be "다름: 사용자 PATH 에 $entry 없음"
    }
}

Describe 'add-user-path.ps1 의존성' {
    It '옛 모듈 폴더(lib)를 import 하거나 dot-source 하지 않는다' {
        $text = Get-Content -LiteralPath $script:toolPath -Raw
        $text | Should -Not -Match '(?im)^\s*(Import-Module|using\s+module|\.\s+\S)'
        $text | Should -Not -Match '(?i)[\\/]lib[\\/]|''lib'''
    }
}
