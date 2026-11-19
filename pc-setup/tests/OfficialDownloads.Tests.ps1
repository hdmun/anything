Describe 'OfficialDownloads' {
    Describe 'raidrive' {
        BeforeAll {
            $raidriveScript = Join-Path $PSScriptRoot '..' 'apps' 'raidrive.ps1'
            . $raidriveScript
        }

        It '제거 목록에 RaiDrive Mount -> 그대로, 내려받기 안 불림' {
            Mock Get-RaiDriveUninstallEntry { [pscustomobject]@{ DisplayName = 'RaiDrive Mount' } }
            Mock Get-RaiDriveDownloadPage { '' }
            Mock Invoke-FileDownload {}
            Mock Invoke-MsiExec { return 0 }

            $resCheck = Invoke-Main -Check:$true
            $resCheck | Should -Be '그대로'

            $resFix = Invoke-Main -Check:$false
            $resFix | Should -Be '그대로'

            Should -Invoke Get-RaiDriveDownloadPage -Times 0
            Should -Invoke Invoke-FileDownload -Times 0
        }

        It '없음, -Check -> 다름 (설치 안 됨), 내려받기 안 불림' {
            Mock Get-RaiDriveUninstallEntry { return $null }
            Mock Get-RaiDriveDownloadPage { '' }
            Mock Invoke-FileDownload {}
            Mock Invoke-MsiExec { return 0 }

            $res = Invoke-Main -Check:$true
            $res | Should -Be '다름 (설치 안 됨)'

            Should -Invoke Get-RaiDriveDownloadPage -Times 0
            Should -Invoke Invoke-FileDownload -Times 0
            Should -Invoke Invoke-MsiExec -Times 0
        }

        It '없음 -> 페이지에 MSI 주소 -> msiexec 0 -> 다시 읽으면 있음 -> 바꿈, msiexec 인자에 /qn·/norestart' {
            $script:rdEntryCalls = 0
            Mock Get-RaiDriveUninstallEntry {
                $script:rdEntryCalls++
                if ($script:rdEntryCalls -eq 1) { return $null }
                return [pscustomobject]@{ DisplayName = 'RaiDrive Mount' }
            }
            Mock Get-RaiDriveDownloadPage {
                '<a href="https://app.raidrive.com/download/raidrive.mount/release/RaiDrive.Mount_2026.10.0_x64.msi">Download</a>'
            }
            Mock Invoke-FileDownload {}
            Mock Invoke-MsiExec { return 0 }

            $res = Invoke-Main -Check:$false
            $res | Should -Be '바꿈'

            Should -Invoke Invoke-FileDownload -Times 1
            Should -Invoke Invoke-MsiExec -Times 1 -ParameterFilter {
                ($Arguments -contains '/i') -and
                ($Arguments -contains '/qn') -and
                ($Arguments -contains '/norestart')
            }
        }

        It 'msiexec 3010 -> 할 일: 재부팅 후 셋업 다시 실행' {
            Mock Get-RaiDriveUninstallEntry { return $null }
            Mock Get-RaiDriveDownloadPage {
                '<a href="https://app.raidrive.com/download/raidrive.mount/release/RaiDrive.Mount_2026.10.0_x64.msi">Download</a>'
            }
            Mock Invoke-FileDownload {}
            Mock Invoke-MsiExec { return 3010 }

            $res = Invoke-Main -Check:$false
            $res | Should -Be '할 일: 재부팅 후 셋업 다시 실행'
        }

        It 'msiexec 1603 -> 실패: msiexec 종료 코드 1603' {
            Mock Get-RaiDriveUninstallEntry { return $null }
            Mock Get-RaiDriveDownloadPage {
                '<a href="https://app.raidrive.com/download/raidrive.mount/release/RaiDrive.Mount_2026.10.0_x64.msi">Download</a>'
            }
            Mock Invoke-FileDownload {}
            Mock Invoke-MsiExec { return 1603 }

            $res = Invoke-Main -Check:$false
            $res | Should -Be '실패: msiexec 종료 코드 1603'
        }

        It '페이지에 맞는 주소 없음 -> 실패: RaiDrive 내려받기 주소를 찾지 못했다' {
            Mock Get-RaiDriveUninstallEntry { return $null }
            Mock Get-RaiDriveDownloadPage { '<html><body>no link</body></html>' }
            Mock Invoke-FileDownload {}
            Mock Invoke-MsiExec { return 0 }

            $res = Invoke-Main -Check:$false
            $res | Should -Be '실패: RaiDrive 내려받기 주소를 찾지 못했다'

            Should -Invoke Invoke-FileDownload -Times 0
            Should -Invoke Invoke-MsiExec -Times 0
        }

        It 'Invoke-MsiExec 는 공백이 있는 인자를 큰따옴표로 감싸 Start-Process 에 넘긴다' {
            Mock Start-Process { [pscustomobject]@{ ExitCode = 0 } }

            $exitCode = Invoke-MsiExec -Arguments @('/i', 'C:\Users\Jane Doe\AppData\Local\Temp\RaiDrive.msi', '/qn', '/norestart')
            $exitCode | Should -Be 0

            Should -Invoke Start-Process -Times 1 -ParameterFilter {
                ($FilePath -eq 'msiexec.exe') -and
                ($ArgumentList -contains '"C:\Users\Jane Doe\AppData\Local\Temp\RaiDrive.msi"')
            }
        }
    }

    Describe 'd2coding' {
        BeforeAll {
            $d2Script = Join-Path $PSScriptRoot '..' 'apps' 'd2coding.ps1'
            . $d2Script
        }

        It '폰트 값 있음 + 파일 있음 -> 그대로' {
            Mock Get-D2CodingFontPaths { @('C:\Users\test\AppData\Local\Microsoft\Windows\Fonts\D2Coding-Ver1.3.2-20180524-all.ttc') }
            Mock Test-FileExists { return $true }
            Mock Get-D2CodingLatestRelease { $null }

            $resCheck = Invoke-Main -Check:$true
            $resCheck | Should -Be '그대로'

            $resFix = Invoke-Main -Check:$false
            $resFix | Should -Be '그대로'

            Should -Invoke Get-D2CodingLatestRelease -Times 0
        }

        It '폰트 값 있음 + 파일 없음, -Check -> 다름 (설치 안 됨)' {
            Mock Get-D2CodingFontPaths { @('C:\Users\test\AppData\Local\Microsoft\Windows\Fonts\D2Coding-Ver1.3.2-20180524-all.ttc') }
            Mock Test-FileExists { return $false }
            Mock Get-D2CodingLatestRelease { $null }

            $res = Invoke-Main -Check:$true
            $res | Should -Be '다름 (설치 안 됨)'

            Should -Invoke Get-D2CodingLatestRelease -Times 0
        }

        It '없음 -> 자산 받기 -> D2CodingAll/*-all.ttc 있음 -> 복사 1번, 레지스트리 쓰기 1번, 바꿈' {
            $zipSourceDir = Join-Path (Get-Item 'TestDrive:/').FullName 'd2-src-ok'
            New-Item -ItemType Directory -Path (Join-Path $zipSourceDir 'D2Coding') -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $zipSourceDir 'D2CodingAll') -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $zipSourceDir 'D2CodingLigature') -Force | Out-Null
            Set-Content -Path (Join-Path $zipSourceDir 'D2CodingAll' 'D2Coding-Ver1.4.0-20261003-all.ttc') -Value 'fake-ttc'
            $fakeZipPath = Join-Path (Get-Item 'TestDrive:/').FullName 'D2Coding-Ver1.4.0-20261003.zip'
            Compress-Archive -Path (Join-Path $zipSourceDir '*') -DestinationPath $fakeZipPath -Force

            Mock Get-D2CodingFontPaths { @() }
            Mock Get-D2CodingLatestRelease {
                [pscustomobject]@{
                    assets = @(
                        [pscustomobject]@{
                            name                 = 'D2Coding-Ver1.4.0-20261003.zip'
                            browser_download_url = 'https://example.invalid/D2Coding-Ver1.4.0-20261003.zip'
                        }
                    )
                }
            }
            Mock Invoke-FileDownload {
                Copy-Item -LiteralPath $fakeZipPath -Destination $OutFile -Force
            }
            Mock Copy-FontFile {}
            Mock Set-D2CodingFontRegistry {}

            $res = Invoke-Main -Check:$false
            $res | Should -Be '바꿈'

            Should -Invoke Copy-FontFile -Times 1
            Should -Invoke Set-D2CodingFontRegistry -Times 1 -ParameterFilter {
                $Name -eq 'D2Coding & D2Coding Bold & D2Coding ligature & D2Coding ligature Bold (TrueType)'
            }
        }

        It '릴리스에 zip 자산 없음 -> 실패: D2Coding 릴리스 자산을 찾지 못했다' {
            Mock Get-D2CodingFontPaths { @() }
            Mock Get-D2CodingLatestRelease {
                [pscustomobject]@{
                    assets = @(
                        [pscustomobject]@{
                            name                 = 'README.txt'
                            browser_download_url = 'https://example.invalid/README.txt'
                        }
                    )
                }
            }
            Mock Invoke-FileDownload {}
            Mock Copy-FontFile {}
            Mock Set-D2CodingFontRegistry {}

            $res = Invoke-Main -Check:$false
            $res | Should -Be '실패: D2Coding 릴리스 자산을 찾지 못했다'

            Should -Invoke Invoke-FileDownload -Times 0
            Should -Invoke Copy-FontFile -Times 0
            Should -Invoke Set-D2CodingFontRegistry -Times 0
        }

        It 'zip 안에 D2CodingAll 없음 -> 실패: D2Coding all.ttc 가 없다' {
            $zipSourceDir = Join-Path (Get-Item 'TestDrive:/').FullName 'd2-src-noall'
            New-Item -ItemType Directory -Path (Join-Path $zipSourceDir 'D2Coding') -Force | Out-Null
            Set-Content -Path (Join-Path $zipSourceDir 'D2Coding' 'D2Coding.ttf') -Value 'fake-ttf'
            $fakeZipPath = Join-Path (Get-Item 'TestDrive:/').FullName 'D2Coding-Ver1.4.0-noall.zip'
            Compress-Archive -Path (Join-Path $zipSourceDir '*') -DestinationPath $fakeZipPath -Force

            Mock Get-D2CodingFontPaths { @() }
            Mock Get-D2CodingLatestRelease {
                [pscustomobject]@{
                    assets = @(
                        [pscustomobject]@{
                            name                 = 'D2Coding-Ver1.4.0-20261003.zip'
                            browser_download_url = 'https://example.invalid/D2Coding-Ver1.4.0-20261003.zip'
                        }
                    )
                }
            }
            Mock Invoke-FileDownload {
                Copy-Item -LiteralPath $fakeZipPath -Destination $OutFile -Force
            }
            Mock Copy-FontFile {}
            Mock Set-D2CodingFontRegistry {}

            $res = Invoke-Main -Check:$false
            $res | Should -Be '실패: D2Coding all.ttc 가 없다'

            Should -Invoke Copy-FontFile -Times 0
            Should -Invoke Set-D2CodingFontRegistry -Times 0
        }
    }
}
