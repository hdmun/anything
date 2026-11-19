Describe 'OfficialAgentCli' {
    Describe 'agy' {
        BeforeAll {
            $agyScript = Join-Path $PSScriptRoot '..' 'apps' 'agy.ps1'
            . $agyScript
        }

        It '실행 파일 있음 + PATH 에 있음(이 PC 모양) -> 그대로, 설치·PATH 쓰기 안 불림' {
            $agyDir = Join-Path $env:LOCALAPPDATA 'agy\bin'
            Mock Test-ExecutableExists { return $true }
            Mock Get-UserPathEntries { return @('C:\Windows\System32', $agyDir) }
            Mock Invoke-InstallScript { return 0 }
            Mock Add-UserPath { return $true }
            Mock Update-SessionPath {}

            $resCheck = Invoke-Main -Check:$true
            $resCheck | Should -Be '그대로'

            $resFix = Invoke-Main -Check:$false
            $resFix | Should -Be '그대로'

            Should -Invoke Invoke-InstallScript -Times 0
            Should -Invoke Add-UserPath -Times 0
            Should -Invoke Update-SessionPath -Times 0
        }

        It '실행 파일 없음, -Check -> 다름 (agy.exe 없음, ...), 설치 안 불림' {
            Mock Test-ExecutableExists { return $false }
            Mock Get-UserPathEntries { return @('C:\Windows\System32') }
            Mock Invoke-InstallScript { return 0 }
            Mock Add-UserPath { return $true }

            $res = Invoke-Main -Check:$true
            $res | Should -Be '다름 (agy.exe 없음, agy\bin 이 사용자 PATH 에 없음)'

            Should -Invoke Invoke-InstallScript -Times 0
            Should -Invoke Add-UserPath -Times 0
        }

        It '실행 파일 없음 -> 설치 -> 생김, PATH 에 없음 -> 설치 1번, Add-UserPath 1번, 바꿈' {
            $script:agyExeCalls = 0
            Mock Test-ExecutableExists {
                $script:agyExeCalls++
                return ($script:agyExeCalls -ge 2)
            }
            Mock Get-UserPathEntries { return @('C:\Windows\System32') }
            Mock Invoke-InstallScript { return 0 }
            Mock Add-UserPath { return $true }
            Mock Update-SessionPath {}

            $res = Invoke-Main -Check:$false
            $res | Should -Be '바꿈'

            Should -Invoke Invoke-InstallScript -Times 1 -ParameterFilter {
                $Uri -eq 'https://antigravity.google/cli/install.ps1'
            }
            Should -Invoke Add-UserPath -Times 1 -ParameterFilter {
                (-not $Prepend) -and ($Path -eq (Join-Path $env:LOCALAPPDATA 'agy\bin'))
            }
            Should -Invoke Update-SessionPath -Times 1
        }

        It '설치 뒤에도 실행 파일 없음 -> 실패: agy.exe 가 생기지 않았다' {
            Mock Test-ExecutableExists { return $false }
            Mock Get-UserPathEntries { return @('C:\Windows\System32') }
            Mock Invoke-InstallScript { return 0 }
            Mock Add-UserPath { return $true }
            Mock Update-SessionPath {}

            $res = Invoke-Main -Check:$false
            $res | Should -Be '실패: agy.exe 가 생기지 않았다'

            Should -Invoke Invoke-InstallScript -Times 1
            Should -Invoke Add-UserPath -Times 0
        }

        It 'PATH 항목이 %LOCALAPPDATA%\agy\bin\(펼치지 않은 꼴, 끝 \) -> PATH 조건 맞음' {
            Mock Test-ExecutableExists { return $true }
            Mock Get-UserPathEntries { return @('%LOCALAPPDATA%\agy\bin\') }
            Mock Invoke-InstallScript { return 0 }
            Mock Add-UserPath { return $true }

            $res = Invoke-Main -Check:$true
            $res | Should -Be '그대로'
        }
    }

    Describe 'claude-code' {
        BeforeAll {
            $claudeScript = Join-Path $PSScriptRoot '..' 'apps' 'claude-code.ps1'
            . $claudeScript
        }

        It '실행 파일 있음 + PATH 첫 항목 -> 그대로' {
            $claudeDir = Join-Path $env:USERPROFILE '.local\bin'
            Mock Test-ExecutableExists { return $true }
            Mock Get-UserPathEntries { return @($claudeDir, 'C:\Windows\System32') }
            Mock Invoke-InstallScript { return 0 }
            Mock Add-UserPath { return $true }
            Mock Update-SessionPath {}

            $resCheck = Invoke-Main -Check:$true
            $resCheck | Should -Be '그대로'

            $resFix = Invoke-Main -Check:$false
            $resFix | Should -Be '그대로'

            Should -Invoke Invoke-InstallScript -Times 0
            Should -Invoke Add-UserPath -Times 0
        }

        It '실행 파일 없음 + PATH 에 없음(이 PC 모양), -Check -> 다름 (claude.exe 없음, ~/.local/bin 이 사용자 PATH 맨 앞이 아님)' {
            Mock Test-ExecutableExists { return $false }
            Mock Get-UserPathEntries { return @('C:\Windows\System32') }
            Mock Invoke-InstallScript { return 0 }
            Mock Add-UserPath { return $true }

            $res = Invoke-Main -Check:$true
            $res | Should -Be '다름 (claude.exe 없음, ~/.local/bin 이 사용자 PATH 맨 앞이 아님)'

            Should -Invoke Invoke-InstallScript -Times 0
            Should -Invoke Add-UserPath -Times 0
        }

        It '실행 파일 있음 + PATH 셋째 항목(손으로 설치한 경우) -> 설치 안 불림, Add-UserPath -Prepend 1번, 바꿈' {
            $claudeDir = Join-Path $env:USERPROFILE '.local\bin'
            Mock Test-ExecutableExists { return $true }
            Mock Get-UserPathEntries { return @('C:\first', 'C:\second', $claudeDir) }
            Mock Invoke-InstallScript { return 0 }
            Mock Add-UserPath { return $true }
            Mock Update-SessionPath {}

            $res = Invoke-Main -Check:$false
            $res | Should -Be '바꿈'

            Should -Invoke Invoke-InstallScript -Times 0
            Should -Invoke Add-UserPath -Times 1 -ParameterFilter {
                $Prepend -and ($Path -eq $claudeDir)
            }
        }

        It '실행 파일 없음 -> 설치 -> 생김 + PATH 없음 -> 설치 1번, -Prepend 1번, 바꿈' {
            $claudeDir = Join-Path $env:USERPROFILE '.local\bin'
            $script:claudeExeCalls = 0
            Mock Test-ExecutableExists {
                $script:claudeExeCalls++
                return ($script:claudeExeCalls -ge 2)
            }
            Mock Get-UserPathEntries { return @('C:\Windows\System32') }
            Mock Invoke-InstallScript { return 0 }
            Mock Add-UserPath { return $true }
            Mock Update-SessionPath {}

            $res = Invoke-Main -Check:$false
            $res | Should -Be '바꿈'

            Should -Invoke Invoke-InstallScript -Times 1 -ParameterFilter {
                $Uri -eq 'https://claude.ai/install.ps1'
            }
            Should -Invoke Add-UserPath -Times 1 -ParameterFilter {
                $Prepend -and ($Path -eq $claudeDir)
            }
            Should -Invoke Update-SessionPath -Times 1
        }

        It '설치 자식 종료 코드 1 -> 실패: 설치 스크립트 종료 코드 1' {
            Mock Test-ExecutableExists { return $false }
            Mock Get-UserPathEntries { return @('C:\Windows\System32') }
            Mock Invoke-InstallScript { return 1 }
            Mock Add-UserPath { return $true }
            Mock Update-SessionPath {}

            $res = Invoke-Main -Check:$false
            $res | Should -Be '실패: 설치 스크립트 종료 코드 1'

            Should -Invoke Invoke-InstallScript -Times 1
            Should -Invoke Add-UserPath -Times 0
            Should -Invoke Update-SessionPath -Times 0
        }
    }
}
