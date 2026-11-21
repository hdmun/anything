Describe 'rdp-notify/install.ps1' {
    BeforeAll {
        $script:rdpDir = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' 'rdp-notify')).Path
        $script:installScript = Join-Path $script:rdpDir 'install.ps1'
        $script:expectedEnvPath = Join-Path $script:rdpDir 'rdp-notify.env'
        . $script:installScript
    }

    It 'install.ps1 파일이 UTF-8 BOM(EF BB BF)으로 시작한다' {
        $bytes = [System.IO.File]::ReadAllBytes($script:installScript)
        $bytes.Length | Should -BeGreaterThan 3
        $bytes[0] | Should -Be 0xEF
        $bytes[1] | Should -Be 0xBB
        $bytes[2] | Should -Be 0xBF
    }

    It 'Get-ExpectedArguments 가 register.ps1 -PrintXml 출력에서 rdp-notify.ps1 전체 경로가 든 인수를 꺼낸다' {
        $argsText = Get-ExpectedArguments
        $expectedScript = Join-Path $script:rdpDir 'rdp-notify.ps1'
        $argsText | Should -Match ([regex]::Escape($expectedScript))
        $argsText | Should -Match '-RecordId \$\(RecordId\)'
    }

    Context '표 1: 관리자 아님' {
        BeforeEach {
            Mock Test-Admin { $false }
            Mock Invoke-Register { 0 }
        }

        It '-Check -> 확인 못 함: 관리자 필요 (Invoke-Register 0회)' {
            $res = Invoke-Main -Check:$true
            $res | Should -Be '확인 못 함: 관리자 필요'
            Should -Invoke Invoke-Register -Times 0
        }

        It '고치는 실행 -> 실패: 관리자 필요 (Invoke-Register 0회)' {
            $res = Invoke-Main -Check:$false
            $res | Should -Be '실패: 관리자 필요'
            Should -Invoke Invoke-Register -Times 0
        }
    }

    Context '표 2: 작업이 선언과 같다, env 파일 있음' {
        BeforeEach {
            Mock Test-Admin { $true }
            Mock Get-ExpectedArguments { '-NoProfile -File "C:\repo\rdp-notify\rdp-notify.ps1" -RecordId $(RecordId)' }
            Mock Get-RdpNotifyTask {
                [pscustomobject]@{
                    State   = 'Ready'
                    Actions = @([pscustomobject]@{ Arguments = '-NoProfile -File "C:\repo\rdp-notify\rdp-notify.ps1" -RecordId $(RecordId)' })
                }
            }
            Mock Test-EnvFile { $true }
            Mock Invoke-Register { 0 }
        }

        It '-Check -> 그대로 (Invoke-Register 0회)' {
            $res = Invoke-Main -Check:$true
            $res | Should -Be '그대로'
            Should -Invoke Invoke-Register -Times 0
        }

        It '고치는 실행 -> 그대로 (Invoke-Register 0회)' {
            $res = Invoke-Main -Check:$false
            $res | Should -Be '그대로'
            Should -Invoke Invoke-Register -Times 0
        }
    }

    Context '표 3·7: 작업 없음' {
        BeforeEach {
            Mock Test-Admin { $true }
            Mock Get-ExpectedArguments { '-NoProfile -File "C:\repo\rdp-notify\rdp-notify.ps1" -RecordId $(RecordId)' }
            Mock Get-RdpNotifyTask { $null }
            Mock Test-EnvFile { $true }
            Mock Invoke-Register { 0 }
        }

        It '-Check -> 다름 (작업 없음) (Invoke-Register 0회)' {
            $res = Invoke-Main -Check:$true
            $res | Should -Be '다름 (작업 없음)'
            Should -Invoke Invoke-Register -Times 0
        }

        It '고치는 실행, env 있음 -> 바꿈 (Invoke-Register 정확히 1회)' {
            $res = Invoke-Main -Check:$false
            $res | Should -Be '바꿈'
            Should -Invoke Invoke-Register -Times 1
        }
    }

    Context '표 4·7: 인수 다름(저장소 옮김)' {
        BeforeEach {
            Mock Test-Admin { $true }
            Mock Get-ExpectedArguments { '-NoProfile -File "C:\new-repo\rdp-notify\rdp-notify.ps1" -RecordId $(RecordId)' }
            Mock Get-RdpNotifyTask {
                [pscustomobject]@{
                    State   = 'Ready'
                    Actions = @([pscustomobject]@{ Arguments = '-NoProfile -File "C:\old-repo\rdp-notify\rdp-notify.ps1" -RecordId $(RecordId)' })
                }
            }
            Mock Test-EnvFile { $true }
            Mock Invoke-Register { 0 }
        }

        It '-Check -> 다름 (작업 경로 다름) (Invoke-Register 0회)' {
            $res = Invoke-Main -Check:$true
            $res | Should -Be '다름 (작업 경로 다름)'
            Should -Invoke Invoke-Register -Times 0
        }

        It '고치는 실행, env 있음 -> 바꿈 (Invoke-Register 1회)' {
            $res = Invoke-Main -Check:$false
            $res | Should -Be '바꿈'
            Should -Invoke Invoke-Register -Times 1
        }
    }

    Context '표 5·7: 작업이 꺼짐(Disabled)' {
        BeforeEach {
            Mock Test-Admin { $true }
            Mock Get-ExpectedArguments { '-NoProfile -File "C:\repo\rdp-notify\rdp-notify.ps1" -RecordId $(RecordId)' }
            Mock Get-RdpNotifyTask {
                [pscustomobject]@{
                    State   = 'Disabled'
                    Actions = @([pscustomobject]@{ Arguments = '-NoProfile -File "C:\repo\rdp-notify\rdp-notify.ps1" -RecordId $(RecordId)' })
                }
            }
            Mock Test-EnvFile { $true }
            Mock Invoke-Register { 0 }
        }

        It '-Check -> 다름 (작업 꺼짐) (Invoke-Register 0회)' {
            $res = Invoke-Main -Check:$true
            $res | Should -Be '다름 (작업 꺼짐)'
            Should -Invoke Invoke-Register -Times 0
        }

        It '고치는 실행, env 있음 -> 바꿈 (Invoke-Register 1회)' {
            $res = Invoke-Main -Check:$false
            $res | Should -Be '바꿈'
            Should -Invoke Invoke-Register -Times 1
        }
    }

    Context '표 6: Invoke-Register 가 0 이 아님' {
        BeforeEach {
            Mock Test-Admin { $true }
            Mock Get-ExpectedArguments { '-NoProfile -File "C:\repo\rdp-notify\rdp-notify.ps1" -RecordId $(RecordId)' }
            Mock Get-RdpNotifyTask { $null }
            Mock Test-EnvFile { $false }
            Mock Invoke-Register { 1 }
        }

        It '고치는 실행 -> 실패: register.ps1 종료 코드 1 (env 없어도 6이 우선)' {
            $res = Invoke-Main -Check:$false
            $res | Should -Be '실패: register.ps1 종료 코드 1'
            Should -Invoke Invoke-Register -Times 1
        }
    }

    Context '표 8: env 파일 없음' {
        BeforeEach {
            Mock Test-Admin { $true }
            Mock Get-ExpectedArguments { '-NoProfile -File "C:\repo\rdp-notify\rdp-notify.ps1" -RecordId $(RecordId)' }
            Mock Test-EnvFile { $false }
            Mock Invoke-Register { 0 }
        }

        It '작업 같음 + -Check -> 할 일 (Invoke-Register 0회)' {
            Mock Get-RdpNotifyTask {
                [pscustomobject]@{
                    State   = 'Ready'
                    Actions = @([pscustomobject]@{ Arguments = '-NoProfile -File "C:\repo\rdp-notify\rdp-notify.ps1" -RecordId $(RecordId)' })
                }
            }

            $res = Invoke-Main -Check:$true
            $res | Should -Be "할 일: $($script:expectedEnvPath) 만들기 (rdp-notify/README.md 설치 1~2번)"
            Should -Invoke Invoke-Register -Times 0
        }

        It '작업 없음 + -Check -> 할 일 (8이 3보다 우선, Invoke-Register 0회)' {
            Mock Get-RdpNotifyTask { $null }

            $res = Invoke-Main -Check:$true
            $res | Should -Be "할 일: $($script:expectedEnvPath) 만들기 (rdp-notify/README.md 설치 1~2번)"
            Should -Invoke Invoke-Register -Times 0
        }

        It '작업 없음 + 고치는 실행 -> 등록 후 할 일 (Invoke-Register 1회)' {
            Mock Get-RdpNotifyTask { $null }

            $res = Invoke-Main -Check:$false
            $res | Should -Be "할 일: $($script:expectedEnvPath) 만들기 (rdp-notify/README.md 설치 1~2번)"
            Should -Invoke Invoke-Register -Times 1
        }

        It '작업 같음 + 고치는 실행(두 번째 실행 멱등) -> 할 일 (Invoke-Register 0회)' {
            Mock Get-RdpNotifyTask {
                [pscustomobject]@{
                    State   = 'Ready'
                    Actions = @([pscustomobject]@{ Arguments = '-NoProfile -File "C:\repo\rdp-notify\rdp-notify.ps1" -RecordId $(RecordId)' })
                }
            }

            $res = Invoke-Main -Check:$false
            $res | Should -Be "할 일: $($script:expectedEnvPath) 만들기 (rdp-notify/README.md 설치 1~2번)"
            Should -Invoke Invoke-Register -Times 0
        }
    }
}

