# nvm v2 공식 문서 확인 링크:
# - nvm list: https://docs.nvm-windows.com/command/nvm/list
# - nvm install: https://docs.nvm-windows.com/command/nvm/install
# - nvm default: https://docs.nvm-windows.com/command/nvm/default
# - nvm use: https://docs.nvm-windows.com/command/nvm/use
# - v1->v2 업그레이드 / 버전 확인: https://docs.nvm-windows.com/guide/upgrade-from-v1

BeforeAll {
    $envPathModule = Join-Path $PSScriptRoot '..' 'lib' 'EnvPath.psm1'
    Import-Module $envPathModule -Force
    $appRuntimeModule = Join-Path $PSScriptRoot '..' 'lib' 'AppRuntime.psm1'
    Import-Module $appRuntimeModule -Force
}

Describe 'Invoke-NvmApp' {
    It '1: nvm 없음 (-Check <Check>) -> 다름 (nvm v2 없음) / 실패: nvm v2 가 없다' -ForEach @(
        @{ Check = $true;  ExpectedStatus = '다름'; ExpectedDetail = 'nvm v2 없음' }
        @{ Check = $false; ExpectedStatus = '실패'; ExpectedDetail = 'nvm v2 가 없다' }
    ) {
        Mock -ModuleName AppRuntime Update-SessionPath {}
        Mock -ModuleName AppRuntime Invoke-Nvm { return @{ ExitCode = $null; Output = @() } }

        $entry = [pscustomobject]@{ Id = 'node'; Origin = 'nvm'; NodeLine = '26' }
        $res = Invoke-NvmApp -Entry $entry -Check $Check

        $res.Status | Should -Be $ExpectedStatus
        $res.Detail | Should -Be $ExpectedDetail
    }

    It '2: nvm 버전 확인이 1.2.2, -Check $true -> 다름 (nvm v2 없음)' {
        Mock -ModuleName AppRuntime Update-SessionPath {}
        Mock -ModuleName AppRuntime Invoke-Nvm {
            if ($Arguments[0] -eq 'version') {
                return @{ ExitCode = 0; Output = @('1.2.2') }
            }
            throw "예상치 못한 호출: $($Arguments -join ' ')"
        }

        $entry = [pscustomobject]@{ Id = 'node'; Origin = 'nvm'; NodeLine = '26' }
        $res = Invoke-NvmApp -Entry $entry -Check $true

        $res.Status | Should -Be '다름'
        $res.Detail | Should -Be 'nvm v2 없음'
    }

    It '3: 26.1.0 설치됨 (-Check <Check>) -> 그대로' -ForEach @(
        @{ Check = $false }
        @{ Check = $true }
    ) {
        $script:calls = [System.Collections.Generic.List[string]]::new()
        Mock -ModuleName AppRuntime Update-SessionPath {}
        Mock -ModuleName AppRuntime Invoke-Nvm {
            $script:calls.Add(($Arguments -join ' '))
            switch ($Arguments[0]) {
                'version' { return @{ ExitCode = 0; Output = @('2.0.1') } }
                'list'    { return @{ ExitCode = 0; Output = @('* 26.1.0    (default)') } }
                default   { throw "예상치 못한 호출: $($Arguments -join ' ')" }
            }
        }

        $entry = [pscustomobject]@{ Id = 'node'; Origin = 'nvm'; NodeLine = '26' }
        $res = Invoke-NvmApp -Entry $entry -Check $Check

        $res.Status | Should -Be '그대로'
        $res.Detail | Should -Be ''
        $script:calls | Should -Not -Contain 'install 26'
    }

    It '4: 23.3.0 만 있음, 기본 23.3.0, -Check $false -> 26 설치, 기본 안 바꿈, 바꿈' {
        $script:calls = [System.Collections.Generic.List[string]]::new()
        Mock -ModuleName AppRuntime Update-SessionPath {}
        Mock -ModuleName AppRuntime Invoke-Nvm {
            $script:calls.Add(($Arguments -join ' '))
            switch ($Arguments[0]) {
                'version' { return @{ ExitCode = 0; Output = @('2.0.1') } }
                'list'    { return @{ ExitCode = 0; Output = @('* 23.3.0    (default)') } }
                'install' { return @{ ExitCode = 0; Output = @('Installed Node.js v26.1.0') } }
                'default' { return @{ ExitCode = 0; Output = @('Default : v23.3.0') } }
                default   { throw "예상치 못한 호출: $($Arguments -join ' ')" }
            }
        }

        $entry = [pscustomobject]@{ Id = 'node'; Origin = 'nvm'; NodeLine = '26' }
        $res = Invoke-NvmApp -Entry $entry -Check $false

        $res.Status | Should -Be '바꿈'
        $res.Detail | Should -Be ''
        $script:calls | Should -Contain 'install 26'
        $script:calls | Should -Not -Contain 'use 26'
    }

    It '5: 아무 버전도 없음, -Check $false -> 26 설치 후 기본으로 지정, 바꿈' {
        $script:calls = [System.Collections.Generic.List[string]]::new()
        Mock -ModuleName AppRuntime Update-SessionPath {}
        Mock -ModuleName AppRuntime Invoke-Nvm {
            $script:calls.Add(($Arguments -join ' '))
            switch ($Arguments[0]) {
                'version' { return @{ ExitCode = 0; Output = @('2.0.1') } }
                'list'    { return @{ ExitCode = 0; Output = @('No installations recognized.') } }
                'install' { return @{ ExitCode = 0; Output = @('Installed Node.js v26.1.0') } }
                'default' { return @{ ExitCode = 0; Output = @('Default : none') } }
                'use'     { return @{ ExitCode = 0; Output = @('Now using Node.js v26.1.0 by default.') } }
                default   { throw "예상치 못한 호출: $($Arguments -join ' ')" }
            }
        }

        $entry = [pscustomobject]@{ Id = 'node'; Origin = 'nvm'; NodeLine = '26' }
        $res = Invoke-NvmApp -Entry $entry -Check $false

        $res.Status | Should -Be '바꿈'
        $res.Detail | Should -Be ''
        $script:calls | Should -Contain 'install 26'
        $script:calls | Should -Contain 'use 26'
    }

    It '6: 설치된 버전이 v126.0.0 하나, -Check $true -> 다름 (Node 26 줄 없음)' {
        Mock -ModuleName AppRuntime Update-SessionPath {}
        Mock -ModuleName AppRuntime Invoke-Nvm {
            switch ($Arguments[0]) {
                'version' { return @{ ExitCode = 0; Output = @('2.0.1') } }
                'list'    { return @{ ExitCode = 0; Output = @('  v126.0.0') } }
                default   { throw "예상치 못한 호출: $($Arguments -join ' ')" }
            }
        }

        $entry = [pscustomobject]@{ Id = 'node'; Origin = 'nvm'; NodeLine = '26' }
        $res = Invoke-NvmApp -Entry $entry -Check $true

        $res.Status | Should -Be '다름'
        $res.Detail | Should -Be 'Node 26 줄 없음'
    }
}

