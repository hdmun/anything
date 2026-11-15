BeforeAll {
    $sandboxHostPath = Join-Path $PSScriptRoot '..' 'test' 'SandboxHost.psm1'
    Import-Module $sandboxHostPath -Force
    $script:SandboxScriptPath = (Resolve-Path (Join-Path $PSScriptRoot '..' 'test' 'sandbox.ps1')).Path

    function script:New-TestGitRepo {
        param(
            [string[]]$SettingIds = @('LongPaths', 'DarkModeApps'),
            [object[]]$ExpectedItems = @(),
            [switch]$BrokenDeclaration
        )

        $repoRoot = Join-Path $TestDrive ([System.Guid]::NewGuid().ToString())
        $pcSetup = Join-Path $repoRoot 'pc-setup'
        $testDir = Join-Path $pcSetup 'test'
        New-Item -Path $testDir -ItemType Directory -Force | Out-Null

        $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
        $utf8Bom = [System.Text.UTF8Encoding]::new($true)

        if ($BrokenDeclaration) {
            $settingsContent = "@{`n    Items = @(`n        @{ Id = 'Bad'; Path = 'INVALID:\Path'; Name = 'N'; Type = 'DWord'; Value = 1 }`n    )`n}`n"
        } else {
            $entries = @(
                foreach ($id in $SettingIds) {
                    "        @{ Id = '$id'; Path = 'HKCU:\Software\Test'; Name = '$id'; Type = 'DWord'; Value = 1 }"
                }
            ) -join "`n"
            $settingsContent = "@{`n    Items = @(`n$entries`n    )`n}`n"
        }
        [System.IO.File]::WriteAllText((Join-Path $pcSetup 'windows-settings.psd1'), $settingsContent, $utf8NoBom)

        $expEntries = @(
            foreach ($exp in $ExpectedItems) {
                "        @{ Id = '$($exp.Id)'; Result = '$($exp.Result)'; Reason = '$($exp.Reason)' }"
            }
        ) -join "`n"
        $expContent = "@{`n    Items = @(`n$expEntries`n    )`n}`n"
        [System.IO.File]::WriteAllText((Join-Path $testDir 'sandbox-expected.psd1'), $expContent, $utf8NoBom)

        [System.IO.File]::WriteAllText((Join-Path $pcSetup 'bootstrap.ps1'), "# bootstrap head`nWrite-Output 'ok'`n", $utf8NoBom)
        [System.IO.File]::WriteAllText((Join-Path $testDir 'sandbox-guest.ps1'), "# guest head 한글`r`nWrite-Output 'guest'`r`n", $utf8Bom)

        & git init -q $repoRoot | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'git init failed' }
        & git -C $repoRoot config core.autocrlf false | Out-Null
        & git -C $repoRoot config user.name 'test' | Out-Null
        & git -C $repoRoot config user.email 'test@example.com' | Out-Null
        & git -C $repoRoot add -A | Out-Null
        & git -C $repoRoot commit -q -m 'initial' | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'git commit failed' }

        return $repoRoot
    }

    function script:New-PassResultJson {
        return ([ordered]@{
            Error = ''
            Runs  = @(
                [ordered]@{
                    Name     = 'bootstrap'
                    ExitCode = 0
                    Result   = [ordered]@{
                        Check             = $false
                        ElevationRequests = 1
                        DurationSeconds   = 10.0
                        Results           = @(
                            [ordered]@{ Stage = '부트스트랩'; Id = 'winget'; Status = '그대로'; Detail = '' }
                            [ordered]@{ Stage = '부트스트랩'; Id = 'clone'; Status = '바꿈'; Detail = '' }
                        )
                    }
                }
                [ordered]@{
                    Name     = 'setup-1'
                    ExitCode = 0
                    Result   = [ordered]@{
                        Check             = $false
                        ElevationRequests = 1
                        DurationSeconds   = 20.0
                        Results           = @(
                            [ordered]@{ Stage = 'Windows 설정'; Id = 'LongPaths'; Status = '바꿈'; Detail = '' }
                        )
                    }
                }
                [ordered]@{
                    Name     = 'setup-2'
                    ExitCode = 0
                    Result   = [ordered]@{
                        Check             = $false
                        ElevationRequests = 1
                        DurationSeconds   = 5.0
                        Results           = @(
                            [ordered]@{ Stage = 'Windows 설정'; Id = 'LongPaths'; Status = '그대로'; Detail = '' }
                        )
                    }
                }
            )
        } | ConvertTo-Json -Depth 15)
    }

    function script:New-FailResultJson {
        return ([ordered]@{
            Error = ''
            Runs  = @(
                [ordered]@{
                    Name     = 'bootstrap'
                    ExitCode = 0
                    Result   = [ordered]@{
                        Check             = $false
                        ElevationRequests = 1
                        DurationSeconds   = 10.0
                        Results           = @(
                            [ordered]@{ Stage = '부트스트랩'; Id = 'clone'; Status = '실패'; Detail = 'clone 오류' }
                        )
                    }
                }
            )
        } | ConvertTo-Json -Depth 15)
    }
}