Describe 'rdp-notify/install.ps1 출력 인코딩' {
    BeforeAll {
        $script:installScript = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' 'rdp-notify' 'install.ps1')).Path

        function Invoke-ChildRaw {
            # 자식 pwsh -File 을 띄워 표준 출력 바이트를 디코딩하지 않고 그대로 받는다 → @{ Bytes; ExitCode }
            # 부모 콘솔 출력 인코딩을 잠깐 CP949 로 두어, 스크립트가 스스로 UTF-8 로 맞추는지 확인한다.
            param([string[]]$Arguments)
            $saved = [Console]::OutputEncoding
            try {
                [Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding(949)
                $psi = [System.Diagnostics.ProcessStartInfo]::new('pwsh')
                foreach ($a in @('-NoProfile', '-File', $script:installScript) + $Arguments) {
                    $psi.ArgumentList.Add($a)
                }
                $psi.RedirectStandardOutput = $true
                $psi.UseShellExecute = $false
                $proc = [System.Diagnostics.Process]::Start($psi)
                $ms = [System.IO.MemoryStream]::new()
                $proc.StandardOutput.BaseStream.CopyTo($ms)
                $proc.WaitForExit()
                return @{ Bytes = $ms.ToArray(); ExitCode = $proc.ExitCode }
            } finally {
                [Console]::OutputEncoding = $saved
            }
        }
    }

    It '-Check 를 자식 pwsh -File 로 실행 -> 콘솔 코드 페이지와 상관없이 BOM 없는 UTF-8 한 줄이다' {
        # -Check 는 읽기만 한다. 관리자 여부에 따라 줄이 달라지므로 결과 말의 형식만 본다.
        $r = Invoke-ChildRaw -Arguments @('-Check')
        $r.ExitCode | Should -Be 0
        $r.Bytes.Length | Should -BeGreaterThan 3
        ($r.Bytes[0] -eq 0xEF -and $r.Bytes[1] -eq 0xBB -and $r.Bytes[2] -eq 0xBF) | Should -BeFalse
        $text = [System.Text.UTF8Encoding]::new($false, $true).GetString($r.Bytes)
        $text | Should -Match '\A(그대로|다름 \(.+\)|할 일: .+|확인 못 함: .+|실패: .+)\r\n\z'
    }

    It '같은 프로세스에서 실행한 뒤 [Console]::OutputEncoding 이 원래 값으로 돌아온다' {
        $saved = [Console]::OutputEncoding
        try {
            [Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding(949)
            & $script:installScript -Check | Out-Null
            [Console]::OutputEncoding.CodePage | Should -Be 949
        } finally {
            [Console]::OutputEncoding = $saved
        }
    }
}