Describe 'Invoke-PnpmApp' {
    It '7: PNPM_HOME 있음·PATH 있음·패키지 있음 (-Check <Check>) -> 그대로' -ForEach @(
        @{ Check = $false }
        @{ Check = $true }
    ) {
        Mock -ModuleName AppRuntime Get-UserEnv {
            param($Name)
            if ($Name -eq 'PNPM_HOME') { return 'C:\Users\test\AppData\Local\pnpm' }
            if ($Name -eq 'Path')      { return 'C:\Tools;C:\Users\test\AppData\Local\pnpm' }
            return $null
        }
        Mock -ModuleName AppRuntime Set-UserEnv { throw 'Set-UserEnv 가 불리면 안 됩니다' }
        Mock -ModuleName AppRuntime Add-UserPath { return $false }
        Mock -ModuleName AppRuntime Update-SessionPath {}
        Mock -ModuleName AppRuntime Invoke-Pnpm {
            if ($Arguments[0] -eq 'ls') {
                return @{ ExitCode = 0; Output = @('[{"path":"C:\\pnpm\\global\\5","private":false,"dependencies":{"@openai/codex":{"from":"@openai/codex","version":"1.0.0"}}}]') }
            }
            throw "예상치 못한 호출: $($Arguments -join ' ')"
        }

        $entry = [pscustomobject]@{ Id = '@openai/codex'; Origin = 'pnpm' }
        $res = Invoke-PnpmApp -Entry $entry -Check $Check

        $res.Status | Should -Be '그대로'
        $res.Detail | Should -Be ''
    }

    It '8: dependencies 없음, -Check $true -> 다름 (설치 안 됨)' {
        Mock -ModuleName AppRuntime Get-UserEnv {
            param($Name)
            if ($Name -eq 'PNPM_HOME') { return 'C:\Users\test\AppData\Local\pnpm' }
            if ($Name -eq 'Path')      { return 'C:\Users\test\AppData\Local\pnpm' }
            return $null
        }
        Mock -ModuleName AppRuntime Update-SessionPath {}
        Mock -ModuleName AppRuntime Invoke-Pnpm {
            return @{ ExitCode = 0; Output = @('[{"path":"C:\\pnpm\\global\\5","private":false}]') }
        }

        $entry = [pscustomobject]@{ Id = '@openai/codex'; Origin = 'pnpm' }
        $res = Invoke-PnpmApp -Entry $entry -Check $true

        $res.Status | Should -Be '다름'
        $res.Detail | Should -Be '설치 안 됨'
    }

    It '9: PNPM_HOME 없음, -Check $false -> Set-UserEnv + Add-UserPath + add, 바꿈' {
        $savedPnpmHome = $env:PNPM_HOME
        try {
            $script:setEnvName = $null
            $script:setEnvValue = $null
            $script:addedPath = $null
            $script:calls = [System.Collections.Generic.List[string]]::new()

            Mock -ModuleName AppRuntime Get-UserEnv { return $null }
            Mock -ModuleName AppRuntime Set-UserEnv {
                $script:setEnvName = $Name
                $script:setEnvValue = $Value
            }
            Mock -ModuleName AppRuntime Add-UserPath {
                $script:addedPath = $Path
                return $true
            }
            Mock -ModuleName AppRuntime Update-SessionPath {}
            Mock -ModuleName AppRuntime Invoke-Pnpm {
                $script:calls.Add(($Arguments -join ' '))
                switch ($Arguments[0]) {
                    'ls'  { return @{ ExitCode = 0; Output = @('[{"path":"C:\\pnpm\\global\\5","private":false}]') } }
                    'add' { return @{ ExitCode = 0; Output = @() } }
                    default { throw "예상치 못한 호출: $($Arguments -join ' ')" }
                }
            }

            $expectedHome = [System.Environment]::ExpandEnvironmentVariables('%LOCALAPPDATA%\pnpm')
            $entry = [pscustomobject]@{ Id = '@openai/codex'; Origin = 'pnpm' }
            $res = Invoke-PnpmApp -Entry $entry -Check $false

            $res.Status | Should -Be '바꿈'
            $res.Detail | Should -Be ''
            $script:setEnvName | Should -Be 'PNPM_HOME'
            $script:setEnvValue | Should -Be $expectedHome
            $env:PNPM_HOME | Should -Be $expectedHome
            $script:addedPath | Should -Be $expectedHome
            $script:calls | Should -Contain 'add -g @openai/codex'
        } finally {
            $env:PNPM_HOME = $savedPnpmHome
        }
    }

    It '10: PNPM_HOME 없음, 패키지는 있음, -Check $false -> 환경만 맞추고 바꿈, add 안 불림' {
        $savedPnpmHome = $env:PNPM_HOME
        try {
            $script:calls = [System.Collections.Generic.List[string]]::new()

            Mock -ModuleName AppRuntime Get-UserEnv { return $null }
            Mock -ModuleName AppRuntime Set-UserEnv {}
            Mock -ModuleName AppRuntime Add-UserPath { return $true }
            Mock -ModuleName AppRuntime Update-SessionPath {}
            Mock -ModuleName AppRuntime Invoke-Pnpm {
                $script:calls.Add(($Arguments -join ' '))
                if ($Arguments[0] -eq 'ls') {
                    return @{ ExitCode = 0; Output = @('[{"path":"C:\\pnpm\\global\\5","private":false,"dependencies":{"@openai/codex":{"version":"1.0.0"}}}]') }
                }
                throw "예상치 못한 호출: $($Arguments -join ' ')"
            }

            $entry = [pscustomobject]@{ Id = '@openai/codex'; Origin = 'pnpm' }
            $res = Invoke-PnpmApp -Entry $entry -Check $false

            $res.Status | Should -Be '바꿈'
            $res.Detail | Should -Be ''
            $script:calls | Should -Not -Contain 'add -g @openai/codex'
        } finally {
            $env:PNPM_HOME = $savedPnpmHome
        }
    }

    It '11: pnpm 없음, -Check $false -> 실패: pnpm 이 없다' {
        Mock -ModuleName AppRuntime Get-UserEnv {
            param($Name)
            if ($Name -eq 'PNPM_HOME') { return 'C:\Users\test\AppData\Local\pnpm' }
            return $null
        }
        Mock -ModuleName AppRuntime Add-UserPath { return $false }
        Mock -ModuleName AppRuntime Update-SessionPath {}
        Mock -ModuleName AppRuntime Invoke-Pnpm { return @{ ExitCode = $null; Output = @() } }

        $entry = [pscustomobject]@{ Id = '@openai/codex'; Origin = 'pnpm' }
        $res = Invoke-PnpmApp -Entry $entry -Check $false

        $res.Status | Should -Be '실패'
        $res.Detail | Should -Be 'pnpm 이 없다'
    }

    It '12: pnpm add 종료 코드 1, -Check $false -> 실패' {
        Mock -ModuleName AppRuntime Get-UserEnv {
            param($Name)
            if ($Name -eq 'PNPM_HOME') { return 'C:\Users\test\AppData\Local\pnpm' }
            return $null
        }
        Mock -ModuleName AppRuntime Add-UserPath { return $false }
        Mock -ModuleName AppRuntime Update-SessionPath {}
        Mock -ModuleName AppRuntime Invoke-Pnpm {
            switch ($Arguments[0]) {
                'ls'  { return @{ ExitCode = 0; Output = @('[{"path":"C:\\pnpm\\global\\5","private":false}]') } }
                'add' { return @{ ExitCode = 1; Output = @('ERR_PNPM_FETCH_404') } }
            }
        }

        $entry = [pscustomobject]@{ Id = '@openai/codex'; Origin = 'pnpm' }
        $res = Invoke-PnpmApp -Entry $entry -Check $false

        $res.Status | Should -Be '실패'
        $res.Detail | Should -Be 'pnpm add -g @openai/codex 종료 코드 1'
    }
}

