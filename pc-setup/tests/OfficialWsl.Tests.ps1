Describe 'OfficialWsl' {
    Describe 'wsl' {
        BeforeAll {
            $wslScript = Join-Path $PSScriptRoot '..' 'apps' 'wsl.ps1'
            . $wslScript
        }

        It '패키지 있음 + 기능 1 -> 그대로 (쓰기 함수 안 불림)' {
            Mock Get-WslPackage { [pscustomobject]@{ Name = 'MicrosoftCorporationII.WindowsSubsystemForLinux' } }
            Mock Get-FeatureState { return 1 }
            Mock Invoke-Wsl { return 0 }

            $resCheck = Invoke-Main -Check:$true
            $resCheck | Should -Be '그대로'

            $resFix = Invoke-Main -Check:$false
            $resFix | Should -Be '그대로'

            Should -Invoke Invoke-Wsl -Times 0
        }

        It '패키지 없음, -Check -> 다름 (...), 쓰기 안 불림' {
            Mock Get-WslPackage { return $null }
            Mock Get-FeatureState { return 1 }
            Mock Invoke-Wsl { return 0 }

            $res = Invoke-Main -Check:$true
            $res | Should -BeLike '다름 (*)'

            Should -Invoke Invoke-Wsl -Times 0
        }

        It '패키지 없음 -> 설치 뒤 패키지 있음 + 기능 2 -> 설치 1번, 할 일: 재부팅 후 셋업 다시 실행' {
            $script:wslPkgCalls = 0
            Mock Get-WslPackage {
                $script:wslPkgCalls++
                if ($script:wslPkgCalls -eq 1) { return $null }
                return [pscustomobject]@{ Name = 'MicrosoftCorporationII.WindowsSubsystemForLinux' }
            }
            Mock Get-FeatureState { return 2 }
            Mock Test-WslCommand { return $true }
            Mock Invoke-Wsl { return 0 }

            $res = Invoke-Main -Check:$false
            $res | Should -Be '할 일: 재부팅 후 셋업 다시 실행'

            Should -Invoke Invoke-Wsl -Times 1 -ParameterFilter {
                ($Arguments -contains '--install') -and ($Arguments -contains '--no-distribution')
            }
        }

        It '패키지 없음 -> 설치 뒤 패키지 있음 + 기능 1 -> 바꿈' {
            $script:wslPkgCalls2 = 0
            Mock Get-WslPackage {
                $script:wslPkgCalls2++
                if ($script:wslPkgCalls2 -eq 1) { return $null }
                return [pscustomobject]@{ Name = 'MicrosoftCorporationII.WindowsSubsystemForLinux' }
            }
            $script:wslFeatCalls = 0
            Mock Get-FeatureState {
                $script:wslFeatCalls++
                if ($script:wslFeatCalls -eq 1) { return 2 }
                return 1
            }
            Mock Test-WslCommand { return $true }
            Mock Invoke-Wsl { return 0 }

            $res = Invoke-Main -Check:$false
            $res | Should -Be '바꿈'

            Should -Invoke Invoke-Wsl -Times 1
        }

        It '패키지 있음 + 기능 2, 고치는 실행 -> 설치 안 불림, 할 일: 재부팅 후 셋업 다시 실행' {
            Mock Get-WslPackage { [pscustomobject]@{ Name = 'MicrosoftCorporationII.WindowsSubsystemForLinux' } }
            Mock Get-FeatureState { return 2 }
            Mock Invoke-Wsl { return 0 }

            $res = Invoke-Main -Check:$false
            $res | Should -Be '할 일: 재부팅 후 셋업 다시 실행'

            Should -Invoke Invoke-Wsl -Times 0
        }

        It '설치 명령 실패(종료 코드 1) 뒤 패키지 여전히 없음 -> 실패: ...' {
            Mock Get-WslPackage { return $null }
            Mock Get-FeatureState { return 2 }
            Mock Test-WslCommand { return $true }
            Mock Invoke-Wsl { return 1 }

            $res = Invoke-Main -Check:$false
            $res | Should -BeLike '실패: *'
        }
    }

    Describe 'ubuntu-24.04' {
        BeforeAll {
            $ubuntuScript = Join-Path $PSScriptRoot '..' 'apps' 'ubuntu-24.04.ps1'
            . $ubuntuScript
        }

        It '배포판 목록에 Ubuntu-24.04 -> 그대로' {
            Mock Get-WslPackage { [pscustomobject]@{ Name = 'MicrosoftCorporationII.WindowsSubsystemForLinux' } }
            Mock Get-FeatureState { return 1 }
            Mock Test-WslCommand { return $true }
            Mock Get-WslDistros { @('Ubuntu-24.04', 'docker-desktop') }
            Mock Invoke-Wsl { return 0 }

            $resCheck = Invoke-Main -Check:$true
            $resCheck | Should -Be '그대로'

            $resFix = Invoke-Main -Check:$false
            $resFix | Should -Be '그대로'

            Should -Invoke Invoke-Wsl -Times 0
        }

        It '목록에 Ubuntu-22.04 만 -> -Check 는 다름 (배포판 없음), 고치는 실행은 설치 1번' {
            Mock Get-WslPackage { [pscustomobject]@{ Name = 'MicrosoftCorporationII.WindowsSubsystemForLinux' } }
            Mock Get-FeatureState { return 1 }
            Mock Test-WslCommand { return $true }
            Mock Get-WslDistros { @('Ubuntu-22.04') }
            Mock Invoke-Wsl { return 0 }

            $resCheck = Invoke-Main -Check:$true
            $resCheck | Should -Be '다름 (배포판 없음)'
            Should -Invoke Invoke-Wsl -Times 0

            $resFix = Invoke-Main -Check:$false
            Should -Invoke Invoke-Wsl -Times 1 -ParameterFilter {
                ($Arguments -contains '--install') -and
                ($Arguments -contains '-d') -and
                ($Arguments -contains 'Ubuntu-24.04') -and
                ($Arguments -contains '--no-launch')
            }
        }

        It '가짜 목록 읽기가 종료 코드 1 과 오류 문구를 돌려줌(배포판 0개인 새 PC) -> 빈 목록으로 본다' {
            Mock Get-WslPackage { [pscustomobject]@{ Name = 'MicrosoftCorporationII.WindowsSubsystemForLinux' } }
            Mock Get-FeatureState { return 1 }
            Mock Test-WslCommand { return $true }
            Mock Invoke-WslListRaw {
                [pscustomobject]@{
                    ExitCode = 1
                    Output   = "There are no installed distributions.`nError code: Wsl/WSL_E_DEFAULT_DISTRO_NOT_FOUND"
                }
            }
            Mock Invoke-Wsl { return 0 }

            @(Get-WslDistros).Count | Should -Be 0

            $resCheck = Invoke-Main -Check:$true
            $resCheck | Should -Be '다름 (배포판 없음)'
            Should -Invoke Invoke-Wsl -Times 0

            $resFix = Invoke-Main -Check:$false
            Should -Invoke Invoke-Wsl -Times 1 -ParameterFilter {
                ($Arguments -contains '--install') -and
                ($Arguments -contains '-d') -and
                ($Arguments -contains 'Ubuntu-24.04') -and
                ($Arguments -contains '--no-launch')
            }
        }

        It 'WSL 쓸 수 없음 -> 설치 안 불림, 할 일: 재부팅 후 셋업 다시 실행' {
            Mock Get-WslPackage { return $null }
            Mock Get-FeatureState { return 2 }
            Mock Get-WslDistros { @() }
            Mock Invoke-Wsl { return 0 }

            $resCheck = Invoke-Main -Check:$true
            $resCheck | Should -Be '할 일: 재부팅 후 셋업 다시 실행'

            $resFix = Invoke-Main -Check:$false
            $resFix | Should -Be '할 일: 재부팅 후 셋업 다시 실행'

            Should -Invoke Invoke-Wsl -Times 0
        }

        It '설치 뒤 목록에 생김 -> 할 일: wsl -d Ubuntu-24.04 로 처음 실행해 사용자를 만든다' {
            Mock Get-WslPackage { [pscustomobject]@{ Name = 'MicrosoftCorporationII.WindowsSubsystemForLinux' } }
            Mock Get-FeatureState { return 1 }
            Mock Test-WslCommand { return $true }
            $script:distroCalls = 0
            Mock Get-WslDistros {
                $script:distroCalls++
                if ($script:distroCalls -eq 1) { return @() }
                return @('Ubuntu-24.04')
            }
            Mock Invoke-Wsl { return 0 }

            $res = Invoke-Main -Check:$false
            $res | Should -Be '할 일: wsl -d Ubuntu-24.04 로 처음 실행해 사용자를 만든다'

            Should -Invoke Invoke-Wsl -Times 1
        }

        It '목록 출력에 NUL 이 섞인 UTF-16 문자열이 와도 Get-WslDistros 가 NUL 을 지우고 같은 결과' {
            $utf16Like = "U`0b`0u`0n`0t`0u`0-`02`04`0.`00`04`0`r`n`0d`0o`0c`0k`0e`0r`0-`0d`0e`0s`0k`0t`0o`0p`0"
            Mock Invoke-WslListRaw {
                [pscustomobject]@{
                    ExitCode = 0
                    Output   = $utf16Like
                }
            }

            $distros = Get-WslDistros
            $distros | Should -Be @('Ubuntu-24.04', 'docker-desktop')
        }
    }
}