Describe 'Get-RunningSandboxIds' {
    It 'WindowsSandboxEnvironments 가 비어 있으면 빈 배열을 돌려준다' {
        Mock -ModuleName SandboxHost Invoke-Wsb {
            return '{ "WindowsSandboxEnvironments": [] }'
        }

        $ids = Get-RunningSandboxIds
        $ids.Count | Should -Be 0
    }

    It '원소가 있으면 Id 문자열 배열을 돌려준다 (실제 wsb list --raw 모양)' {
        Mock -ModuleName SandboxHost Invoke-Wsb {
            return @'
{
  "WindowsSandboxEnvironments": [
    {
      "Id": "feb7d4b5-bf87-41f6-a1dc-d635f8a811ff"
    }
  ]
}
'@
        }

        $ids = Get-RunningSandboxIds
        $ids.Count | Should -Be 1
        $ids[0] | Should -Be 'feb7d4b5-bf87-41f6-a1dc-d635f8a811ff'
    }
}

Describe 'New-WsbConfig' {
    It 'XML 로 파싱되고 MappedFolder·LogonCommand·MemoryInMB 가 명세와 일치한다' {
        $xmlText = New-WsbConfig -InDir 'C:\temp\run1\in' -OutDir 'C:\temp\run1\out'
        $doc = [xml]$xmlText

        $folders = @($doc.Configuration.MappedFolders.MappedFolder)
        $folders.Count | Should -Be 2

        $folders[0].HostFolder | Should -Be 'C:\temp\run1\in'
        $folders[0].SandboxFolder | Should -Be 'C:\pcs\in'
        $folders[0].ReadOnly | Should -Be 'true'

        $folders[1].HostFolder | Should -Be 'C:\temp\run1\out'
        $folders[1].SandboxFolder | Should -Be 'C:\pcs\out'
        $folders[1].ReadOnly | Should -Be 'false'

        $doc.Configuration.LogonCommand.Command | Should -Be 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\pcs\in\sandbox-guest.ps1'
        $doc.Configuration.MemoryInMB | Should -Be '8192'
    }

    It '호스트 경로에 & 가 있으면 XML 이스케이프된다' {
        $xmlText = New-WsbConfig -InDir 'C:\temp\a&b\in' -OutDir 'C:\temp\c&d\out'
        $xmlText | Should -Match 'C:\\temp\\a&amp;b\\in'
        $xmlText | Should -Match 'C:\\temp\\c&amp;d\\out'

        $doc = [xml]$xmlText
        $doc.Configuration.MappedFolders.MappedFolder[0].HostFolder | Should -Be 'C:\temp\a&b\in'
        $doc.Configuration.MappedFolders.MappedFolder[1].HostFolder | Should -Be 'C:\temp\c&d\out'
    }
}

