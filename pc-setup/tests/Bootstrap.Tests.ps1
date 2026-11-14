BeforeAll {
    $script:BootstrapPath = (Resolve-Path (Join-Path $PSScriptRoot '..' 'bootstrap.ps1')).Path
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:BootstrapPath, [ref]$null, [ref]$parseErrors)
    if ($parseErrors -and $parseErrors.Count -gt 0) {
        throw "bootstrap.ps1 parse errors: $($parseErrors | Out-String)"
    }
    $funcAsts = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)
    foreach ($fn in $funcAsts) {
        . ([scriptblock]::Create($fn.Extent.Text))
    }
}

Describe 'bootstrap.ps1 5.1 호환 및 금지 항목 검사' {
    It 'Windows PowerShell 5.1 파서 오류가 0개다' {
        $ps51 = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $escaped = $script:BootstrapPath.Replace("'", "''")
        $cmd = "`$errs = `$null; [void][System.Management.Automation.Language.Parser]::ParseFile('$escaped', [ref]`$null, [ref]`$errs); Write-Output `$errs.Count"
        $out = & $ps51 -NoProfile -Command $cmd
        $LASTEXITCODE | Should -Be 0
        [int]($out | Select-Object -Last 1) | Should -Be 0
    }

    It 'UTF-8 BOM(EF BB BF)이 없고 모든 바이트가 0x7F 이하다' {
        $bytes = [System.IO.File]::ReadAllBytes($script:BootstrapPath)
        $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
        $hasBom | Should -BeFalse
        $nonAscii = @($bytes | Where-Object { $_ -gt 0x7F })
        $nonAscii.Count | Should -Be 0
    }

    It 'Repair-WinGetPackageManager, Install-Module, Set-ExecutionPolicy 가 없다' {
        $raw = [System.IO.File]::ReadAllText($script:BootstrapPath, [System.Text.Encoding]::ASCII)
        $raw | Should -Not -Match 'Repair-WinGetPackageManager'
        $raw | Should -Not -Match 'Install-Module'
        $raw | Should -Not -Match 'Set-ExecutionPolicy'
    }

    It 'irm | iex 와 [scriptblock]::Create((irm ...)) 경로의 파싱이 5.1 에서 성공한다' {
        $ps51 = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $escaped = $script:BootstrapPath.Replace("'", "''")
        $cmd = "`$text = [System.IO.File]::ReadAllText('$escaped', [System.Text.Encoding]::UTF8); `$sb = [scriptblock]::Create(`$text); Write-Output (`$null -ne `$sb)"
        $out = & $ps51 -NoProfile -Command $cmd
        $LASTEXITCODE | Should -Be 0
        ($out | Select-Object -Last 1) | Should -Be 'True'
    }
}

