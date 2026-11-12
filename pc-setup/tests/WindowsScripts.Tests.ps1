Describe 'WindowsScripts' {
    Describe 'RemoteDesktop' {
        BeforeAll {
            $rdScript = Join-Path $PSScriptRoot '..' 'windows' 'RemoteDesktop.ps1'
            . $rdScript
        }

        It '모두 맞음 -> 그대로' {
            Mock Get-RemoteDesktopRegistry { @{ fDenyTSConnections = 0; UserAuthentication = 1 } }
            Mock Get-RemoteDesktopFirewallRules { @([pscustomobject]@{ Enabled = $true }, [pscustomobject]@{ Enabled = 'True' }) }

            $resCheck = Invoke-Main -Check:$true
            $resCheck | Should -Be '그대로'

            $resFix = Invoke-Main -Check:$false
            $resFix | Should -Be '그대로'
        }

        It 'fDenyTSConnections 1, -Check -> 다름 (...), 쓰기 함수 안 불림' {
            Mock Get-RemoteDesktopRegistry { @{ fDenyTSConnections = 1; UserAuthentication = 1 } }
            Mock Get-RemoteDesktopFirewallRules { @([pscustomobject]@{ Enabled = $true }) }
            Mock Set-RemoteDesktopRegistry
            Mock Enable-RemoteDesktopFirewallRules

            $res = Invoke-Main -Check:$true
            $res | Should -Be '다름 (fDenyTSConnections 1)'

            Should -Invoke Set-RemoteDesktopRegistry -Times 0
            Should -Invoke Enable-RemoteDesktopFirewallRules -Times 0
        }

        It '규칙 2개 꺼짐, 고치는 실행 -> 방화벽 켜기 1번, 바꿈' {
            Mock Get-RemoteDesktopRegistry { @{ fDenyTSConnections = 0; UserAuthentication = 1 } }
            Mock Get-RemoteDesktopFirewallRules {
                @(
                    [pscustomobject]@{ Enabled = $true }
                    [pscustomobject]@{ Enabled = $false }
                    [pscustomobject]@{ Enabled = $false }
                )
            }
            Mock Set-RemoteDesktopRegistry
            Mock Enable-RemoteDesktopFirewallRules

            $res = Invoke-Main -Check:$false
            $res | Should -Be '바꿈'

            Should -Invoke Enable-RemoteDesktopFirewallRules -Times 1
            Should -Invoke Set-RemoteDesktopRegistry -Times 0
        }

        It '규칙 없음 -> 실패' {
            Mock Get-RemoteDesktopRegistry { @{ fDenyTSConnections = 0; UserAuthentication = 1 } }
            Mock Get-RemoteDesktopFirewallRules { @() }

            $res = Invoke-Main -Check:$false
            $res | Should -Be '실패: 원격 데스크톱 방화벽 규칙이 없다'

            $resCheck = Invoke-Main -Check:$true
            $resCheck | Should -Be '실패: 원격 데스크톱 방화벽 규칙이 없다'
        }

        It '읽기 권한 오류, -Check -> 확인 못 함: 관리자 필요' {
            Mock Get-RemoteDesktopRegistry { throw [System.UnauthorizedAccessException]::new('액세스가 거부되었습니다') }
            Mock Get-RemoteDesktopFirewallRules { @([pscustomobject]@{ Enabled = $true }) }

            $resCheck = Invoke-Main -Check:$true
            $resCheck | Should -Be '확인 못 함: 관리자 필요'

            $resFix = Invoke-Main -Check:$false
            $resFix | Should -Be '실패: 관리자 필요'
        }
    }

    Describe 'Hibernate' {
        BeforeAll {
            $hibScript = Join-Path $PSScriptRoot '..' 'windows' 'Hibernate.ps1'
            . $hibScript
        }

        It '0 / 값 없음 -> 그대로' {
            Mock Get-HibernateEnabled { return 0 }
            $res0 = Invoke-Main -Check:$false
            $res0 | Should -Be '그대로'

            Mock Get-HibernateEnabled { return $null }
            $resNull = Invoke-Main -Check:$true
            $resNull | Should -Be '그대로'
        }

        It '1, -Check -> 다름 (HibernateEnabled 1)' {
            Mock Get-HibernateEnabled { return 1 }
            Mock Invoke-Powercfg

            $res = Invoke-Main -Check:$true
            $res | Should -Be '다름 (HibernateEnabled 1)'

            Should -Invoke Invoke-Powercfg -Times 0
        }

        It '1, 고치는 실행, powercfg 성공 후 0 -> 바꿈' {
            $script:hibCallCount = 0
            Mock Get-HibernateEnabled {
                $script:hibCallCount++
                if ($script:hibCallCount -eq 1) { return 1 }
                return 0
            }
            Mock Invoke-Powercfg { return 0 }

            $res = Invoke-Main -Check:$false
            $res | Should -Be '바꿈'

            Should -Invoke Invoke-Powercfg -Times 1 -ParameterFilter {
                $Arguments -contains '/h' -and $Arguments -contains 'off'
            }
        }

        It 'powercfg 종료 코드 1 -> 실패' {
            Mock Get-HibernateEnabled { return 1 }
            Mock Invoke-Powercfg { return 1 }

            $res = Invoke-Main -Check:$false
            $res | Should -Be '실패: powercfg /h off 종료 코드 1'
        }
    }

    Describe 'Power' {
        BeforeAll {
            $powerScript = Join-Path $PSScriptRoot '..' 'windows' 'Power.ps1'
            . $powerScript

            $script:sampleKoSleep = @"
전원 구성표 GUID: 9935e61f-1661-40c5-ae2f-8495027d5d5d  (AMD Ryzen™ High Performance)
  하위 그룹 GUID: 238c9fa8-0aad-41ed-83f4-97be242c8f20  (절전)
    GUID 별칭: SUB_SLEEP
    전원 설정 GUID: 29f6c1db-86da-48c5-9fdb-f2b67b1f44da  (다음 시간 후 절전 모드로 전환)
      GUID 별칭: STANDBYIDLE
      가능한 최소 설정: 0x00000000
      가능한 최대 설정: 0xffffffff
      가능한 설정 증가: 0x00000001
      가능한 설정 단위: 초
    현재 AC 전원 설정 색인: 0x00000000
    현재 DC 전원 설정 색인: 0x00000000
"@

            $script:sampleKoVideo = @"
전원 구성표 GUID: 9935e61f-1661-40c5-ae2f-8495027d5d5d  (AMD Ryzen™ High Performance)
  하위 그룹 GUID: 7516b95f-f776-4464-8c53-06167f40cc99  (디스플레이)
    GUID 별칭: SUB_VIDEO
    전원 설정 GUID: 3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e  (다음 시간 이후에 끄기)
      GUID 별칭: VIDEOIDLE
      가능한 최소 설정: 0x00000000
      가능한 최대 설정: 0xffffffff
      가능한 설정 증가: 0x00000001
      가능한 설정 단위: 초
    현재 AC 전원 설정 색인: 0x00000384
    현재 DC 전원 설정 색인: 0x00000258
"@

            $script:sampleEnSleep = @"
Power Scheme GUID: 9935e61f-1661-40c5-ae2f-8495027d5d5d  (AMD Ryzen™ High Performance)
  Subgroup GUID: 238c9fa8-0aad-41ed-83f4-97be242c8f20  (Sleep)
    GUID Alias: SUB_SLEEP
    Power Setting GUID: 29f6c1db-86da-48c5-9fdb-f2b67b1f44da  (Sleep after)
      GUID Alias: STANDBYIDLE
      Minimum Possible Setting: 0x00000000
      Maximum Possible Setting: 0xffffffff
      Possible Setting Increment: 0x00000001
      Possible Settings units: Seconds
    Current AC Power Setting Index: 0x00000000
    Current DC Power Setting Index: 0x00000000
"@

            $script:sampleEnVideo = @"
Power Scheme GUID: 9935e61f-1661-40c5-ae2f-8495027d5d5d  (AMD Ryzen™ High Performance)
  Subgroup GUID: 7516b95f-f776-4464-8c53-06167f40cc99  (Display)
    GUID Alias: SUB_VIDEO
    Power Setting GUID: 3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e  (Turn off display after)
      GUID Alias: VIDEOIDLE
      Minimum Possible Setting: 0x00000000
      Maximum Possible Setting: 0xffffffff
      Possible Setting Increment: 0x00000001
      Possible Settings units: Seconds
    Current AC Power Setting Index: 0x00000384
    Current DC Power Setting Index: 0x00000258
"@
        }

        It 'AC 0x0·0x384 -> 그대로' {
            Mock Invoke-PowercfgQuery {
                if ($SubGroup -eq 'SUB_SLEEP') { return $script:sampleKoSleep }
                if ($SubGroup -eq 'SUB_VIDEO') { return $script:sampleKoVideo }
                throw "Unexpected subgroup: $SubGroup"
            }

            $resCheck = Invoke-Main -Check:$true
            $resCheck | Should -Be '그대로'

            $resFix = Invoke-Main -Check:$false
            $resFix | Should -Be '그대로'
        }

        It '영어 출력과 한국어 출력 견본 각각에서 AC 값을 읽음 -> 같은 값' {
            $koSleepVal = Get-AcValue -Output $script:sampleKoSleep
            $enSleepVal = Get-AcValue -Output $script:sampleEnSleep
            $koSleepVal | Should -Be $enSleepVal
            $koSleepVal | Should -Be 0

            $koVideoVal = Get-AcValue -Output $script:sampleKoVideo
            $enVideoVal = Get-AcValue -Output $script:sampleEnVideo
            $koVideoVal | Should -Be $enVideoVal
            $koVideoVal | Should -Be 900
        }

        It '모니터 0x258(10분), -Check -> 다름 (절전 안 함, 모니터 10분)' {
            $video10Min = $script:sampleKoVideo -replace '현재 AC 전원 설정 색인: 0x00000384', '현재 AC 전원 설정 색인: 0x00000258'
            Mock Invoke-PowercfgQuery {
                if ($SubGroup -eq 'SUB_SLEEP') { return $script:sampleKoSleep }
                if ($SubGroup -eq 'SUB_VIDEO') { return $video10Min }
                throw "Unexpected subgroup: $SubGroup"
            }
            Mock Invoke-PowercfgChange

            $res = Invoke-Main -Check:$true
            $res | Should -Be '다름 (절전 안 함, 모니터 10분)'

            Should -Invoke Invoke-PowercfgChange -Times 0
        }

        It '절전만 다름, 고치는 실행 -> standby 명령만 불림, 바꿈' {
            $sleep10Min = $script:sampleKoSleep -replace '현재 AC 전원 설정 색인: 0x00000000', '현재 AC 전원 설정 색인: 0x00000258'
            Mock Invoke-PowercfgQuery {
                if ($SubGroup -eq 'SUB_SLEEP') { return $sleep10Min }
                if ($SubGroup -eq 'SUB_VIDEO') { return $script:sampleKoVideo }
                throw "Unexpected subgroup: $SubGroup"
            }
            Mock Invoke-PowercfgChange { return 0 }

            $res = Invoke-Main -Check:$false
            $res | Should -Be '바꿈'

            Should -Invoke Invoke-PowercfgChange -Times 1 -ParameterFilter {
                $Command -eq 'powercfg /change standby-timeout-ac 0'
            }
            Should -Invoke Invoke-PowercfgChange -Times 0 -ParameterFilter {
                $Command -like '*monitor*'
            }
        }

        It '읽기 권한 오류, -Check -> 확인 못 함: 관리자 필요' {
            Mock Invoke-PowercfgQuery {
                throw "powercfg /query SCHEME_CURRENT SUB_SLEEP STANDBYIDLE 실패 (종료 코드 1): Access is denied"
            }

            $resCheck = Invoke-Main -Check:$true
            $resCheck | Should -Be '확인 못 함: 관리자 필요'

            $resFix = Invoke-Main -Check:$false
            $resFix | Should -Be '실패: 관리자 필요'
        }
    }
}