Describe 'Export-HeadFiles' {
    It '작업 트리를 바꾼 뒤에도 HEAD 의 바이트를 그대로 꺼내고 repo.bundle 을 clone 하면 HEAD 커밋이 나온다' {
        $repo = New-TestGitRepo
        $headBootstrapBytes = [System.IO.File]::ReadAllBytes((Join-Path $repo 'pc-setup\bootstrap.ps1'))
        $headGuestBytes = [System.IO.File]::ReadAllBytes((Join-Path $repo 'pc-setup\test\sandbox-guest.ps1'))
        $headCommit = (& git -C $repo rev-parse HEAD).Trim()

        # 작업 트리 수정 (커밋하지 않음)
        Set-Content -LiteralPath (Join-Path $repo 'pc-setup\bootstrap.ps1') -Value '# dirty working tree' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $repo 'pc-setup\test\sandbox-guest.ps1') -Value '# dirty guest' -Encoding UTF8

        $inDir = Join-Path $TestDrive ([System.Guid]::NewGuid().ToString())
        Export-HeadFiles -RepoRoot $repo -InDir $inDir

        $exportedBootBytes = [System.IO.File]::ReadAllBytes((Join-Path $inDir 'bootstrap.ps1'))
        $exportedGuestBytes = [System.IO.File]::ReadAllBytes((Join-Path $inDir 'sandbox-guest.ps1'))

        $exportedBootBytes | Should -Be $headBootstrapBytes
        $exportedGuestBytes | Should -Be $headGuestBytes

        $cloneDir = Join-Path $TestDrive ([System.Guid]::NewGuid().ToString())
        $bundlePath = Join-Path $inDir 'repo.bundle'
        & git clone -q $bundlePath $cloneDir | Out-Null
        $LASTEXITCODE | Should -Be 0
        (& git -C $cloneDir rev-parse HEAD).Trim() | Should -Be $headCommit
    }

    It 'git 종료 코드가 0 이 아니면 예외를 던진다' {
        $notARepo = Join-Path $TestDrive ([System.Guid]::NewGuid().ToString())
        $inDir = Join-Path $TestDrive ([System.Guid]::NewGuid().ToString())
        New-Item -Path $notARepo -ItemType Directory -Force | Out-Null

        { Export-HeadFiles -RepoRoot $notARepo -InDir $inDir } | Should -Throw
    }
}

Describe 'Start-TestSandbox / Stop-TestSandbox / Invoke-Wsb' {
    It 'Start-TestSandbox 는 wsb start --raw 출력에서 Id 를 돌려준다' {
        Mock -ModuleName SandboxHost Invoke-Wsb {
            param([string[]]$Arguments)
            return '{ "Id": "11111111-2222-3333-4444-555555555555" }'
        }

        $id = Start-TestSandbox -Config '<Configuration/>'
        $id | Should -Be '11111111-2222-3333-4444-555555555555'
        Should -Invoke -ModuleName SandboxHost Invoke-Wsb -Times 1 -Exactly -ParameterFilter {
            $Arguments[0] -eq 'start' -and $Arguments[1] -eq '--config' -and $Arguments[3] -eq '--raw'
        }
    }

    It 'Stop-TestSandbox 는 wsb stop --id <id> 를 부른다' {
        Mock -ModuleName SandboxHost Invoke-Wsb { return '' }

        Stop-TestSandbox -Id 'sb-123'
        Should -Invoke -ModuleName SandboxHost Invoke-Wsb -Times 1 -Exactly -ParameterFilter {
            $Arguments -join '|' -eq 'stop|--id|sb-123'
        }
    }

    It 'Invoke-Wsb 는 wsb 종료 코드가 0 이 아니면 예외를 던진다' {
        Mock -ModuleName SandboxHost wsb {
            $global:LASTEXITCODE = 1
            'wsb error'
        }

        { Invoke-Wsb -Arguments @('list', '--raw') } | Should -Throw '*종료 코드 1*'
    }
}

