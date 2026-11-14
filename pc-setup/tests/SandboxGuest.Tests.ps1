BeforeAll {
    $script:GuestScriptPath = (Resolve-Path (Join-Path $PSScriptRoot '..' 'test' 'sandbox-guest.ps1')).Path
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:GuestScriptPath, [ref]$null, [ref]$parseErrors)
    if ($parseErrors -and $parseErrors.Count -gt 0) {
        throw "sandbox-guest.ps1 parse errors: $($parseErrors | Out-String)"
    }
    $funcAsts = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)
    foreach ($fn in $funcAsts) {
        . ([scriptblock]::Create($fn.Extent.Text))
    }

    $judgePath = Join-Path $PSScriptRoot '..' 'test' 'SandboxJudge.psm1'
    Import-Module $judgePath -Force
}

Describe 'sandbox-guest.ps1 5.1 호환 및 파일 형식 검사' {
    It 'Windows PowerShell 5.1 파서 오류가 0개다' {
        $ps51 = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $escaped = $script:GuestScriptPath.Replace("'", "''")
        $cmd = "`$errs = `$null; [void][System.Management.Automation.Language.Parser]::ParseFile('$escaped', [ref]`$null, [ref]`$errs); Write-Output `$errs.Count"
        $out = & $ps51 -NoProfile -Command $cmd
        $LASTEXITCODE | Should -Be 0
        [int]($out | Select-Object -Last 1) | Should -Be 0
    }

    It '파일 첫 3바이트가 UTF-8 BOM(EF BB BF)이다' {
        $bytes = [System.IO.File]::ReadAllBytes($script:GuestScriptPath)
        $bytes.Length | Should -BeGreaterOrEqual 3
        $bytes[0] | Should -Be 0xEF
        $bytes[1] | Should -Be 0xBB
        $bytes[2] | Should -Be 0xBF
    }
}

