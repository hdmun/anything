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
    $script:Prompt = 'SETUP.md 를 읽고 셋업해'
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

    It 'setup.ps1·RunAs·api.github.com·ResultPath·SetEnvironmentVariable·-Skip 문자열이 없다' {
        $raw = [System.IO.File]::ReadAllText($script:BootstrapPath, [System.Text.Encoding]::ASCII)
        $raw | Should -Not -Match ([regex]::Escape('setup.ps1'))
        $raw | Should -Not -Match 'RunAs'
        $raw | Should -Not -Match ([regex]::Escape('api.github.com'))
        $raw | Should -Not -Match 'ResultPath'
        $raw | Should -Not -Match 'SetEnvironmentVariable'
        # 대소문자를 구분한다: 에이전트 플래그 --dangerously-skip-permissions 는 매개변수 -Skip 이 아니다.
        $raw | Should -Not -MatchExactly '-Skip'
    }

    It '모든 Invoke-WebRequest 줄에 -UseBasicParsing 이 있다' {
        $webLines = @(Get-Content -LiteralPath $script:BootstrapPath | Where-Object { $_ -match 'Invoke-WebRequest' })
        $webLines.Count | Should -BeGreaterThan 0
        foreach ($line in $webLines) {
            $line | Should -Match '-UseBasicParsing'
        }
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

Describe 'Invoke-Bootstrap 정상 경로와 엣지 케이스' {
    BeforeEach {
        $script:lines = [System.Collections.Generic.List[string]]::new()
        Mock Write-Host { $script:lines.Add([string]$Object) }
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
        Mock Test-CommandExists { return $true }
        Mock Get-AgentExePath { return $Agent }
        Mock Get-GitLatestTag { throw 'should not be called' }
        Mock Install-GitForWindows { throw 'should not be called' }
        Mock Install-AgentCli { throw 'should not be called' }
        Mock Invoke-Winget { throw 'should not be called' }
        Mock Invoke-Git { return 0 }

        $script:newRepoWithSetup = {
            param([string]$Path)
            New-Item -Path (Join-Path $Path 'pc-setup') -ItemType Directory -Force | Out-Null
            Set-Content -Path (Join-Path $Path 'pc-setup\SETUP.md') -Value '# dummy'
        }
        $script:guidanceLines = {
            @($script:lines | Where-Object { $_ -like 'cd *' -or $_ -like "*$script:Prompt*" })
        }
    }

    It '관리자 창 -> 2, 다른 단계 안 불림, 문구 일치' {
        Mock Test-AdminWindow { return $true }
        Mock Get-WingetVersion { throw 'should not be called' }
        Mock Invoke-Git { throw 'should not be called' }

        $ret = Invoke-Bootstrap
        $ret | Should -Be 2
        $script:lines | Should -Contain '부트스트랩은 일반 권한 창에서 실행한다'
        Should -Invoke Test-CommandExists -Times 0 -Exactly
        (& $script:guidanceLines).Count | Should -Be 0
    }

    It '모두 이미 있음 -> 모든 단계 그대로, 설치 함수 0회, 안내 두 줄, 0' {
        & $script:newRepoWithSetup $script:defaultRepo

        $ret = Invoke-Bootstrap
        $ret | Should -Be 0
        $script:lines | Should -Contain '[부트스트랩] winget: 그대로'
        $script:lines | Should -Contain '[부트스트랩] Git: 그대로'
        $script:lines | Should -Contain '[부트스트랩] Microsoft.PowerShell: 그대로'
        $script:lines | Should -Contain '[부트스트랩] claude: 그대로'
        $script:lines | Should -Contain '[부트스트랩] clone: 그대로'
        Should -Invoke Install-GitForWindows -Times 0 -Exactly
        Should -Invoke Invoke-Winget -Times 0 -Exactly
        Should -Invoke Install-AgentCli -Times 0 -Exactly
        Should -Invoke Invoke-Git -Times 0 -Exactly
        Should -Invoke Update-SessionPath -Times 0 -Exactly
        $script:lines[-2] | Should -Be "cd $script:defaultRepo\pc-setup"
        $script:lines[-1] | Should -Be "claude --dangerously-skip-permissions `"$script:Prompt`""
        (& $script:guidanceLines).Count | Should -Be 2
    }

    It '저장소 경로 없음 -> git clone Source 경로, clone 바꿈, 안내 두 줄' {
        $script:gitArgs = $null
        Mock Invoke-Git { $script:gitArgs = $Arguments; return 0 }

        $ret = Invoke-Bootstrap
        $ret | Should -Be 0
        ($script:gitArgs -join '|') | Should -Be "clone|https://github.com/hdmun/anything.git|$script:defaultRepo"
        $script:lines | Should -Contain '[부트스트랩] clone: 바꿈'
        (& $script:guidanceLines).Count | Should -Be 2
    }

    It 'winget 없음 -> Register-WingetFamily 후 충분 -> winget 바꿈, Install-WingetFromGitHub 안 불림' {
        $script:wingetChecks = 0
        Mock Get-WingetVersion {
            $script:wingetChecks++
            if ($script:wingetChecks -eq 1) { return $null }
            return [version]'1.29.380'
        }
        Mock Register-WingetFamily {}

        $ret = Invoke-Bootstrap
        $ret | Should -Be 0
        Should -Invoke Register-WingetFamily -Times 1 -Exactly
        Should -Invoke Install-WingetFromGitHub -Times 0 -Exactly
        $script:lines | Should -Contain '[부트스트랩] winget: 바꿈'
    }

    It 'winget 낡음·등록도 실패 -> GitHub 설치 후 충분 -> winget 바꿈' {
        $script:githubInstalled = $false
        Mock Get-WingetVersion {
            if ($script:githubInstalled) { return [version]'1.29.380' }
            return [version]'1.2.0'
        }
        Mock Register-WingetFamily { throw 'not registered' }
        Mock Install-WingetFromGitHub { $script:githubInstalled = $true }

        $ret = Invoke-Bootstrap
        $ret | Should -Be 0
        Should -Invoke Register-WingetFamily -Times 1 -Exactly
        Should -Invoke Install-WingetFromGitHub -Times 1 -Exactly
        $script:lines | Should -Contain '[부트스트랩] winget: 바꿈'
    }

    It 'winget GitHub 설치도 실패 -> winget 실패, 1, 뒤 단계 안 불림, 안내 없음' {
        Mock Get-WingetVersion { return $null }
        Mock Register-WingetFamily { throw 'register failed' }
        Mock Install-WingetFromGitHub { throw 'github download failed' }
        Mock Invoke-Git { throw 'should not be called' }

        $ret = Invoke-Bootstrap
        $ret | Should -Be 1
        $script:lines | Should -Contain '[부트스트랩] winget: 실패: github download failed'
        Should -Invoke Test-CommandExists -Times 0 -Exactly
        (& $script:guidanceLines).Count | Should -Be 0
    }

    It 'Git 만 없음 -> 최신 태그로 Install-GitForWindows, Update-SessionPath, Git 바꿈' {
        $script:gitInstalled = $false
        Mock Test-CommandExists {
            if ($Name -eq 'git') { return $script:gitInstalled }
            return $true
        }
        Mock Get-GitLatestTag { return 'v2.47.1.windows.1' }
        $script:capturedTag = $null
        Mock Install-GitForWindows { $script:capturedTag = $Tag; $script:gitInstalled = $true; return 0 }

        $ret = Invoke-Bootstrap
        $ret | Should -Be 0
        $script:capturedTag | Should -Be 'v2.47.1.windows.1'
        Should -Invoke Update-SessionPath -Times 1 -Exactly
        $script:lines | Should -Contain '[부트스트랩] Git: 바꿈'
        $script:lines | Should -Contain '[부트스트랩] Microsoft.PowerShell: 그대로'
        $script:lines | Should -Contain '[부트스트랩] claude: 그대로'
        Should -Invoke Invoke-Winget -Times 0 -Exactly
    }

    It 'pwsh 만 없음 -> winget install --id Microsoft.PowerShell (사용자 범위 인자), Update-SessionPath, 바꿈' {
        $script:pwshInstalled = $false
        Mock Test-CommandExists {
            if ($Name -eq 'pwsh') { return $script:pwshInstalled }
            return $true
        }
        $script:wingetArgs = $null
        Mock Invoke-Winget { $script:wingetArgs = $Arguments; $script:pwshInstalled = $true; return 0 }

        $ret = Invoke-Bootstrap
        $ret | Should -Be 0
        ($script:wingetArgs -join ' ') | Should -Be 'install --id Microsoft.PowerShell --source winget --exact --silent --accept-package-agreements --accept-source-agreements'
        Should -Invoke Update-SessionPath -Times 1 -Exactly
        $script:lines | Should -Contain '[부트스트랩] Git: 그대로'
        $script:lines | Should -Contain '[부트스트랩] Microsoft.PowerShell: 바꿈'
        Should -Invoke Install-GitForWindows -Times 0 -Exactly
    }

    It '에이전트 CLI 만 없음 -> Install-AgentCli -Agent claude, Update-SessionPath, 바꿈' {
        $script:agentInstalled = $false
        Mock Get-AgentExePath { if ($script:agentInstalled) { return $Agent }; return '' }
        $script:capturedAgent = $null
        Mock Install-AgentCli { $script:capturedAgent = $Agent; $script:agentInstalled = $true; return 0 }

        $ret = Invoke-Bootstrap
        $ret | Should -Be 0
        $script:capturedAgent | Should -Be 'claude'
        Should -Invoke Update-SessionPath -Times 1 -Exactly
        $script:lines | Should -Contain '[부트스트랩] claude: 바꿈'
        $script:lines[-1] | Should -Be "claude --dangerously-skip-permissions `"$script:Prompt`""
    }

    It '-Agent agy -> agy 설치, agy 안내 줄' {
        $script:agentInstalled = $false
        Mock Get-AgentExePath { if ($script:agentInstalled) { return $Agent }; return '' }
        $script:capturedAgent = $null
        Mock Install-AgentCli { $script:capturedAgent = $Agent; $script:agentInstalled = $true; return 0 }

        $ret = Invoke-Bootstrap -Agent 'agy'
        $ret | Should -Be 0
        $script:capturedAgent | Should -Be 'agy'
        $script:lines | Should -Contain '[부트스트랩] agy: 바꿈'
        $script:lines[-1] | Should -Be "agy --dangerously-skip-permissions -i `"$script:Prompt`""
    }

    It '-Agent codex -> codex 설치, codex 안내 줄' {
        $script:agentInstalled = $false
        Mock Get-AgentExePath { if ($script:agentInstalled) { return $Agent }; return '' }
        $script:capturedAgent = $null
        Mock Install-AgentCli { $script:capturedAgent = $Agent; $script:agentInstalled = $true; return 0 }

        $ret = Invoke-Bootstrap -Agent 'codex'
        $ret | Should -Be 0
        $script:capturedAgent | Should -Be 'codex'
        $script:lines | Should -Contain '[부트스트랩] codex: 바꿈'
        $script:lines[-1] | Should -Be "codex --yolo `"$script:Prompt`""
    }

    It '설치 뒤 PATH 에 없고 알려진 위치(공백 없음)에 있음 -> 바꿈, 안내 줄이 전체 경로로 시작' {
        $script:agentInstalled = $false
        Mock Get-AgentExePath { if ($script:agentInstalled) { return 'C:\Users\me\.local\bin\claude.exe' }; return '' }
        Mock Install-AgentCli { $script:agentInstalled = $true; return 0 }

        $ret = Invoke-Bootstrap
        $ret | Should -Be 0
        $script:lines | Should -Contain '[부트스트랩] claude: 바꿈'
        $script:lines[-1] | Should -Be "C:\Users\me\.local\bin\claude.exe --dangerously-skip-permissions `"$script:Prompt`""
    }

    It '설치 뒤 PATH 에 없고 알려진 위치(공백 있음)에 있음 -> 안내 줄이 & "경로" 로 시작' {
        $script:agentInstalled = $false
        Mock Get-AgentExePath { if ($script:agentInstalled) { return 'C:\Users\my name\.local\bin\claude.exe' }; return '' }
        Mock Install-AgentCli { $script:agentInstalled = $true; return 0 }

        $ret = Invoke-Bootstrap
        $ret | Should -Be 0
        $script:lines[-1] | Should -Be "& `"C:\Users\my name\.local\bin\claude.exe`" --dangerously-skip-permissions `"$script:Prompt`""
    }

    It 'ANYTHING_REPO 가 있고 SETUP.md 있음 -> 그 경로, clone 그대로, Invoke-Git 안 불림' {
        $envRepo = Join-Path $script:testCaseDir 'custom-repo'
        & $script:newRepoWithSetup $envRepo
        Mock Get-AnythingRepo { return $envRepo }
        Mock Invoke-Git { throw 'should not be called' }

        $ret = Invoke-Bootstrap
        $ret | Should -Be 0
        $script:lines | Should -Contain '[부트스트랩] clone: 그대로'
        $script:lines[-2] | Should -Be "cd $envRepo\pc-setup"
    }

    It 'ANYTHING_REPO 가 있고 그 경로가 없음 -> 그 경로로 clone' {
        $envRepo = Join-Path $script:testCaseDir 'env-repo'
        Mock Get-AnythingRepo { return $envRepo }
        $script:gitArgs = $null
        Mock Invoke-Git { $script:gitArgs = $Arguments; return 0 }

        $ret = Invoke-Bootstrap
        $ret | Should -Be 0
        $script:gitArgs[-1] | Should -Be $envRepo
        $script:lines[-2] | Should -Be "cd $envRepo\pc-setup"
    }

    It '저장소 경로에 공백이 있음 -> cd 줄이 경로를 따옴표로 감싼다' {
        $spaceRepo = Join-Path $script:testCaseDir 'my repo'
        & $script:newRepoWithSetup $spaceRepo
        Mock Get-AnythingRepo { return $spaceRepo }

        $ret = Invoke-Bootstrap
        $ret | Should -Be 0
        $script:lines[-2] | Should -Be "cd `"$spaceRepo\pc-setup`""
    }

    It '-Branch feat -Source C:\x.bundle -> git clone -b feat C:\x.bundle 경로' {
        $script:gitArgs = $null
        Mock Invoke-Git { $script:gitArgs = $Arguments; return 0 }

        $ret = Invoke-Bootstrap -Source 'C:\x.bundle' -Branch 'feat'
        $ret | Should -Be 0
        ($script:gitArgs -join '|') | Should -Be "clone|-b|feat|C:\x.bundle|$script:defaultRepo"
    }

    It '-Branch 빈 값 -> -b 없이 clone' {
        $script:gitArgs = $null
        Mock Invoke-Git { $script:gitArgs = $Arguments; return 0 }

        $ret = Invoke-Bootstrap -Source 'https://example.com/repo.git' -Branch ''
        $ret | Should -Be 0
        ($script:gitArgs -join '|') | Should -Be "clone|https://example.com/repo.git|$script:defaultRepo"
    }
}

Describe 'Invoke-Bootstrap 에러 처리 (실패하면 뒤 단계 없음, 1, 안내 없음)' {
    BeforeEach {
        $script:lines = [System.Collections.Generic.List[string]]::new()
        Mock Write-Host { $script:lines.Add([string]$Object) }
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
        Mock Test-CommandExists { return $true }
        Mock Get-AgentExePath { return $Agent }
        Mock Get-GitLatestTag { return 'v2.47.1.windows.1' }
        Mock Install-GitForWindows { throw 'should not be called' }
        Mock Install-AgentCli { throw 'should not be called' }
        Mock Invoke-Winget { throw 'should not be called' }
        Mock Invoke-Git { throw 'should not be called' }

        $script:assertStopped = {
            param([int]$Ret)
            $Ret | Should -Be 1
            @($script:lines | Where-Object { $_ -like 'cd *' -or $_ -like "*$script:Prompt*" }).Count | Should -Be 0
        }
    }

    Context 'Git 단계' {
        BeforeEach {
            Mock Test-CommandExists { if ($Name -eq 'git') { return $false }; return $true }
        }

        It '최신 태그 읽기 예외 -> 실패: 이유' {
            Mock Get-GitLatestTag { throw 'redirect failed' }

            & $script:assertStopped (Invoke-Bootstrap)
            $script:lines | Should -Contain '[부트스트랩] Git: 실패: redirect failed'
            Should -Invoke Install-GitForWindows -Times 0 -Exactly
            Should -Invoke Get-AgentExePath -Times 0 -Exactly
        }

        It '최신 태그가 빈 값 -> 실패: 최신 태그를 읽지 못했다' {
            Mock Get-GitLatestTag { return '' }

            & $script:assertStopped (Invoke-Bootstrap)
            $script:lines | Should -Contain '[부트스트랩] Git: 실패: 최신 태그를 읽지 못했다'
        }

        It '설치 종료 코드 5 -> 실패: Git 설치 종료 코드 5' {
            Mock Install-GitForWindows { return 5 }

            & $script:assertStopped (Invoke-Bootstrap)
            $script:lines | Should -Contain '[부트스트랩] Git: 실패: Git 설치 종료 코드 5'
            Should -Invoke Get-AgentExePath -Times 0 -Exactly
        }

        It '설치 뒤에도 git 없음 -> 실패: 설치 뒤에도 git 이 없다' {
            Mock Install-GitForWindows { return 0 }

            & $script:assertStopped (Invoke-Bootstrap)
            $script:lines | Should -Contain '[부트스트랩] Git: 실패: 설치 뒤에도 git 이 없다'
            Should -Invoke Update-SessionPath -Times 1 -Exactly
        }
    }

    Context 'pwsh 단계' {
        BeforeEach {
            Mock Test-CommandExists { if ($Name -eq 'pwsh') { return $false }; return $true }
        }

        It 'winget 종료 코드 0 아님 -> 실패: pwsh 설치 종료 코드 n' {
            Mock Invoke-Winget { return -1978335212 }

            & $script:assertStopped (Invoke-Bootstrap)
            $script:lines | Should -Contain '[부트스트랩] Microsoft.PowerShell: 실패: pwsh 설치 종료 코드 -1978335212'
            Should -Invoke Get-AgentExePath -Times 0 -Exactly
        }

        It '설치 뒤에도 pwsh 없음 -> 실패: 설치 뒤에도 pwsh 이 없다' {
            Mock Invoke-Winget { return 0 }

            & $script:assertStopped (Invoke-Bootstrap)
            $script:lines | Should -Contain '[부트스트랩] Microsoft.PowerShell: 실패: 설치 뒤에도 pwsh 이 없다'
        }
    }

    Context '에이전트 CLI 단계' {
        BeforeEach {
            Mock Get-AgentExePath { return '' }
        }

        It '설치 종료 코드 1 -> 실패: claude 설치 종료 코드 1, clone 안 함' {
            Mock Install-AgentCli { return 1 }

            & $script:assertStopped (Invoke-Bootstrap)
            $script:lines | Should -Contain '[부트스트랩] claude: 실패: claude 설치 종료 코드 1'
            Should -Invoke Invoke-Git -Times 0 -Exactly
        }

        It '설치 뒤 PATH 에도 알려진 위치에도 없음 -> 실패: 설치 뒤에도 codex 이 없다' {
            Mock Install-AgentCli { return 0 }

            & $script:assertStopped (Invoke-Bootstrap -Agent 'codex')
            $script:lines | Should -Contain '[부트스트랩] codex: 실패: 설치 뒤에도 codex 이 없다'
            Should -Invoke Update-SessionPath -Times 1 -Exactly
        }
    }

    Context 'clone 단계' {
        It '저장소 경로가 있지만 pc-setup\SETUP.md 없음 -> 실패: 경로 에 셋업이 없다' {
            New-Item -Path $script:defaultRepo -ItemType Directory -Force | Out-Null

            & $script:assertStopped (Invoke-Bootstrap)
            $script:lines | Should -Contain "[부트스트랩] clone: 실패: $script:defaultRepo 에 셋업이 없다"
        }

        It 'git clone 종료 코드 128 -> 실패: git clone 종료 코드 128' {
            Mock Invoke-Git { return 128 }

            & $script:assertStopped (Invoke-Bootstrap)
            $script:lines | Should -Contain '[부트스트랩] clone: 실패: git clone 종료 코드 128'
        }
    }
}

Describe '하위 함수 단위 테스트 (실제 외부 명령 호출 없음)' {
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

    It 'Install-WingetFromGitHub: API 없이 releases/latest/download 에서 받고, 의존성 .appx 먼저·msixbundle 나중으로 설치' {
        Mock Invoke-RestMethod { throw 'should not be called' }
        $script:webUris = [System.Collections.Generic.List[string]]::new()
        Mock Invoke-WebRequest {
            param([string]$Uri, [string]$OutFile)
            $script:webUris.Add($Uri)
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
        $script:webUris | Should -Contain 'https://github.com/microsoft/winget-cli/releases/latest/download/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle'
        $script:webUris | Should -Contain 'https://github.com/microsoft/winget-cli/releases/latest/download/DesktopAppInstaller_Dependencies.zip'
        Should -Invoke Invoke-RestMethod -Times 0 -Exactly
        $script:appxCalls.Count | Should -Be 2
        $script:appxCalls[0] | Should -Be 'dep1.appx'
        $script:appxCalls[1] | Should -Be 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle'
    }

    It 'Get-GitInstallerName: 태그를 64비트 설치 파일 이름으로 바꾼다' {
        Get-GitInstallerName -Tag 'v2.47.1.windows.1' | Should -Be 'Git-2.47.1-64-bit.exe'
        Get-GitInstallerName -Tag 'v2.47.1.windows.2' | Should -Be 'Git-2.47.1.2-64-bit.exe'
        { Get-GitInstallerName -Tag 'v2.47.1' } | Should -Throw
    }

    It 'Install-GitForWindows: 그 태그의 설치 파일을 받아 비관리자 무인 설치 인자로 실행하고 종료 코드를 돌려준다' {
        $script:webUri = $null
        Mock Invoke-WebRequest {
            param([string]$Uri, [string]$OutFile)
            $script:webUri = $Uri
            [System.IO.File]::WriteAllText($OutFile, 'dummy')
        }
        $script:procArgs = $null
        $script:procVerb = $null
        Mock Start-Process {
            $script:procArgs = $ArgumentList
            $script:procVerb = $Verb
            return [pscustomobject]@{ ExitCode = 3 }
        }

        $code = Install-GitForWindows -Tag 'v2.47.1.windows.1'
        $code | Should -Be 3
        $script:webUri | Should -Be 'https://github.com/git-for-windows/git/releases/download/v2.47.1.windows.1/Git-2.47.1-64-bit.exe'
        $expectedDir = Join-Path $env:LOCALAPPDATA 'Programs\Git'
        ($script:procArgs -join ' ') | Should -Be "/VERYSILENT /NORESTART /DIR=`"$expectedDir`" /o:PathOption=Cmd"
        ($script:procArgs -join ' ') | Should -Not -Match 'CURRENTUSER'
        $script:procVerb | Should -BeNullOrEmpty
    }

    It 'Get-AgentInstallUrl: 에이전트마다 공식 install.ps1 주소' {
        Get-AgentInstallUrl -Agent 'claude' | Should -Be 'https://claude.ai/install.ps1'
        Get-AgentInstallUrl -Agent 'agy' | Should -Be 'https://antigravity.google/cli/install.ps1'
        Get-AgentInstallUrl -Agent 'codex' | Should -Be 'https://chatgpt.com/codex/install.ps1'
    }

    It 'Get-AgentKnownPath: 에이전트마다 알려진 설치 위치' {
        Get-AgentKnownPath -Agent 'claude' | Should -Be (Join-Path $env:USERPROFILE '.local\bin\claude.exe')
        Get-AgentKnownPath -Agent 'agy' | Should -Be (Join-Path $env:LOCALAPPDATA 'agy\bin\agy.exe')
        Get-AgentKnownPath -Agent 'codex' | Should -Be (Join-Path $env:LOCALAPPDATA 'Programs\OpenAI\Codex\bin\codex.exe')
    }

    It 'Get-AgentExePath: PATH 에 있으면 이름, 아니면 알려진 위치의 전체 경로, 둘 다 없으면 빈 문자열' {
        $knownExe = Join-Path $TestDrive 'known\claude.exe'
        Mock Get-AgentKnownPath { return $knownExe }

        Mock Test-CommandExists { return $true }
        Get-AgentExePath -Agent 'claude' | Should -Be 'claude'

        Mock Test-CommandExists { return $false }
        Get-AgentExePath -Agent 'claude' | Should -Be ''

        New-Item -Path (Split-Path -Parent $knownExe) -ItemType Directory -Force | Out-Null
        Set-Content -Path $knownExe -Value 'dummy'
        Get-AgentExePath -Agent 'claude' | Should -Be $knownExe
    }
}
