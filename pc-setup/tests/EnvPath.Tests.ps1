BeforeAll {
    $envPathModule = Join-Path $PSScriptRoot '..' 'lib' 'EnvPath.psm1'
    Import-Module $envPathModule -Force
}

Describe 'Add-UserPath' {
    It '없는 경로 뒤에 넣기 (-Prepend 없음) -> 맨 뒤에 추가, $true, Update-SessionPath 불림' {
        $script:writtenEntries = $null
        $script:updateCalls = 0
        Mock -ModuleName EnvPath Get-UserPathEntries { return @('C:\existing1', 'C:\existing2') }
        Mock -ModuleName EnvPath Set-UserPathEntries { $script:writtenEntries = $Entries }
        Mock -ModuleName EnvPath Update-SessionPath { $script:updateCalls++ }

        $changed = Add-UserPath -Path 'C:\new\bin'

        $changed | Should -BeTrue
        $script:writtenEntries | Should -Be @('C:\existing1', 'C:\existing2', 'C:\new\bin')
        $script:updateCalls | Should -Be 1
    }

    It '-Prepend 로 맨 앞 -> 맨 앞에 추가, $true, Update-SessionPath 불림' {
        $script:writtenEntries = $null
        $script:updateCalls = 0
        Mock -ModuleName EnvPath Get-UserPathEntries { return @('C:\existing1', 'C:\existing2') }
        Mock -ModuleName EnvPath Set-UserPathEntries { $script:writtenEntries = $Entries }
        Mock -ModuleName EnvPath Update-SessionPath { $script:updateCalls++ }

        $changed = Add-UserPath -Path 'C:\first\bin' -Prepend

        $changed | Should -BeTrue
        $script:writtenEntries | Should -Be @('C:\first\bin', 'C:\existing1', 'C:\existing2')
        $script:updateCalls | Should -Be 1
    }

    It '이미 있음 (대소문자·끝 \ 다름) -> $false, Set-UserPathEntries 및 Update-SessionPath 안 불림' {
        $script:setCalls = 0
        $script:updateCalls = 0
        Mock -ModuleName EnvPath Get-UserPathEntries { return @('C:\Existing\Bin\') }
        Mock -ModuleName EnvPath Set-UserPathEntries { $script:setCalls++ }
        Mock -ModuleName EnvPath Update-SessionPath { $script:updateCalls++ }

        $changed = Add-UserPath -Path 'c:\existing\bin'

        $changed | Should -BeFalse
        $script:setCalls | Should -Be 0
        $script:updateCalls | Should -Be 0
    }

    It '-Prepend, 같은 경로가 셋째 항목 -> 맨 앞으로 옮겨지고 나머지 순서 그대로, 중복 없음, $true' {
        $script:writtenEntries = $null
        $script:updateCalls = 0
        Mock -ModuleName EnvPath Get-UserPathEntries { return @('C:\first', 'C:\second', 'C:\target\bin') }
        Mock -ModuleName EnvPath Set-UserPathEntries { $script:writtenEntries = $Entries }
        Mock -ModuleName EnvPath Update-SessionPath { $script:updateCalls++ }

        $changed = Add-UserPath -Path 'C:\target\bin' -Prepend

        $changed | Should -BeTrue
        $script:writtenEntries | Should -Be @('C:\target\bin', 'C:\first', 'C:\second')
        $script:updateCalls | Should -Be 1
    }

    It '-Prepend, 이미 첫 항목(대소문자·끝 \ 다름) -> $false, Set-UserPathEntries 및 Update-SessionPath 안 불림' {
        $script:setCalls = 0
        $script:updateCalls = 0
        Mock -ModuleName EnvPath Get-UserPathEntries { return @('C:\First\Bin\', 'C:\second') }
        Mock -ModuleName EnvPath Set-UserPathEntries { $script:setCalls++ }
        Mock -ModuleName EnvPath Update-SessionPath { $script:updateCalls++ }

        $changed = Add-UserPath -Path 'c:\first\bin' -Prepend

        $changed | Should -BeFalse
        $script:setCalls | Should -Be 0
        $script:updateCalls | Should -Be 0
    }

    It '-Prepend, 둘째 항목이 %USERPROFILE%\.local\bin 이고 $Path 는 펼친 값 -> 원래 꼴 그대로 맨 앞, $true' {
        $script:writtenEntries = $null
        $script:updateCalls = 0
        Mock -ModuleName EnvPath Get-UserPathEntries { return @('C:\other', '%USERPROFILE%\.local\bin', 'C:\third') }
        Mock -ModuleName EnvPath Set-UserPathEntries { $script:writtenEntries = $Entries }
        Mock -ModuleName EnvPath Update-SessionPath { $script:updateCalls++ }

        $expanded = [System.Environment]::ExpandEnvironmentVariables('%USERPROFILE%\.local\bin')
        $changed = Add-UserPath -Path $expanded -Prepend

        $changed | Should -BeTrue
        $script:writtenEntries | Should -Be @('%USERPROFILE%\.local\bin', 'C:\other', 'C:\third')
        $script:updateCalls | Should -Be 1
    }

    It '-Prepend, 같은 경로가 둘째·넷째에 두 번 -> 둘 다 빠지고 하나만 맨 앞, $true' {
        $script:writtenEntries = $null
        $script:updateCalls = 0
        Mock -ModuleName EnvPath Get-UserPathEntries { return @('C:\first', 'C:\dup\bin', 'C:\middle', 'C:\DUP\BIN\') }
        Mock -ModuleName EnvPath Set-UserPathEntries { $script:writtenEntries = $Entries }
        Mock -ModuleName EnvPath Update-SessionPath { $script:updateCalls++ }

        $changed = Add-UserPath -Path 'C:\dup\bin' -Prepend

        $changed | Should -BeTrue
        $script:writtenEntries | Should -Be @('C:\dup\bin', 'C:\first', 'C:\middle')
        $script:updateCalls | Should -Be 1
    }

    It '-Prepend 없음, %LOCALAPPDATA%\pnpm 꼴로 이미 있고 $Path 는 펼친 값 -> $false, Set-UserPathEntries 안 불림' {
        $script:setCalls = 0
        $script:updateCalls = 0
        Mock -ModuleName EnvPath Get-UserPathEntries { return @('C:\first', '%LOCALAPPDATA%\pnpm') }
        Mock -ModuleName EnvPath Set-UserPathEntries { $script:setCalls++ }
        Mock -ModuleName EnvPath Update-SessionPath { $script:updateCalls++ }

        $expanded = [System.Environment]::ExpandEnvironmentVariables('%LOCALAPPDATA%\pnpm')
        $changed = Add-UserPath -Path $expanded

        $changed | Should -BeFalse
        $script:setCalls | Should -Be 0
        $script:updateCalls | Should -Be 0
    }
}

Describe 'Update-SessionPath' {
    It '시스템(HKLM) 다음에 사용자(HKCU) 조각을 순서대로 잇고 빈 조각은 빼며 환경 변수를 펼친다' {
        $savedPath = $env:Path
        try {
            $env:Path = 'C:\before'
            Mock -ModuleName EnvPath Get-EnvironmentPath {
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