Describe 'Invoke-Guest 엣지 케이스 표 1~12' {
    BeforeEach {
        $script:caseRoot = Join-Path $TestDrive ([System.Guid]::NewGuid().ToString())
        $script:inDir = Join-Path $script:caseRoot 'in'
        $script:outDir = Join-Path $script:caseRoot 'out'
        $script:repoDir = Join-Path $script:caseRoot 'repo'
        New-Item -Path $script:inDir -ItemType Directory -Force | Out-Null
        New-Item -Path $script:outDir -ItemType Directory -Force | Out-Null
        New-Item -Path (Join-Path $script:repoDir 'pc-setup') -ItemType Directory -Force | Out-Null

        Set-Content -Path (Join-Path $script:inDir 'run.psd1') -Value "@{`n    Skip = @()`n}" -Encoding UTF8

        Mock Test-AdminWindow { return $false }
        Mock Enable-TestUac {}
        Mock Restart-Guest {}
        Mock Update-SessionPath {}
        Mock Get-GuestRepoPath { return $script:repoDir }

        $script:childCalls = [System.Collections.Generic.List[object]]::new()
        $script:writeBootstrapJson = $true
        $script:writeSetup1Json = $true
        $script:writeSetup2Json = $true
        $script:bootstrapExitCode = 0
        $script:setup2ExitCode = 0

        Mock Invoke-Child {
            param([string]$FilePath, [string[]]$Arguments)
            $script:childCalls.Add([pscustomobject]@{
                FilePath  = $FilePath
                Arguments = $Arguments
            })

            $getArgValue = {
                param([string]$Flag)
                if ($null -eq $Arguments) { return $null }
                $idx = [Array]::IndexOf($Arguments, $Flag)
                if ($idx -ge 0 -and ($idx + 1) -lt $Arguments.Count) {
                    return $Arguments[$idx + 1]
                }
                return $null
            }

            $resultPath = & $getArgValue '-ResultPath'
            $setupResultPath = & $getArgValue '-SetupResultPath'

            if (-not [string]::IsNullOrEmpty($setupResultPath)) {
                if ($script:writeBootstrapJson -and -not [string]::IsNullOrEmpty($resultPath)) {
                    $bootPayload = [ordered]@{
                        Check             = $false
                        ElevationRequests = 1
                        DurationSeconds   = 12.3
                        Results           = @(
                            [ordered]@{ Stage = '부트스트랩'; Id = 'winget'; Status = '그대로'; Detail = '' }
                            [ordered]@{ Stage = '부트스트랩'; Id = 'clone'; Status = '바꿈'; Detail = '' }
                        )
                    } | ConvertTo-Json -Depth 10
                    [System.IO.File]::WriteAllText($resultPath, $bootPayload, [System.Text.Encoding]::UTF8)
                }

                if ($script:writeSetup1Json) {
                    $s1Payload = [ordered]@{
                        Check             = $false
                        ElevationRequests = 1
                        DurationSeconds   = 30.0
                        Results           = @(
                            [ordered]@{ Stage = 'Windows 설정'; Id = 'LongPaths'; Status = '바꿈'; Detail = '' }
                        )
                    } | ConvertTo-Json -Depth 10
                    [System.IO.File]::WriteAllText($setupResultPath, $s1Payload, [System.Text.Encoding]::UTF8)
                }

                return $script:bootstrapExitCode
            }

            if ($script:writeSetup2Json -and -not [string]::IsNullOrEmpty($resultPath)) {
                $s2Payload = [ordered]@{
                    Check             = $false
                    ElevationRequests = 1
                    DurationSeconds   = 10.0
                    Results           = @(
                        [ordered]@{ Stage = 'Windows 설정'; Id = 'LongPaths'; Status = '그대로'; Detail = '' }
                    )
                } | ConvertTo-Json -Depth 10
                [System.IO.File]::WriteAllText($resultPath, $s2Payload, [System.Text.Encoding]::UTF8)
            }

            return $script:setup2ExitCode
        }
    }

    It '1: 상태 없음 -> Enable-TestUac·Restart-Guest 각 1번, 상태 uac, Invoke-Child 안 불림, result.json 없음' {
        Invoke-Guest -InDir $script:inDir -OutDir $script:outDir

        Should -Invoke Enable-TestUac -Times 1 -Exactly
        Should -Invoke Restart-Guest -Times 1 -Exactly
        Should -Invoke Invoke-Child -Times 0 -Exactly
        (Get-Content -LiteralPath (Join-Path $script:outDir 'state.txt') -Raw).Trim() | Should -Be 'uac'
        Test-Path -LiteralPath (Join-Path $script:outDir 'result.json') | Should -BeFalse
    }

    It '2: 상태 uac, 관리자 아님, 부트스트랩·셋업 모두 JSON 씀 -> Invoke-Child 2번, Runs 3개(이름 순서), Error 빈 값, 상태 done' {
        Set-Content -LiteralPath (Join-Path $script:outDir 'state.txt') -Value 'uac' -NoNewline -Encoding ASCII

        Invoke-Guest -InDir $script:inDir -OutDir $script:outDir

        Should -Invoke Invoke-Child -Times 2 -Exactly
        Should -Invoke Update-SessionPath -Times 1 -Exactly
        Should -Invoke Get-GuestRepoPath -Times 1 -Exactly
        $script:childCalls[0].FilePath | Should -Be 'powershell.exe'
        ($script:childCalls[0].Arguments -join '|') | Should -Be (
            "-NoProfile|-ExecutionPolicy|Bypass|-File|$(Join-Path $script:inDir 'bootstrap.ps1')|-Source|$(Join-Path $script:inDir 'repo.bundle')|-ResultPath|$(Join-Path $script:outDir 'bootstrap.json')|-SetupResultPath|$(Join-Path $script:outDir 'setup-1.json')"
        )
        ($script:childCalls[1].Arguments -join '|') | Should -Be (
            "-NoProfile|-File|$(Join-Path $script:repoDir 'pc-setup\setup.ps1')|-ResultPath|$(Join-Path $script:outDir 'setup-2.json')"
        )

        $resultFile = Join-Path $script:outDir 'result.json'
        Test-Path -LiteralPath $resultFile | Should -BeTrue
        $res = Get-Content -LiteralPath $resultFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $res.Error | Should -Be ''
        $res.Runs.Count | Should -Be 3
        $res.Runs[0].Name | Should -Be 'bootstrap'
        $res.Runs[1].Name | Should -Be 'setup-1'
        $res.Runs[2].Name | Should -Be 'setup-2'
        (Get-Content -LiteralPath (Join-Path $script:outDir 'state.txt') -Raw).Trim() | Should -Be 'done'
    }

    It '3: 2 + run.psd1 의 Skip 2개 -> 두 Invoke-Child 인자에 -Skip 과 a,b' {
        Set-Content -LiteralPath (Join-Path $script:outDir 'state.txt') -Value 'uac' -NoNewline -Encoding ASCII
        Set-Content -Path (Join-Path $script:inDir 'run.psd1') -Value "@{`n    Skip = @('a', 'b')`n}" -Encoding UTF8

        Invoke-Guest -InDir $script:inDir -OutDir $script:outDir

        $script:childCalls.Count | Should -Be 2
        foreach ($call in $script:childCalls) {
            $idx = [Array]::IndexOf($call.Arguments, '-Skip')
            $idx | Should -BeGreaterOrEqual 0
            $call.Arguments[$idx + 1] | Should -Be 'a,b'
        }
    }

    It '4: 2 + Skip 없음 -> 인자에 -Skip 없음' {
        Set-Content -LiteralPath (Join-Path $script:outDir 'state.txt') -Value 'uac' -NoNewline -Encoding ASCII
        Set-Content -Path (Join-Path $script:inDir 'run.psd1') -Value "@{`n    Skip = @()`n}" -Encoding UTF8

        Invoke-Guest -InDir $script:inDir -OutDir $script:outDir

        $script:childCalls.Count | Should -Be 2
        foreach ($call in $script:childCalls) {
            ($call.Arguments -contains '-Skip') | Should -BeFalse
        }
    }

    It '5: 상태 uac, 관리자 -> Error UAC 를 켠 뒤에도 관리자 권한으로 돈다, Invoke-Child 안 불림' {
        Set-Content -LiteralPath (Join-Path $script:outDir 'state.txt') -Value 'uac' -NoNewline -Encoding ASCII
        Mock Test-AdminWindow { return $true }

        Invoke-Guest -InDir $script:inDir -OutDir $script:outDir

        Should -Invoke Invoke-Child -Times 0 -Exactly
        $res = Get-Content -LiteralPath (Join-Path $script:outDir 'result.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $res.Error | Should -Be 'UAC 를 켠 뒤에도 관리자 권한으로 돈다'
        (Get-Content -LiteralPath (Join-Path $script:outDir 'state.txt') -Raw).Trim() | Should -Be 'done'
    }

    It '6: 부트스트랩이 setup-1.json 을 쓰지 않음(종료 코드 1) -> Runs 에 bootstrap 하나, setup-2 안 돎' {
        Set-Content -LiteralPath (Join-Path $script:outDir 'state.txt') -Value 'uac' -NoNewline -Encoding ASCII
        $script:writeSetup1Json = $false
        $script:bootstrapExitCode = 1

        Invoke-Guest -InDir $script:inDir -OutDir $script:outDir

        Should -Invoke Invoke-Child -Times 1 -Exactly
        $res = Get-Content -LiteralPath (Join-Path $script:outDir 'result.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $res.Error | Should -Be ''
        $res.Runs.Count | Should -Be 1
        $res.Runs[0].Name | Should -Be 'bootstrap'
        $res.Runs[0].ExitCode | Should -Be 1
        $null -ne $res.Runs[0].Result | Should -BeTrue
        (Get-Content -LiteralPath (Join-Path $script:outDir 'state.txt') -Raw).Trim() | Should -Be 'done'
    }

    It '7: 부트스트랩이 bootstrap.json 도 쓰지 않음 -> bootstrap 의 Result null' {
        Set-Content -LiteralPath (Join-Path $script:outDir 'state.txt') -Value 'uac' -NoNewline -Encoding ASCII
        $script:writeBootstrapJson = $false
        $script:writeSetup1Json = $false
        $script:bootstrapExitCode = 1

        Invoke-Guest -InDir $script:inDir -OutDir $script:outDir

        Should -Invoke Invoke-Child -Times 1 -Exactly
        $res = Get-Content -LiteralPath (Join-Path $script:outDir 'result.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $res.Runs.Count | Should -Be 1
        $res.Runs[0].Name | Should -Be 'bootstrap'
        $null -eq $res.Runs[0].Result | Should -BeTrue
    }

    It '8: Invoke-Child 가 예외 -> Error 에 메시지, result.json 있음, 상태 done (모은 Runs 유지)' {
        Set-Content -LiteralPath (Join-Path $script:outDir 'state.txt') -Value 'uac' -NoNewline -Encoding ASCII
        Mock Invoke-Child { throw '자식 실행 실패' }

        Invoke-Guest -InDir $script:inDir -OutDir $script:outDir

        $resultFile = Join-Path $script:outDir 'result.json'
        Test-Path -LiteralPath $resultFile | Should -BeTrue
        $res = Get-Content -LiteralPath $resultFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $res.Error | Should -Be '자식 실행 실패'
        $res.Runs.Count | Should -Be 0
        (Get-Content -LiteralPath (Join-Path $script:outDir 'state.txt') -Raw).Trim() | Should -Be 'done'

        # setup-2 단계에서 예외가 나면 bootstrap·setup-1 Runs 를 보존한다
        $case2Out = Join-Path $script:caseRoot 'out2'
        New-Item -Path $case2Out -ItemType Directory -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $case2Out 'state.txt') -Value 'uac' -NoNewline -Encoding ASCII
        Mock Invoke-Child {
            param([string]$FilePath, [string[]]$Arguments)
            $idxBoot = [Array]::IndexOf($Arguments, '-ResultPath')
            $idxS1 = [Array]::IndexOf($Arguments, '-SetupResultPath')
            if ($idxS1 -ge 0) {
                [System.IO.File]::WriteAllText($Arguments[$idxBoot + 1], '{"Results":[]}', [System.Text.Encoding]::UTF8)
                [System.IO.File]::WriteAllText($Arguments[$idxS1 + 1], '{"Results":[]}', [System.Text.Encoding]::UTF8)
                return 0
            }
            throw 'setup-2 실행 실패'
        }

        Invoke-Guest -InDir $script:inDir -OutDir $case2Out

        $res2 = Get-Content -LiteralPath (Join-Path $case2Out 'result.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $res2.Error | Should -Be 'setup-2 실행 실패'
        $res2.Runs.Count | Should -Be 2
        $res2.Runs[0].Name | Should -Be 'bootstrap'
        $res2.Runs[1].Name | Should -Be 'setup-1'
        (Get-Content -LiteralPath (Join-Path $case2Out 'state.txt') -Raw).Trim() | Should -Be 'done'
    }

    It '9: 상태 running -> Error 셋업 중 Sandbox 가 다시 시작됐다' {
        Set-Content -LiteralPath (Join-Path $script:outDir 'state.txt') -Value 'running' -NoNewline -Encoding ASCII

        Invoke-Guest -InDir $script:inDir -OutDir $script:outDir

        Should -Invoke Invoke-Child -Times 0 -Exactly
        $res = Get-Content -LiteralPath (Join-Path $script:outDir 'result.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $res.Error | Should -Be '셋업 중 Sandbox 가 다시 시작됐다'
        (Get-Content -LiteralPath (Join-Path $script:outDir 'state.txt') -Raw).Trim() | Should -Be 'done'
    }

    It '10: 상태 done -> 아무 함수도 안 불림, result.json 을 다시 쓰지 않음' {
        Set-Content -LiteralPath (Join-Path $script:outDir 'state.txt') -Value 'done' -NoNewline -Encoding ASCII
        $resultFile = Join-Path $script:outDir 'result.json'
        Set-Content -LiteralPath $resultFile -Value '{"marker":"keep"}' -NoNewline -Encoding UTF8

        Invoke-Guest -InDir $script:inDir -OutDir $script:outDir

        Should -Invoke Test-AdminWindow -Times 0 -Exactly
        Should -Invoke Enable-TestUac -Times 0 -Exactly
        Should -Invoke Restart-Guest -Times 0 -Exactly
        Should -Invoke Invoke-Child -Times 0 -Exactly
        Should -Invoke Update-SessionPath -Times 0 -Exactly
        Should -Invoke Get-GuestRepoPath -Times 0 -Exactly
        (Get-Content -LiteralPath $resultFile -Raw -Encoding UTF8) | Should -Be '{"marker":"keep"}'
    }

    It '11: 2 의 progress.log -> bootstrap 시작·bootstrap 끝 (0)·setup-2 시작·setup-2 끝 (0)·끝 줄이 순서대로' {
        Set-Content -LiteralPath (Join-Path $script:outDir 'state.txt') -Value 'uac' -NoNewline -Encoding ASCII

        Invoke-Guest -InDir $script:inDir -OutDir $script:outDir

        $lines = Get-Content -LiteralPath (Join-Path $script:outDir 'progress.log') -Encoding UTF8
        $expected = @('bootstrap 시작', 'bootstrap 끝 (0)', 'setup-2 시작', 'setup-2 끝 (0)', '끝')
        $lines.Count | Should -Be $expected.Count
        for ($i = 0; $i -lt $expected.Count; $i++) {
            $lines[$i] | Should -Match ('^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} ' + [regex]::Escape($expected[$i]) + '$')
        }
    }

    It '12: 2 의 result.json 을 Test-SandboxRun 에 넣음 -> 예외 없이 판정이 나온다(모양 호환)' {
        Set-Content -LiteralPath (Join-Path $script:outDir 'state.txt') -Value 'uac' -NoNewline -Encoding ASCII

        Invoke-Guest -InDir $script:inDir -OutDir $script:outDir

        $runObj = Get-Content -LiteralPath (Join-Path $script:outDir 'result.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $judgment = Test-SandboxRun -Run $runObj -Expected @()
        $null -ne $judgment | Should -BeTrue
        $judgment.Passed | Should -BeTrue
        $judgment.Runs.Count | Should -Be 3
    }
}

Describe '보조 함수 단위 테스트 (실제 외부 호출 없음)' {
    It 'Enable-TestUac: New-ItemProperty 로 EnableLUA=1, ConsentPromptBehaviorAdmin=0 (DWord) 을 쓴다' {
        $script:regWrites = [System.Collections.Generic.List[object]]::new()
        Mock New-ItemProperty {
            param([string]$LiteralPath, [string]$Name, $Value, [string]$PropertyType, [switch]$Force)
            $script:regWrites.Add([pscustomobject]@{
                LiteralPath  = $LiteralPath
                Name         = $Name
                Value        = $Value
                PropertyType = $PropertyType
                Force        = [bool]$Force
            })
        }

        Enable-TestUac

        $script:regWrites.Count | Should -Be 2
        $script:regWrites[0].LiteralPath | Should -Be 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
        $script:regWrites[0].Name | Should -Be 'EnableLUA'
        $script:regWrites[0].Value | Should -Be 1
        $script:regWrites[0].PropertyType | Should -Be 'DWord'
        $script:regWrites[0].Force | Should -BeTrue
        $script:regWrites[1].LiteralPath | Should -Be 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
        $script:regWrites[1].Name | Should -Be 'ConsentPromptBehaviorAdmin'
        $script:regWrites[1].Value | Should -Be 0
        $script:regWrites[1].PropertyType | Should -Be 'DWord'
        $script:regWrites[1].Force | Should -BeTrue
    }

    It 'Read-JsonOrNull: 없음·빈 파일·깨진 JSON 은 null, 정상 JSON 은 객체 반환' {
        $dir = Join-Path $TestDrive ([System.Guid]::NewGuid().ToString())
        New-Item -Path $dir -ItemType Directory -Force | Out-Null

        Read-JsonOrNull -Path (Join-Path $dir 'missing.json') | Should -BeNullOrEmpty

        $emptyPath = Join-Path $dir 'empty.json'
        Set-Content -LiteralPath $emptyPath -Value '' -Encoding UTF8
        Read-JsonOrNull -Path $emptyPath | Should -BeNullOrEmpty

        $badPath = Join-Path $dir 'bad.json'
        Set-Content -LiteralPath $badPath -Value '{bad' -Encoding UTF8
        Read-JsonOrNull -Path $badPath | Should -BeNullOrEmpty

        $okPath = Join-Path $dir 'ok.json'
        Set-Content -LiteralPath $okPath -Value '{"a":1}' -Encoding UTF8
        $obj = Read-JsonOrNull -Path $okPath
        $obj.a | Should -Be 1
    }

    It 'Write-GuestResult: Depth 20 으로 result.json 을 쓰고 result.json.tmp 는 남기지 않는다' {
        $dir = Join-Path $TestDrive ([System.Guid]::NewGuid().ToString())
        New-Item -Path $dir -ItemType Directory -Force | Out-Null

        $payload = [ordered]@{
            Error = ''
            Runs  = @(
                [ordered]@{
                    Name     = 'bootstrap'
                    ExitCode = 0
                    Result   = [ordered]@{
                        Results = @(
                            [ordered]@{ Stage = '부트스트랩'; Id = 'winget'; Status = '그대로'; Detail = '' }
                        )
                    }
                }
            )
        }

        Write-GuestResult -OutDir $dir -Result $payload

        Test-Path -LiteralPath (Join-Path $dir 'result.json.tmp') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $dir 'result.json') | Should -BeTrue
        $parsed = Get-Content -LiteralPath (Join-Path $dir 'result.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $parsed.Runs[0].Result.Results[0].Id | Should -Be 'winget'
    }

    It 'pwsh 를 찾지 못하면 ProgramFiles\PowerShell\7\pwsh.exe 로 setup-2 를 호출한다' {
        $caseRoot = Join-Path $TestDrive ([System.Guid]::NewGuid().ToString())
        $inDir = Join-Path $caseRoot 'in'
        $outDir = Join-Path $caseRoot 'out'
        $repoDir = Join-Path $caseRoot 'repo'
        New-Item -Path $inDir -ItemType Directory -Force | Out-Null
        New-Item -Path $outDir -ItemType Directory -Force | Out-Null
        New-Item -Path (Join-Path $repoDir 'pc-setup') -ItemType Directory -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $outDir 'state.txt') -Value 'uac' -NoNewline -Encoding ASCII

        Mock Test-AdminWindow { return $false }
        Mock Update-SessionPath {}
        Mock Get-GuestRepoPath { return $repoDir }
        Mock Get-Command { return $null } -ParameterFilter { $Name -eq 'pwsh' }

        $script:capturedSetup2Exe = $null
        Mock Invoke-Child {
            param([string]$FilePath, [string[]]$Arguments)
            $idx = [Array]::IndexOf($Arguments, '-SetupResultPath')
            if ($idx -ge 0) {
                $s1Path = $Arguments[$idx + 1]
                [System.IO.File]::WriteAllText($s1Path, '{"Check":false,"ElevationRequests":1,"DurationSeconds":1,"Results":[]}', [System.Text.Encoding]::UTF8)
                return 0
            }
            $script:capturedSetup2Exe = $FilePath
            return 0
        }

        Invoke-Guest -InDir $inDir -OutDir $outDir

        $script:capturedSetup2Exe | Should -Be (Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe')
    }
}