Describe 'Wait-SandboxResult' {
    It 'result.json 이 곧 생기면 $true 를 돌려주고 progress.log 의 줄이 한 번씩만 출력된다' {
        $outDir = Join-Path $TestDrive ([System.Guid]::NewGuid().ToString())
        New-Item -Path $outDir -ItemType Directory -Force | Out-Null
        $progressPath = Join-Path $outDir 'progress.log'
        $resultPath = Join-Path $outDir 'result.json'

        Set-Content -LiteralPath $progressPath -Value '2026-11-15 12:00:00 UAC 켜고 재시작' -Encoding UTF8

        $script:hostLines = [System.Collections.Generic.List[string]]::new()
        Mock -ModuleName SandboxHost Write-Host { $script:hostLines.Add([string]$Object) }

        $script:pollStep = 0
        Mock -ModuleName SandboxHost Start-Sleep {
            $script:pollStep++
            if ($script:pollStep -eq 1) {
                Add-Content -LiteralPath $progressPath -Value '2026-11-15 12:00:05 bootstrap 시작' -Encoding UTF8
            } elseif ($script:pollStep -eq 2) {
                Add-Content -LiteralPath $progressPath -Value '2026-11-15 12:00:10 끝' -Encoding UTF8
                Set-Content -LiteralPath $resultPath -Value '{}' -Encoding UTF8
            }
        }

        $ok = Wait-SandboxResult -OutDir $outDir -Timeout ([TimeSpan]::FromSeconds(10)) -PollSeconds 0.01
        $ok | Should -BeTrue
        $script:hostLines.Count | Should -Be 3
        $script:hostLines[0] | Should -Be '  [Sandbox] 2026-11-15 12:00:00 UAC 켜고 재시작'
        $script:hostLines[1] | Should -Be '  [Sandbox] 2026-11-15 12:00:05 bootstrap 시작'
        $script:hostLines[2] | Should -Be '  [Sandbox] 2026-11-15 12:00:10 끝'
    }

    It 'result.json 이 안 생기면 짧은 Timeout 뒤 $false 를 돌려주고 progress.log 줄은 한 번씩만 출력된다' {
        $outDir = Join-Path $TestDrive ([System.Guid]::NewGuid().ToString())
        New-Item -Path $outDir -ItemType Directory -Force | Out-Null
        $progressPath = Join-Path $outDir 'progress.log'
        Set-Content -LiteralPath $progressPath -Value 'line-1' -Encoding UTF8

        $script:hostLines = [System.Collections.Generic.List[string]]::new()
        Mock -ModuleName SandboxHost Write-Host { $script:hostLines.Add([string]$Object) }

        $ok = Wait-SandboxResult -OutDir $outDir -Timeout ([TimeSpan]::FromMilliseconds(120)) -PollSeconds 0.03
        $ok | Should -BeFalse
        ($script:hostLines | Where-Object { $_ -eq '  [Sandbox] line-1' }).Count | Should -Be 1
    }
}

Describe 'sandbox.ps1 진입점' {
    It '-Skip ''a, b'' 를 넘기면 Invoke-SandboxHarness 가 @(''a'',''b'') 를 받는다' {
        Mock Invoke-SandboxHarness {
            param([string]$RepoRoot, [string[]]$Skip, [int]$TimeoutMinutes)
            return 0
        }

        & $script:SandboxScriptPath -Skip 'a, b'
        $LASTEXITCODE | Should -Be 0
        Should -Invoke Invoke-SandboxHarness -Times 1 -Exactly -ParameterFilter {
            $null -ne $Skip -and $Skip.Count -eq 2 -and $Skip[0] -eq 'a' -and $Skip[1] -eq 'b'
        }
    }
}

