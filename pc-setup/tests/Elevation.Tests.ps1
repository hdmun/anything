BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'lib' 'Elevation.psm1'
    Import-Module $modulePath -Force
}

Describe 'Elevation.psm1' {
    Context 'Test-AdminWindow' {
        It '현재 창의 관리자 권한 여부를 boolean 으로 돌려준다' {
            $isAdmin = Test-AdminWindow
            $isAdmin -is [bool] | Should -BeTrue
        }
    }

    Context 'Invoke-ElevatedPhase' {
        It '결과 JSON 을 쓰는 가짜 -> Results 와 Requested=1' {
            Mock -ModuleName Elevation Start-Process {
                $argStr = [string]($ArgumentList -join ' ')
                if ($argStr -match '-ResultPath "([^"]+)"') {
                    $jsonPath = $Matches[1]
                    $content = @{
                        Check             = $false
                        ElevationRequests = 1
                        DurationSeconds   = 1.2
                        Results           = @(
                            @{ Stage = 'Windows 설정'; Id = 'LongPaths'; Status = '그대로'; Detail = '' }
                        )
                    } | ConvertTo-Json -Depth 5
                    [System.IO.File]::WriteAllText($jsonPath, $content, [System.Text.Encoding]::UTF8)
                }
            }

            $res = Invoke-ElevatedPhase -SetupScript 'C:\test\setup.ps1'
            $res.Requested | Should -Be 1
            $res.Error | Should -Be ''
            $res.Results.Count | Should -Be 1
            $res.Results[0].Stage | Should -Be 'Windows 설정'
            $res.Results[0].Id | Should -Be 'LongPaths'
            $res.Results[0].Status | Should -Be '그대로'
            $res.Results[0].Detail | Should -Be ''
        }

        It '예외 -> 승격 거부됨' {
            Mock -ModuleName Elevation Start-Process {
                throw [System.ComponentModel.Win32Exception]::new('작업이 사용자에 의해 취소되었습니다.')
            }

            $res = Invoke-ElevatedPhase -SetupScript 'C:\test\setup.ps1'
            $res.Requested | Should -Be 1
            $res.Error | Should -Be '승격 거부됨'
            $res.Results.Count | Should -Be 0
        }

        It '파일을 안 씀 -> 승격 단계 결과 없음' {
            Mock -ModuleName Elevation Start-Process {
                # 파일을 생성하지 않음
            }

            $res = Invoke-ElevatedPhase -SetupScript 'C:\test\setup.ps1'
            $res.Requested | Should -Be 1
            $res.Error | Should -Be '승격 단계 결과 없음'
            $res.Results.Count | Should -Be 0
        }

        It '깨진 JSON -> 승격 단계 결과 없음' {
            Mock -ModuleName Elevation Start-Process {
                $argStr = [string]($ArgumentList -join ' ')
                if ($argStr -match '-ResultPath "([^"]+)"') {
                    $jsonPath = $Matches[1]
                    [System.IO.File]::WriteAllText($jsonPath, '{ not valid json', [System.Text.Encoding]::UTF8)
                }
            }

            $res = Invoke-ElevatedPhase -SetupScript 'C:\test\setup.ps1'
            $res.Requested | Should -Be 1
            $res.Error | Should -Be '승격 단계 결과 없음'
            $res.Results.Count | Should -Be 0
        }

        It '-Skip a,b 가 인자에 -Skip "a,b" 로 들어감' {
            $script:capturedArgs = $null
            Mock -ModuleName Elevation Start-Process {
                $script:capturedArgs = $ArgumentList
            }

            $null = Invoke-ElevatedPhase -SetupScript 'C:\test\setup.ps1' -Skip @('a', 'b')

            ($script:capturedArgs -join ' ') | Should -Match '-Skip "a,b"'
        }

        It '끝난 뒤 임시 파일이 지워짐' {
            $script:capturedTempPath = $null
            Mock -ModuleName Elevation Start-Process {
                $argStr = [string]($ArgumentList -join ' ')
                if ($argStr -match '-ResultPath "([^"]+)"') {
                    $script:capturedTempPath = $Matches[1]
                    $content = @{
                        Results = @()
                    } | ConvertTo-Json
                    [System.IO.File]::WriteAllText($script:capturedTempPath, $content, [System.Text.Encoding]::UTF8)
                }
            }

            $null = Invoke-ElevatedPhase -SetupScript 'C:\test\setup.ps1'
            $script:capturedTempPath | Should -Not -BeNullOrEmpty
            Test-Path -LiteralPath $script:capturedTempPath | Should -BeFalse
        }
    }
}
