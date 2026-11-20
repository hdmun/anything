Describe 'OfficialMisc' {
    Describe 'flutter' {
        BeforeAll {
            $flutterScript = Join-Path $PSScriptRoot '..' 'apps' 'flutter.ps1'
            . $flutterScript
        }

        It 'flutter.bat 있음 + PATH 있음 -> 그대로, clone·PATH 쓰기 안 불림' {
            $flutterBinDir = Join-Path $env:USERPROFILE 'develop\flutter\bin'
            Mock Test-FlutterBatExists { return $true }
            Mock Test-FlutterDirExists { return $true }
            Mock Get-UserPathEntries { return @('C:\Windows\System32', $flutterBinDir) }
            Mock Invoke-GitClone { return 0 }
            Mock Add-UserPath { return $true }
            Mock Update-SessionPath {}
            Mock Ensure-Directory {}

            $resCheck = Invoke-Main -Check:$true
            $resCheck | Should -Be '그대로'

            $resFix = Invoke-Main -Check:$false
            $resFix | Should -Be '그대로'

            Should -Invoke Invoke-GitClone -Times 0
            Should -Invoke Add-UserPath -Times 0
        }

        It '폴더 없음, -Check -> 다름 (flutter.bat 없음, ...), clone 안 불림' {
            Mock Test-FlutterBatExists { return $false }
            Mock Test-FlutterDirExists { return $false }
            Mock Get-UserPathEntries { return @('C:\Windows\System32') }
            Mock Invoke-GitClone { return 0 }
            Mock Add-UserPath { return $true }

            $res = Invoke-Main -Check:$true
            $res | Should -Be '다름 (flutter.bat 없음, flutter\bin 이 사용자 PATH 에 없음)'

            Should -Invoke Invoke-GitClone -Times 0
            Should -Invoke Add-UserPath -Times 0
        }

        It '폴더 없음 -> clone 성공, PATH 없음 -> clone 1번(인자에 -b stable), Add-UserPath 1번, 바꿈' {
            $flutterBinDir = Join-Path $env:USERPROFILE 'develop\flutter\bin'
            Mock Test-FlutterBatExists { return $false }
            Mock Test-FlutterDirExists { return $false }
            Mock Test-GitAvailable { return $true }
            Mock Ensure-Directory {}
            Mock Invoke-GitClone { return 0 }
            Mock Get-UserPathEntries { return @('C:\Windows\System32') }
            Mock Add-UserPath { return $true }
            Mock Update-SessionPath {}

            $res = Invoke-Main -Check:$false
            $res | Should -Be '바꿈'

            Should -Invoke Invoke-GitClone -Times 1 -ParameterFilter {
                ($Arguments -join ' ') -match '-b stable'
            }
            Should -Invoke Add-UserPath -Times 1 -ParameterFilter {
                (-not $Prepend) -and ($Path -eq $flutterBinDir)
            }
        }

        It 'clone 종료 코드 128 -> 실패: git clone 종료 코드 128' {
            Mock Test-FlutterBatExists { return $false }
            Mock Test-FlutterDirExists { return $false }
            Mock Test-GitAvailable { return $true }
            Mock Ensure-Directory {}
            Mock Invoke-GitClone { return 128 }
            Mock Get-UserPathEntries { return @('C:\Windows\System32') }
            Mock Add-UserPath { return $true }
            Mock Update-SessionPath {}

            $res = Invoke-Main -Check:$false
            $res | Should -Be '실패: git clone 종료 코드 128'

            Should -Invoke Invoke-GitClone -Times 1
            Should -Invoke Add-UserPath -Times 0
        }

        It '폴더 있음 + flutter.bat 없음 -> clone 안 불림, 실패: ...Flutter 저장소가 아니다' {
            Mock Test-FlutterBatExists { return $false }
            Mock Test-FlutterDirExists { return $true }
            Mock Invoke-GitClone { return 0 }
            Mock Get-UserPathEntries { return @('C:\Windows\System32') }
            Mock Add-UserPath { return $true }
            Mock Update-SessionPath {}

            $res = Invoke-Main -Check:$false
            $res | Should -Be '실패: ~/develop/flutter 가 Flutter 저장소가 아니다'

            Should -Invoke Invoke-GitClone -Times 0
            Should -Invoke Add-UserPath -Times 0
        }

        It 'flutter.bat 있음 + PATH 없음 -> clone 안 불림, Add-UserPath 1번, 바꿈' {
            $flutterBinDir = Join-Path $env:USERPROFILE 'develop\flutter\bin'
            Mock Test-FlutterBatExists { return $true }
            Mock Test-FlutterDirExists { return $true }
            Mock Invoke-GitClone { return 0 }
            Mock Get-UserPathEntries { return @('C:\Windows\System32') }
            Mock Add-UserPath { return $true }
            Mock Update-SessionPath {}

            $res = Invoke-Main -Check:$false
            $res | Should -Be '바꿈'

            Should -Invoke Invoke-GitClone -Times 0
            Should -Invoke Add-UserPath -Times 1 -ParameterFilter {
                (-not $Prepend) -and ($Path -eq $flutterBinDir)
            }
        }

        It 'USERPROFILE 경로에 공백이 있어도 목적지 경로를 하나의 인자로 전달한다' {
            $origProfile = $env:USERPROFILE
            try {
                $env:USERPROFILE = 'C:\Users\Jane Doe'
                Mock Test-FlutterBatExists { return $false }
                Mock Test-FlutterDirExists { return $false }
                Mock Test-GitAvailable { return $true }
                Mock Ensure-Directory {}
                Mock Invoke-GitClone { return 0 }
                Mock Get-UserPathEntries { return @('C:\Users\Jane Doe\develop\flutter\bin') }
                Mock Add-UserPath { return $true }
                Mock Update-SessionPath {}

                $res = Invoke-Main -Check:$false
                $res | Should -Be '바꿈'

                Should -Invoke Invoke-GitClone -Times 1 -ParameterFilter {
                    $Arguments.Count -eq 5 -and $Arguments[4] -eq 'C:\Users\Jane Doe\develop\flutter'
                }
            } finally {
                $env:USERPROFILE = $origProfile
            }
        }
    }

    Describe 'nvidia-driver' {
        BeforeAll {
            $nvidiaScript = Join-Path $PSScriptRoot '..' 'apps' 'nvidia-driver.ps1'
            . $nvidiaScript
        }

        It 'VEN_10DE 장치 없음 -> 그대로' {
            Mock Get-DisplayDrivers {
                @(
                    [pscustomobject]@{
                        DeviceName         = 'Microsoft Basic Display Adapter'
                        HardWareID         = 'PCI\VEN_1234&DEV_1111'
                        DriverProviderName = 'Microsoft'
                    }
                )
            }

            (Invoke-Main -Check:$true) | Should -Be '그대로'
            (Invoke-Main -Check:$false) | Should -Be '그대로'
        }

        It 'VEN_10DE 장치 + 제공자 NVIDIA(이 PC 모양) -> 그대로' {
            Mock Get-DisplayDrivers {
                @(
                    [pscustomobject]@{
                        DeviceName         = 'NVIDIA GeForce RTX 5060 Ti'
                        HardWareID         = 'PCI\VEN_10DE&DEV_2D04&SUBSYS_177219DA&REV_A1'
                        DriverProviderName = 'NVIDIA'
                    }
                )
            }

            (Invoke-Main -Check:$true) | Should -Be '그대로'
            (Invoke-Main -Check:$false) | Should -Be '그대로'
        }

        It 'VEN_10DE 장치 + 제공자 Microsoft -> 할 일: NVIDIA 드라이버 설치 (-Check 와 고치는 실행 모두)' {
            Mock Get-DisplayDrivers {
                @(
                    [pscustomobject]@{
                        DeviceName         = 'Microsoft Basic Display Adapter'
                        HardWareID         = 'PCI\VEN_10DE&DEV_2D04&SUBSYS_177219DA&REV_A1'
                        DriverProviderName = 'Microsoft'
                    }
                )
            }

            (Invoke-Main -Check:$true) | Should -Be '할 일: NVIDIA 드라이버 설치'
            (Invoke-Main -Check:$false) | Should -Be '할 일: NVIDIA 드라이버 설치'
        }
    }

    Describe 'pester' {
        BeforeAll {
            $pesterScript = Join-Path $PSScriptRoot '..' 'apps' 'pester.ps1'
            . $pesterScript
        }

        It '6.2.0 있음 -> 그대로, 설치 안 불림' {
            Mock Get-InstalledPesterResources {
                @([pscustomobject]@{ Name = 'Pester'; Version = [version]'6.2.0' })
            }
            Mock Install-PesterResource {}

            (Invoke-Main -Check:$true) | Should -Be '그대로'
            (Invoke-Main -Check:$false) | Should -Be '그대로'

            Should -Invoke Install-PesterResource -Times 0
        }

        It '5.7.1 만 있음, -Check -> 다름 (Pester 6 없음)' {
            Mock Get-InstalledPesterResources {
                @([pscustomobject]@{ Name = 'Pester'; Version = [version]'5.7.1' })
            }
            Mock Install-PesterResource {}

            (Invoke-Main -Check:$true) | Should -Be '다름 (Pester 6 없음)'

            Should -Invoke Install-PesterResource -Times 0
        }

        It '없음 -> 설치 -> 6.2.0 생김 -> 설치 1번(인자에 -Version ''[6.0,7.0)''·-Scope CurrentUser), 바꿈' {
            $script:pesterCheckCalls = 0
            Mock Get-InstalledPesterResources {
                $script:pesterCheckCalls++
                if ($script:pesterCheckCalls -ge 2) {
                    return @([pscustomobject]@{ Name = 'Pester'; Version = [version]'6.2.0' })
                }
                return @()
            }
            Mock Install-PesterResource {}

            $res = Invoke-Main -Check:$false
            $res | Should -Be '바꿈'

            Should -Invoke Install-PesterResource -Times 1 -ParameterFilter {
                ($Version -eq '[6.0,7.0)') -and ($Scope -eq 'CurrentUser')
            }
        }

        It '설치 뒤에도 없음 -> 실패: Pester 6 이 설치되지 않았다' {
            Mock Get-InstalledPesterResources { return @() }
            Mock Install-PesterResource {}

            $res = Invoke-Main -Check:$false
            $res | Should -Be '실패: Pester 6 이 설치되지 않았다'

            Should -Invoke Install-PesterResource -Times 1
        }
    }
}