Describe 'Invoke-SandboxHarness 엣지 케이스 표 1~11' {
    BeforeEach {
        $script:hostLines = [System.Collections.Generic.List[string]]::new()
        $script:warnLines = [System.Collections.Generic.List[string]]::new()
        Mock -ModuleName SandboxHost Write-Host { $script:hostLines.Add([string]$Object) }
        Mock -ModuleName SandboxHost Write-Warning { $script:warnLines.Add([string]$Message) }

        Mock -ModuleName SandboxHost Invoke-Wsb { throw 'real wsb must not be called' }
        Mock -ModuleName SandboxHost Get-RunningSandboxIds { @() }
        Mock -ModuleName SandboxHost Start-TestSandbox { return 'sb-test-id' }
        Mock -ModuleName SandboxHost Stop-TestSandbox {}

        $script:baseDir = Join-Path $TestDrive ([System.Guid]::NewGuid().ToString())
        New-Item -Path $script:baseDir -ItemType Directory -Force | Out-Null
    }

    It '1: Sandbox 가 이미 떠 있음 -> 2, 실패: Sandbox 사용 중, git·Start-TestSandbox 안 불림' {
        $repo = New-TestGitRepo
        Mock -ModuleName SandboxHost Get-RunningSandboxIds { return ,([string[]]@('existing-id')) }
        Mock -ModuleName SandboxHost git { throw 'git should not be called' }

        $ret = Invoke-SandboxHarness -RepoRoot $repo -BaseDir $script:baseDir
        $ret | Should -Be 2
        $script:hostLines | Should -Contain '실패: Sandbox 사용 중'
        Should -Invoke -ModuleName SandboxHost git -Times 0 -Exactly
        Should -Invoke -ModuleName SandboxHost Start-TestSandbox -Times 0 -Exactly
    }

    It '2: 선언 오류 -> 2, 문제 출력, Start-TestSandbox 안 불림' {
        $repo = New-TestGitRepo -BrokenDeclaration

        $ret = Invoke-SandboxHarness -RepoRoot $repo -BaseDir $script:baseDir
        $ret | Should -Be 2
        ($script:hostLines -join "`n") | Should -Match 'windows-settings\.psd1'
        Should -Invoke -ModuleName SandboxHost Start-TestSandbox -Times 0 -Exactly
    }

    It '3: 예상 결과 Id 가 선언에 없음 -> 2, sandbox-expected.psd1:<줄>: 선언에 없는 Id ''<Id>''' {
        $repo = New-TestGitRepo -SettingIds @('LongPaths') -ExpectedItems @(
            @{ Id = 'GhostItem'; Result = '실패'; Reason = '없음' }
        )

        $ret = Invoke-SandboxHarness -RepoRoot $repo -BaseDir $script:baseDir
        $ret | Should -Be 2
        $script:hostLines | Should -Contain "sandbox-expected.psd1:3: 선언에 없는 Id 'GhostItem'"
        Should -Invoke -ModuleName SandboxHost Start-TestSandbox -Times 0 -Exactly
    }

    It '4: 모르는 사람 -Skip -> 2' {
        $repo = New-TestGitRepo -SettingIds @('LongPaths')

        $ret = Invoke-SandboxHarness -RepoRoot $repo -Skip @('UnknownId') -BaseDir $script:baseDir
        $ret | Should -Be 2
        $script:hostLines | Should -Contain '모르는 -Skip Id: UnknownId'
        Should -Invoke -ModuleName SandboxHost Start-TestSandbox -Times 0 -Exactly
    }

    It '5: 작업 트리에 커밋 안 된 변경 -> 경고 출력 후 계속' {
        $repo = New-TestGitRepo
        Add-Content -LiteralPath (Join-Path $repo 'pc-setup\bootstrap.ps1') -Value '# uncommitted'

        Mock -ModuleName SandboxHost Wait-SandboxResult {
            param([string]$OutDir)
            [System.IO.File]::WriteAllText((Join-Path $OutDir 'result.json'), (New-PassResultJson), [System.Text.Encoding]::UTF8)
            return $true
        }

        $ret = Invoke-SandboxHarness -RepoRoot $repo -BaseDir $script:baseDir
        $ret | Should -Be 0
        $script:hostLines | Should -Contain '경고: 커밋하지 않은 변경은 시험되지 않는다'
        Should -Invoke -ModuleName SandboxHost Start-TestSandbox -Times 1 -Exactly
    }

    It '6: 예상 건너뜀 a + 사람 -Skip b,a -> run.psd1 의 Skip 이 a,b' {
        $repo = New-TestGitRepo -SettingIds @('a', 'b', 'LongPaths') -ExpectedItems @(
            @{ Id = 'a'; Result = '건너뜀'; Reason = '이유' }
        )

        Mock -ModuleName SandboxHost Wait-SandboxResult {
            param([string]$OutDir)
            [System.IO.File]::WriteAllText((Join-Path $OutDir 'result.json'), (New-PassResultJson), [System.Text.Encoding]::UTF8)
            return $true
        }

        $ret = Invoke-SandboxHarness -RepoRoot $repo -Skip @('b,a') -BaseDir $script:baseDir
        $ret | Should -Be 0

        $runDirs = @(Get-ChildItem -LiteralPath $script:baseDir -Directory)
        $runDirs.Count | Should -Be 1
        $runData = Import-PowerShellDataFile -LiteralPath (Join-Path $runDirs[0].FullName 'in\run.psd1')
        $runData.Skip.Count | Should -Be 2
        $runData.Skip[0] | Should -Be 'a'
        $runData.Skip[1] | Should -Be 'b'
    }

    It '7: 정상, 판정 합격 -> 0, Stop-TestSandbox 1번, report.txt 있음, sandbox.wsb 있음' {
        $repo = New-TestGitRepo

        Mock -ModuleName SandboxHost Wait-SandboxResult {
            param([string]$OutDir)
            [System.IO.File]::WriteAllText((Join-Path $OutDir 'result.json'), (New-PassResultJson), [System.Text.Encoding]::UTF8)
            return $true
        }

        $ret = Invoke-SandboxHarness -RepoRoot $repo -BaseDir $script:baseDir
        $ret | Should -Be 0
        Should -Invoke -ModuleName SandboxHost Stop-TestSandbox -Times 1 -Exactly -ParameterFilter { $Id -eq 'sb-test-id' }

        $runDirs = @(Get-ChildItem -LiteralPath $script:baseDir -Directory)
        $runDirs.Count | Should -Be 1
        $runDir = $runDirs[0].FullName

        $script:hostLines | Should -Contain 'Sandbox 시작: sb-test-id'
        $script:hostLines | Should -Contain "로그: $runDir"
        $script:hostLines | Should -Contain 'Sandbox 판정: 합격'

        $reportPath = Join-Path $runDir 'report.txt'
        $wsbPath = Join-Path $runDir 'sandbox.wsb'
        Test-Path -LiteralPath $reportPath -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath $wsbPath -PathType Leaf | Should -BeTrue
        (Get-Content -LiteralPath $reportPath -Encoding UTF8) | Should -Contain 'Sandbox 판정: 합격'
    }

    It '8: 판정 불합격 -> 1, Stop-TestSandbox 1번' {
        $repo = New-TestGitRepo

        Mock -ModuleName SandboxHost Wait-SandboxResult {
            param([string]$OutDir)
            [System.IO.File]::WriteAllText((Join-Path $OutDir 'result.json'), (New-FailResultJson), [System.Text.Encoding]::UTF8)
            return $true
        }

        $ret = Invoke-SandboxHarness -RepoRoot $repo -BaseDir $script:baseDir
        $ret | Should -Be 1
        Should -Invoke -ModuleName SandboxHost Stop-TestSandbox -Times 1 -Exactly
        $script:hostLines | Should -Contain 'Sandbox 판정: 불합격'
    }

    It '9: Wait-SandboxResult 가 $false -> 1, 실패: 시간 초과 (90분), Stop-TestSandbox 1번' {
        $repo = New-TestGitRepo

        Mock -ModuleName SandboxHost Wait-SandboxResult { return $false }

        $ret = Invoke-SandboxHarness -RepoRoot $repo -BaseDir $script:baseDir
        $ret | Should -Be 1
        $script:hostLines | Should -Contain '실패: 시간 초과 (90분)'
        Should -Invoke -ModuleName SandboxHost Stop-TestSandbox -Times 1 -Exactly
    }

    It '10: result.json 이 깨진 JSON -> 1, 실패: result.json 을 읽지 못했다, Stop-TestSandbox 1번' {
        $repo = New-TestGitRepo

        Mock -ModuleName SandboxHost Wait-SandboxResult {
            param([string]$OutDir)
            [System.IO.File]::WriteAllText((Join-Path $OutDir 'result.json'), '{broken json', [System.Text.Encoding]::UTF8)
            return $true
        }

        $ret = Invoke-SandboxHarness -RepoRoot $repo -BaseDir $script:baseDir
        $ret | Should -Be 1
        $script:hostLines | Should -Contain '실패: result.json 을 읽지 못했다'
        Should -Invoke -ModuleName SandboxHost Stop-TestSandbox -Times 1 -Exactly
    }

    It '11: Start-TestSandbox 뒤 예외 -> 1, Stop-TestSandbox 1번' {
        $repo = New-TestGitRepo

        Mock -ModuleName SandboxHost Wait-SandboxResult { throw '대기 중 오류' }

        $ret = Invoke-SandboxHarness -RepoRoot $repo -BaseDir $script:baseDir
        $ret | Should -Be 1
        Should -Invoke -ModuleName SandboxHost Stop-TestSandbox -Times 1 -Exactly
    }

    It 'Stop-TestSandbox 가 실패하면 경고만 출력하고 종료 코드는 바꾸지 않는다' {
        $repo = New-TestGitRepo

        Mock -ModuleName SandboxHost Wait-SandboxResult {
            param([string]$OutDir)
            [System.IO.File]::WriteAllText((Join-Path $OutDir 'result.json'), (New-PassResultJson), [System.Text.Encoding]::UTF8)
            return $true
        }
        Mock -ModuleName SandboxHost Stop-TestSandbox { throw 'wsb stop failed' }

        $ret = Invoke-SandboxHarness -RepoRoot $repo -BaseDir $script:baseDir
        $ret | Should -Be 0
        $script:warnLines.Count | Should -Be 1
        $script:warnLines[0] | Should -Match 'wsb stop failed'
    }

    It '1단계 Get-RunningSandboxIds 예외 -> 예외 없이 2, Start-TestSandbox·wsb 안 불림' {
        $repo = New-TestGitRepo
        Mock -ModuleName SandboxHost wsb { throw 'real wsb must not be called' }
        Mock -ModuleName SandboxHost Get-RunningSandboxIds { throw 'wsb list 실패' }

        $ret = Invoke-SandboxHarness -RepoRoot $repo -BaseDir $script:baseDir
        $ret | Should -Be 2
        $script:hostLines | Should -Contain '실패: wsb list 실패'
        Should -Invoke -ModuleName SandboxHost Start-TestSandbox -Times 0 -Exactly
        Should -Invoke -ModuleName SandboxHost wsb -Times 0 -Exactly
    }

    It '2단계 일반 예외(DeclarationException 아님) -> 예외 없이 2, Start-TestSandbox 안 불림' {
        $repo = New-TestGitRepo
        Mock -ModuleName SandboxHost Get-SetupItems { throw 'unexpected I/O error' }

        $ret = Invoke-SandboxHarness -RepoRoot $repo -BaseDir $script:baseDir
        $ret | Should -Be 2
        $script:hostLines | Should -Contain '실패: unexpected I/O error'
        Should -Invoke -ModuleName SandboxHost Start-TestSandbox -Times 0 -Exactly
    }

    It 'Start-TestSandbox 중 ID 조회 실패 시 finally 에서 남은 Sandbox 를 정리한다' {
        $repo = New-TestGitRepo
        $script:listCalls = 0
        Mock -ModuleName SandboxHost Get-RunningSandboxIds {
            $script:listCalls++
            if ($script:listCalls -eq 1) { return @() }
            return @('leaked-sb-id')
        }
        Mock -ModuleName SandboxHost Start-TestSandbox { throw 'ID 조회 실패' }

        $ret = Invoke-SandboxHarness -RepoRoot $repo -BaseDir $script:baseDir
        $ret | Should -Be 1
        Should -Invoke -ModuleName SandboxHost Stop-TestSandbox -Times 1 -Exactly -ParameterFilter { $Id -eq 'leaked-sb-id' }
    }
}