Describe 'Invoke-GoApp' {
    It '13: exe 있음 (-Check <Check>) -> 그대로' -ForEach @(
        @{ Check = $false }
        @{ Check = $true }
    ) {
        Mock -ModuleName AppRuntime Update-SessionPath {}
        Mock -ModuleName AppRuntime Invoke-Go {
            if ($Arguments[0] -eq 'env' -and $Arguments[1] -eq 'GOPATH') {
                return @{ ExitCode = 0; Output = @('C:\Users\test\go') }
            }
            throw "예상치 못한 호출: $($Arguments -join ' ')"
        }
        Mock -ModuleName AppRuntime Test-Path { return $true }

        $entry = [pscustomobject]@{ Id = 'golang.org/x/tools/gopls'; Origin = 'go' }
        $res = Invoke-GoApp -Entry $entry -Check $Check

        $res.Status | Should -Be '그대로'
        $res.Detail | Should -Be ''
    }

    It '14: exe 없음 (-Check <Check>) -> 다름 (설치 안 됨) / go install ...@latest, 바꿈' -ForEach @(
        @{ Check = $true;  ExpectedStatus = '다름'; ExpectedDetail = '설치 안 됨' }
        @{ Check = $false; ExpectedStatus = '바꿈'; ExpectedDetail = '' }
    ) {
        $script:installArgs = $null
        Mock -ModuleName AppRuntime Update-SessionPath {}
        Mock -ModuleName AppRuntime Invoke-Go {
            if ($Arguments[0] -eq 'env') {
                return @{ ExitCode = 0; Output = @('C:\Users\test\go') }
            }
            if ($Arguments[0] -eq 'install') {
                $script:installArgs = $Arguments
                return @{ ExitCode = 0; Output = @() }
            }
            throw "예상치 못한 호출: $($Arguments -join ' ')"
        }
        Mock -ModuleName AppRuntime Test-Path { return $false }

        $entry = [pscustomobject]@{ Id = 'golang.org/x/tools/gopls'; Origin = 'go' }
        $res = Invoke-GoApp -Entry $entry -Check $Check

        $res.Status | Should -Be $ExpectedStatus
        $res.Detail | Should -Be $ExpectedDetail
        if (-not $Check) {
            $script:installArgs | Should -Be @('install', 'golang.org/x/tools/gopls@latest')
        }
    }

    It '15: go 없음, -Check $false -> 실패: go 가 없다' {
        Mock -ModuleName AppRuntime Update-SessionPath {}
        Mock -ModuleName AppRuntime Invoke-Go { return @{ ExitCode = $null; Output = @() } }

        $entry = [pscustomobject]@{ Id = 'golang.org/x/tools/gopls'; Origin = 'go' }
        $res = Invoke-GoApp -Entry $entry -Check $false

        $res.Status | Should -Be '실패'
        $res.Detail | Should -Be 'go 가 없다'
    }

    It '16: Id honnef.co/go/tools/cmd/staticcheck (-Check <Check>) -> staticcheck.exe 를 본다' -ForEach @(
        @{ Check = $false }
        @{ Check = $true }
    ) {
        $script:checkedPath = $null
        Mock -ModuleName AppRuntime Update-SessionPath {}
        Mock -ModuleName AppRuntime Invoke-Go {
            return @{ ExitCode = 0; Output = @('C:\Users\test\go;C:\other\go') }
        }
        Mock -ModuleName AppRuntime Test-Path {
            $script:checkedPath = $LiteralPath
            return $true
        }

        $entry = [pscustomobject]@{ Id = 'honnef.co/go/tools/cmd/staticcheck'; Origin = 'go' }
        $res = Invoke-GoApp -Entry $entry -Check $Check

        $res.Status | Should -Be '그대로'
        $script:checkedPath | Should -Be (Join-Path 'C:\Users\test\go' 'bin' 'staticcheck.exe')
    }
}