Describe 'Invoke-Bootstrap 엣지 케이스 표 1~20' {
    BeforeEach {
        $script:lines = [System.Collections.Generic.List[string]]::new()
        Mock Write-Host { $script:lines.Add([string]$Object) }
        Mock Write-Warning {}
        Mock Test-AdminWindow { return $false }
        Mock Get-AnythingRepo { return '' }
        $script:testCaseDir = Join-Path $TestDrive ([System.Guid]::NewGuid().ToString())
        New-Item -Path $script:testCaseDir -ItemType Directory -Force | Out-Null
        $script:defaultRepo = Join-Path $script:testCaseDir 'anything'
        Mock Get-DefaultRepoPath { return $script:defaultRepo }
        Mock Get-WingetVersion { return [version]'1.29.380' }
        Mock Register-WingetFamily { throw 'should not be called' }
        Mock Install-WingetFromGitHub { throw 'should not be called' }
        Mock Update-SessionPath {}
        Mock Invoke-Winget { param([string[]]$Arguments) return 0 }
        Mock Invoke-ElevatedInstall { throw 'should not be called' }
        Mock Invoke-Git { param([string[]]$Arguments) return 0 }
        Mock Start-SetupScript { param([string]$RepoPath, [string[]]$Skip, [string]$ResultPath) return 0 }
    }

    It '1: 관리자 창 -> 2, winget·git 함수 안 불림, 문구 일치' {
        Mock Test-AdminWindow { return $true }
        Mock Get-WingetVersion { throw 'should not be called' }
        Mock Invoke-Winget { throw 'should not be called' }
        Mock Invoke-Git { throw 'should not be called' }
        Mock Start-SetupScript { throw 'should not be called' }

        $ret = Invoke-Bootstrap
        $ret | Should -Be 2
        $script:lines | Should -Contain '부트스트랩은 일반 권한 창에서 실행한다'
    }

    It '2: winget 충분·Git·pwsh 있음·$HOME\anything 없음 -> 모두 그대로, clone 바꿈, 승격 0회, 셋업 종료 코드 반환' {
        Mock Start-SetupScript { return 0 }

        $ret = Invoke-Bootstrap
        $ret | Should -Be 0
        Should -Invoke Invoke-ElevatedInstall -Times 0 -Exactly
        Should -Invoke Invoke-Git -Times 1 -Exactly
        Should -Invoke Start-SetupScript -Times 1 -Exactly
        $script:lines | Should -Contain '[부트스트랩] winget: 그대로'
        $script:lines | Should -Contain '[부트스트랩] Git.Git: 그대로'
        $script:lines | Should -Contain '[부트스트랩] Microsoft.PowerShell: 그대로'
        $script:lines | Should -Contain '[부트스트랩] clone: 바꿈'
        $script:lines | Should -Contain '부트스트랩 승격 요청: 0회'
        ($script:lines | Where-Object { $_ -match '^부트스트랩 걸린 시간: \d{2}:\d{2}$' }).Count | Should -Be 1
    }

    It '3: winget 없음 -> Register-WingetFamily 후 충분 -> winget 바꿈, Install-WingetFromGitHub 안 불림' {
        $script:wingetChecks = 0
        Mock Get-WingetVersion {
            $script:wingetChecks++
            if ($script:wingetChecks -eq 1) { return $null }
            return [version]'1.29.380'
        }
        Mock Register-WingetFamily {}
        Mock Install-WingetFromGitHub { throw 'should not be called' }

        $ret = Invoke-Bootstrap
        $ret | Should -Be 0
        Should -Invoke Register-WingetFamily -Times 1 -Exactly
        Should -Invoke Install-WingetFromGitHub -Times 0 -Exactly
        $script:lines | Should -Contain '[부트스트랩] winget: 바꿈'
    }

    It '4: 등록도 실패 -> GitHub 설치 후 충분 -> winget 바꿈' {
        $script:githubInstalled = $false
        Mock Get-WingetVersion {
            if ($script:githubInstalled) { return [version]'1.29.380' }
            return $null
        }
        Mock Register-WingetFamily { throw 'not registered' }
        Mock Install-WingetFromGitHub { $script:githubInstalled = $true }

        $ret = Invoke-Bootstrap
        $ret | Should -Be 0
        Should -Invoke Register-WingetFamily -Times 1 -Exactly
        Should -Invoke Install-WingetFromGitHub -Times 1 -Exactly
        $script:lines | Should -Contain '[부트스트랩] winget: 바꿈'
    }

    It '5: GitHub 설치도 실패 -> winget 실패, 1, 이후 단계 안 불림' {
        Mock Get-WingetVersion { return $null }
        Mock Register-WingetFamily { throw 'register failed' }
        Mock Install-WingetFromGitHub { throw 'github download failed' }
        Mock Invoke-Winget { throw 'should not be called' }
        Mock Invoke-ElevatedInstall { throw 'should not be called' }
        Mock Invoke-Git { throw 'should not be called' }
        Mock Start-SetupScript { throw 'should not be called' }

        $ret = Invoke-Bootstrap
        $ret | Should -Be 1
        $script:lines | Should -Contain '[부트스트랩] winget: 실패: github download failed'
    }

    It '6: Git 없음·pwsh 있음 -> Invoke-ElevatedInstall -Ids Git.Git 1번, 승격 1회' {
        Mock Invoke-Winget {
            param([string[]]$Arguments)
            $idx = [Array]::IndexOf($Arguments, '--id')
            if ($idx -ge 0 -and $Arguments[$idx + 1] -eq 'Git.Git') { return 1 }
            return 0
        }
        $script:capturedIds = $null
        Mock Invoke-ElevatedInstall {
            param([string[]]$Ids)
            $script:capturedIds = $Ids
            return @{ Requested = 1; Codes = @{ 'Git.Git' = 0 }; Error = '' }
        }

        $ret = Invoke-Bootstrap
        $ret | Should -Be 0
        Should -Invoke Invoke-ElevatedInstall -Times 1 -Exactly
        $script:capturedIds.Count | Should -Be 1
        $script:capturedIds[0] | Should -Be 'Git.Git'
        $script:lines | Should -Contain '[부트스트랩] Git.Git: 바꿈'
        $script:lines | Should -Contain '[부트스트랩] Microsoft.PowerShell: 그대로'
        $script:lines | Should -Contain '부트스트랩 승격 요청: 1회'
    }

    It '7: 둘 다 없음 -> -Ids Git.Git,Microsoft.PowerShell 로 1번' {
        Mock Invoke-Winget { return 1 }
        $script:capturedIds = $null
        Mock Invoke-ElevatedInstall {
            param([string[]]$Ids)
            $script:capturedIds = $Ids
            return @{
                Requested = 1
                Codes     = @{ 'Git.Git' = 0; 'Microsoft.PowerShell' = 0 }
                Error     = ''
            }
        }

        $ret = Invoke-Bootstrap
        $ret | Should -Be 0
        Should -Invoke Invoke-ElevatedInstall -Times 1 -Exactly
        ($script:capturedIds -join ',') | Should -Be 'Git.Git,Microsoft.PowerShell'
        $script:lines | Should -Contain '[부트스트랩] Git.Git: 바꿈'
        $script:lines | Should -Contain '[부트스트랩] Microsoft.PowerShell: 바꿈'
        $script:lines | Should -Contain '부트스트랩 승격 요청: 1회'
    }

    It '8: 설치 종료 코드 0x8A150109 -> 할 일: 재부팅 후 부트스트랩 다시 실행, 셋업 안 불림, 0' {
        Mock Invoke-Winget { return 1 }
        Mock Invoke-ElevatedInstall {
            return @{
                Requested = 1
                Codes     = @{ 'Git.Git' = [int]0x8A150109; 'Microsoft.PowerShell' = 0 }
                Error     = ''
            }
        }
        Mock Invoke-Git { throw 'should not be called' }
        Mock Start-SetupScript { throw 'should not be called' }

        $ret = Invoke-Bootstrap
        $ret | Should -Be 0
        $script:lines | Should -Contain '[부트스트랩] Git.Git: 할 일: 재부팅 후 부트스트랩 다시 실행'
        $script:lines | Should -Contain '[부트스트랩] Microsoft.PowerShell: 바꿈'
    }

    It '9: 설치 종료 코드 그 밖 -> 실패: winget 종료 코드 0x..., 셋업 안 불림, 1' {
        Mock Invoke-Winget { return 1 }
        Mock Invoke-ElevatedInstall {
            return @{
                Requested = 1
                Codes     = @{ 'Git.Git' = 5; 'Microsoft.PowerShell' = 0 }
                Error     = ''
            }
        }
        Mock Invoke-Git { throw 'should not be called' }
        Mock Start-SetupScript { throw 'should not be called' }

        $ret = Invoke-Bootstrap
        $ret | Should -Be 1
        $script:lines | Should -Contain '[부트스트랩] Git.Git: 실패: winget 종료 코드 0x00000005'
    }

    It '10: Error = 승격 거부됨 -> 없던 Id 가 실패: 승격 거부됨, 1' {
        Mock Invoke-Winget {
            param([string[]]$Arguments)
            $idx = [Array]::IndexOf($Arguments, '--id')
            if ($idx -ge 0 -and $Arguments[$idx + 1] -eq 'Git.Git') { return 1 }
            return 0
        }
        Mock Invoke-ElevatedInstall {
            return @{ Requested = 1; Codes = @{}; Error = '승격 거부됨' }
        }
        Mock Invoke-Git { throw 'should not be called' }
        Mock Start-SetupScript { throw 'should not be called' }

        $ret = Invoke-Bootstrap
        $ret | Should -Be 1
        $script:lines | Should -Contain '[부트스트랩] Git.Git: 실패: 승격 거부됨'
        $script:lines | Should -Contain '[부트스트랩] Microsoft.PowerShell: 그대로'
    }

    It '11: ANYTHING_REPO 가 있고 pc-setup\setup.ps1 있음 -> Invoke-Git 안 불림, clone 그대로, 셋업이 그 폴더로 불림' {
        $existingRepo = Join-Path $TestDrive 'custom-repo'
        New-Item -Path (Join-Path $existingRepo 'pc-setup') -ItemType Directory -Force | Out-Null
        Set-Content -Path (Join-Path $existingRepo 'pc-setup\setup.ps1') -Value '# dummy'
        Mock Get-AnythingRepo { return $existingRepo }
        Mock Invoke-Git { throw 'should not be called' }

        $script:setupRepo = $null
        Mock Start-SetupScript {
            param([string]$RepoPath)
            $script:setupRepo = $RepoPath
            return 0
        }

        $ret = Invoke-Bootstrap
        $ret | Should -Be 0
        $script:setupRepo | Should -Be $existingRepo
        $script:lines | Should -Contain '[부트스트랩] clone: 그대로'
    }

    It '12: ANYTHING_REPO 가 있지만 폴더 없음 -> $HOME\anything(Get-DefaultRepoPath) 로 clone' {
        $missingEnvRepo = Join-Path $TestDrive 'missing-env-repo'
        Mock Get-AnythingRepo { return $missingEnvRepo }
        $script:gitArgs = $null
        Mock Invoke-Git {
            param([string[]]$Arguments)
            $script:gitArgs = $Arguments
            return 0
        }

        $ret = Invoke-Bootstrap
        $ret | Should -Be 0
        Should -Invoke Invoke-Git -Times 1 -Exactly
        $script:gitArgs[-1] | Should -Be $script:defaultRepo
    }

    It '13: $HOME\anything 이 이미 있고 셋업 있음 -> clone 그대로, Invoke-Git 안 불림' {
        New-Item -Path (Join-Path $script:defaultRepo 'pc-setup') -ItemType Directory -Force | Out-Null
        Set-Content -Path (Join-Path $script:defaultRepo 'pc-setup\setup.ps1') -Value '# dummy'
        Mock Invoke-Git { throw 'should not be called' }

        $ret = Invoke-Bootstrap
        $ret | Should -Be 0
        $script:lines | Should -Contain '[부트스트랩] clone: 그대로'
    }

    It '14: $HOME\anything 이 이미 있고 셋업 없음 -> clone 실패, 1' {
        New-Item -Path $script:defaultRepo -ItemType Directory -Force | Out-Null
        Mock Invoke-Git { throw 'should not be called' }
        Mock Start-SetupScript { throw 'should not be called' }

        $ret = Invoke-Bootstrap
        $ret | Should -Be 1
        $script:lines | Should -Contain "[부트스트랩] clone: 실패: $script:defaultRepo 에 셋업이 없다"
    }

    It '15: -Branch feat -Source C:\x.bundle -> Invoke-Git clone -b feat C:\x.bundle <폴더>' {
        $script:gitArgs = $null
        Mock Invoke-Git {
            param([string[]]$Arguments)
            $script:gitArgs = $Arguments
            return 0
        }

        $ret = Invoke-Bootstrap -Source 'C:\x.bundle' -Branch 'feat'
        $ret | Should -Be 0
        ($script:gitArgs -join '|') | Should -Be "clone|-b|feat|C:\x.bundle|$script:defaultRepo"
    }

    It '16: -Branch 빈 값 -> -b 없이 clone' {
        $script:gitArgs = $null
        Mock Invoke-Git {
            param([string[]]$Arguments)
            $script:gitArgs = $Arguments
            return 0
        }

        $ret = Invoke-Bootstrap -Source 'https://example.com/repo.git' -Branch ''
        $ret | Should -Be 0
        ($script:gitArgs -join '|') | Should -Be "clone|https://example.com/repo.git|$script:defaultRepo"
    }

    It '17: git clone 종료 코드 128 -> clone 실패, 1' {
        Mock Invoke-Git { return 128 }
        Mock Start-SetupScript { throw 'should not be called' }

        $ret = Invoke-Bootstrap
        $ret | Should -Be 1
        $script:lines | Should -Contain '[부트스트랩] clone: 실패: git clone 종료 코드 128'
    }

    It '18: -Skip a,b -SetupResultPath C:\o\s.json -> Start-SetupScript 가 그 값으로 불림' {
        $script:capturedSkip = $null
        $script:capturedSetupResult = $null
        Mock Start-SetupScript {
            param([string]$RepoPath, [string[]]$Skip, [string]$ResultPath)
            $script:capturedSkip = $Skip
            $script:capturedSetupResult = $ResultPath
            return 0
        }

        $ret = Invoke-Bootstrap -Skip @('a', 'b') -SetupResultPath 'C:\o\s.json'
        $ret | Should -Be 0
        ($script:capturedSkip -join ',') | Should -Be 'a,b'
        $script:capturedSetupResult | Should -Be 'C:\o\s.json'
    }

    It '19: 셋업 종료 코드 1 -> Invoke-Bootstrap 이 1' {
        Mock Start-SetupScript { return 1 }

        $ret = Invoke-Bootstrap
        $ret | Should -Be 1
    }

    It '20: -ResultPath 있음 -> JSON 에 Results(Stage 부트스트랩)·ElevationRequests·DurationSeconds·Check=false, 4·5 단계 멈춤에도 씀' {
        $jsonOut1 = Join-Path $TestDrive 'res-normal.json'
        $ret1 = Invoke-Bootstrap -ResultPath $jsonOut1
        $ret1 | Should -Be 0
        Test-Path -LiteralPath $jsonOut1 | Should -BeTrue
        $data1 = Get-Content -LiteralPath $jsonOut1 -Raw -Encoding UTF8 | ConvertFrom-Json
        $data1.Check | Should -BeFalse
        $data1.ElevationRequests | Should -Be 0
        $data1.DurationSeconds | Should -BeGreaterOrEqual 0
        $data1.Results.Count | Should -Be 4
        @($data1.Results | Where-Object { $_.Stage -eq '부트스트랩' }).Count | Should -Be 4

        # Step 4 stop
        Mock Invoke-Winget { return 1 }
        Mock Invoke-ElevatedInstall {
            return @{ Requested = 1; Codes = @{}; Error = '승격 거부됨' }
        }
        $jsonOut4 = Join-Path $TestDrive 'res-step4.json'
        $ret4 = Invoke-Bootstrap -ResultPath $jsonOut4
        $ret4 | Should -Be 1
        Test-Path -LiteralPath $jsonOut4 | Should -BeTrue
        $data4 = Get-Content -LiteralPath $jsonOut4 -Raw -Encoding UTF8 | ConvertFrom-Json
        $data4.ElevationRequests | Should -Be 1
        $data4.Results.Count | Should -Be 3
        $data4.Results[1].Status | Should -Be '실패'
        $data4.Results[1].Detail | Should -Be '승격 거부됨'

        # Step 5 stop
        Mock Invoke-Winget { return 0 }
        Mock Invoke-Git { return 128 }
        $jsonOut5 = Join-Path $TestDrive 'res-step5.json'
        $ret5 = Invoke-Bootstrap -ResultPath $jsonOut5
        $ret5 | Should -Be 1
        Test-Path -LiteralPath $jsonOut5 | Should -BeTrue
        $data5 = Get-Content -LiteralPath $jsonOut5 -Raw -Encoding UTF8 | ConvertFrom-Json
        $data5.Results.Count | Should -Be 4
        $data5.Results[3].Id | Should -Be 'clone'
        $data5.Results[3].Status | Should -Be '실패'
        $data5.Results[3].Detail | Should -Be 'git clone 종료 코드 128'
    }

    It '결과 JSON 쓰기 실패 -> 경고 출력, 종료 코드는 바꾸지 않음' {
        $badPath = Join-Path $TestDrive 'no-such-dir\nested\out.json'
        $script:warned = $false
        Mock Write-Warning { $script:warned = $true }

        $ret = Invoke-Bootstrap -ResultPath $badPath
        $ret | Should -Be 0
        $script:warned | Should -BeTrue
    }
}