Describe 'Update-SessionPath ordering' {
    It '17: 셋 다 명령을 찾기 전 Update-SessionPath 가 먼저 불림 (<Origin>, -Check <Check>)' -ForEach @(
        @{ Origin = 'nvm';  Check = $true }
        @{ Origin = 'nvm';  Check = $false }
        @{ Origin = 'pnpm'; Check = $true }
        @{ Origin = 'pnpm'; Check = $false }
        @{ Origin = 'go';   Check = $true }
        @{ Origin = 'go';   Check = $false }
    ) {
        $script:events = [System.Collections.Generic.List[string]]::new()
        Mock -ModuleName AppRuntime Update-SessionPath { $script:events.Add('Update-SessionPath') }
        Mock -ModuleName AppRuntime Get-UserEnv {
            param($Name)
            if ($Name -eq 'PNPM_HOME') { return 'C:\Users\test\AppData\Local\pnpm' }
            if ($Name -eq 'Path')      { return 'C:\Users\test\AppData\Local\pnpm' }
            return $null
        }
        Mock -ModuleName AppRuntime Add-UserPath { return $false }
        Mock -ModuleName AppRuntime Invoke-Nvm  { $script:events.Add('Invoke-Nvm');  return @{ ExitCode = $null; Output = @() } }
        Mock -ModuleName AppRuntime Invoke-Pnpm { $script:events.Add('Invoke-Pnpm'); return @{ ExitCode = $null; Output = @() } }
        Mock -ModuleName AppRuntime Invoke-Go   { $script:events.Add('Invoke-Go');   return @{ ExitCode = $null; Output = @() } }

        switch ($Origin) {
            'nvm' {
                $null = Invoke-NvmApp -Entry ([pscustomobject]@{ Id = 'node'; Origin = 'nvm'; NodeLine = '26' }) -Check $Check
                $script:events[0] | Should -Be 'Update-SessionPath'
                $script:events[1] | Should -Be 'Invoke-Nvm'
            }
            'pnpm' {
                $null = Invoke-PnpmApp -Entry ([pscustomobject]@{ Id = '@openai/codex'; Origin = 'pnpm' }) -Check $Check
                $script:events[0] | Should -Be 'Update-SessionPath'
                $script:events[1] | Should -Be 'Invoke-Pnpm'
            }
            'go' {
                $null = Invoke-GoApp -Entry ([pscustomobject]@{ Id = 'golang.org/x/tools/gopls'; Origin = 'go' }) -Check $Check
                $script:events[0] | Should -Be 'Update-SessionPath'
                $script:events[1] | Should -Be 'Invoke-Go'
            }
        }
    }
}