Describe '하위 함수 단위 테스트 (실제 외부 명령 호출 없음)' {
    It 'Invoke-ElevatedInstall: RunAs + EncodedCommand 로 winget 설치를 실행하고 결과 JSON 을 읽어 정리한다' {
        $script:capturedArgs = $null
        $script:capturedTempPath = $null
        Mock Start-Process {
            param($FilePath, $Verb, $Wait, $ArgumentList)
            $FilePath | Should -Be 'powershell.exe'
            $Verb | Should -Be 'RunAs'
            $script:capturedArgs = $ArgumentList
            $b64 = $ArgumentList[-1]
            $decoded = [System.Text.Encoding]::Unicode.GetString([System.Convert]::FromBase64String($b64))
            $decoded | Should -Match 'winget install --id \$id -e --scope machine --no-upgrade --source winget --accept-package-agreements --accept-source-agreements --disable-interactivity'
            if ($decoded -match "WriteAllText\('([^']+)'") {
                $script:capturedTempPath = $Matches[1].Replace("''", "'")
                [System.IO.File]::WriteAllText($script:capturedTempPath, '{"Git.Git":0,"Microsoft.PowerShell":0}', [System.Text.Encoding]::UTF8)
            }
        }

        $res = Invoke-ElevatedInstall -Ids @('Git.Git', 'Microsoft.PowerShell')
        $res.Requested | Should -Be 1
        $res.Error | Should -Be ''
        $res.Codes['Git.Git'] | Should -Be 0
        $res.Codes['Microsoft.PowerShell'] | Should -Be 0
        $script:capturedTempPath | Should -Not -BeNullOrEmpty
        Test-Path -LiteralPath $script:capturedTempPath | Should -BeFalse
    }

    It 'Invoke-ElevatedInstall: Start-Process 예외 -> Error = 승격 거부됨' {
        Mock Start-Process { throw [System.ComponentModel.Win32Exception]::new('User canceled') }
        $res = Invoke-ElevatedInstall -Ids @('Git.Git')
        $res.Requested | Should -Be 1
        $res.Error | Should -Be '승격 거부됨'
        $res.Codes.Count | Should -Be 0
    }

    It 'Invoke-ElevatedInstall: 결과 파일 없음 -> Error = 승격 단계 결과 없음' {
        Mock Start-Process {}
        $res = Invoke-ElevatedInstall -Ids @('Git.Git')
        $res.Requested | Should -Be 1
        $res.Error | Should -Be '승격 단계 결과 없음'
    }

    It 'Invoke-ElevatedInstall: 깨진 JSON -> Error = 승격 단계 결과 없음' {
        Mock Start-Process {
            param($ArgumentList)
            $decoded = [System.Text.Encoding]::Unicode.GetString([System.Convert]::FromBase64String($ArgumentList[-1]))
            if ($decoded -match "WriteAllText\('([^']+)'") {
                $p = $Matches[1].Replace("''", "'")
                [System.IO.File]::WriteAllText($p, '{bad-json', [System.Text.Encoding]::UTF8)
            }
        }
        $res = Invoke-ElevatedInstall -Ids @('Git.Git')
        $res.Requested | Should -Be 1
        $res.Error | Should -Be '승격 단계 결과 없음'
    }

    It 'Register-WingetFamily: Add-AppxPackage -RegisterByFamilyName 호출' {
        $script:regCalled = $false
        Mock Add-AppxPackage {
            param([switch]$RegisterByFamilyName, [string]$MainPackage)
            if ($RegisterByFamilyName -and $MainPackage -eq 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe') {
                $script:regCalled = $true
            }
        }

        Register-WingetFamily
        $script:regCalled | Should -BeTrue
    }

    It 'Install-WingetFromGitHub: 의존성 .appx 먼저, msixbundle 나중 순서로 Add-AppxPackage 호출' {
        Mock Invoke-RestMethod {
            return [pscustomobject]@{
                assets = @(
                    [pscustomobject]@{
                        name                 = 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle'
                        browser_download_url = 'https://example.invalid/winget.msixbundle'
                    },
                    [pscustomobject]@{
                        name                 = 'DesktopAppInstaller_Dependencies.zip'
                        browser_download_url = 'https://example.invalid/deps.zip'
                    }
                )
            }
        }
        Mock Invoke-WebRequest {
            param([string]$Uri, [string]$OutFile)
            [System.IO.File]::WriteAllText($OutFile, 'dummy')
        }
        Mock Expand-Archive {
            param([string]$LiteralPath, [string]$DestinationPath)
            $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } elseif ($env:PROCESSOR_ARCHITECTURE -eq 'x86') { 'x86' } else { 'x64' }
            $archDir = Join-Path $DestinationPath $arch
            New-Item -Path $archDir -ItemType Directory -Force | Out-Null
            Set-Content -Path (Join-Path $archDir 'dep1.appx') -Value 'dep'
        }
        $script:appxCalls = [System.Collections.Generic.List[string]]::new()
        Mock Add-AppxPackage {
            param([string]$Path)
            $script:appxCalls.Add([System.IO.Path]::GetFileName($Path))
        }

        Install-WingetFromGitHub
        $script:appxCalls.Count | Should -Be 2
        $script:appxCalls[0] | Should -Be 'dep1.appx'
        $script:appxCalls[1] | Should -Be 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle'
    }

    It 'Start-SetupScript: -NoProfile -File <repo>\pc-setup\setup.ps1 -Skip a,b -ResultPath C:\o\s.json 인자로 실행한다' {
        $fakeCmd = Join-Path $TestDrive 'fake-pwsh.cmd'
        $captureFile = Join-Path $TestDrive 'captured-args.txt'
        Set-Content -Path $fakeCmd -Value "@echo off`r`necho %* > `"$captureFile`"`r`nexit /b 0" -Encoding ASCII

        Mock Get-Command {
            param([string]$Name)
            if ($Name -eq 'pwsh') {
                return [pscustomobject]@{ Source = $fakeCmd }
            }
        }

        $code = Start-SetupScript -RepoPath 'C:\myrepo' -Skip @('a', 'b') -ResultPath 'C:\o\s.json'
        $code | Should -Be 0
        $recorded = (Get-Content -LiteralPath $captureFile -Raw).Trim()
        $recorded | Should -Be '-NoProfile -File C:\myrepo\pc-setup\setup.ps1 -Skip a,b -ResultPath C:\o\s.json'
    }
}
