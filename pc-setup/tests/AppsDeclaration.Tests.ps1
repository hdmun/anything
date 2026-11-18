BeforeAll {
    $setupModulePath = Join-Path $PSScriptRoot '..' 'lib' 'Setup.psm1'
    Import-Module $setupModulePath -Force
    $appsModulePath = Join-Path $PSScriptRoot '..' 'lib' 'Apps.psm1'
    Import-Module $appsModulePath -Force -Global
}

Describe '실제 앱 선언 (pc-setup/apps.psd1)' {
    BeforeAll {
        $script:pcSetupRoot = Join-Path $PSScriptRoot '..'
        $script:items = Get-AppItems -Root $script:pcSetupRoot
        $script:expectedIds = @(
            'Git.Git',
            'Microsoft.PowerShell',
            'GitHub.GitLFS',
            'GitHub.cli',
            'Fork.Fork',
            'TortoiseGit.TortoiseGit',
            'Microsoft.WindowsTerminal',
            'Microsoft.VisualStudioCode',
            'Notepad++.Notepad++',
            'Microsoft.VisualStudio.Enterprise',
            'JetBrains.Rider',
            'Google.Antigravity',
            'DBBrowserForSQLite.DBBrowserForSQLite',
            'qishibo.AnotherRedisDesktopManager',
            'StablyAI.Orca',
            '7zip.7zip',
            'voidtools.Everything',
            'Obsidian.Obsidian',
            'Google.Chrome',
            'Discord.Discord',
            'Google.AndroidStudio',
            'WinMerge.WinMerge',
            'Python.Python.3.13',
            'RubyInstallerTeam.RubyWithDevKit.3.4',
            'Oven-sh.Bun',
            'GoLang.Go',
            'golang.org/x/tools/gopls',
            'honnef.co/go/tools/cmd/staticcheck',
            'XP8CBJ40XLBWKX',
            '9PKTQ5699M62',
            'lazygit',
            'cmake',
            'dbeaver',
            'nano',
            'nvm',
            'node',
            'pnpm.pnpm',
            '@openai/codex'
        )
    }

    It '저장소 pc-setup/apps.psd1 로 Get-AppItems 가 예외 없이 38개를 돌려준다' {
        $script:items.Count | Should -Be 38
        foreach ($item in $script:items) {
            $item.Stage | Should -Be '앱'
        }
    }

    It 'Id 순서가 표 순서와 같다' {
        $actualIds = @($script:items | ForEach-Object { $_.Id })
        $actualIds | Should -Be $script:expectedIds
    }

    It 'Elevated 인 항목이 정확히 Scope = machine 인 16개와 Python.Python.3.13 이다' {
        $expectedElevatedIds = @(
            'Git.Git',
            'Microsoft.PowerShell',
            'GitHub.GitLFS',
            'GitHub.cli',
            'TortoiseGit.TortoiseGit',
            'Notepad++.Notepad++',
            'Microsoft.VisualStudio.Enterprise',
            'JetBrains.Rider',
            'DBBrowserForSQLite.DBBrowserForSQLite',
            'qishibo.AnotherRedisDesktopManager',
            '7zip.7zip',
            'voidtools.Everything',
            'Google.Chrome',
            'Google.AndroidStudio',
            'WinMerge.WinMerge',
            'Python.Python.3.13',
            'GoLang.Go'
        )
        $actualElevatedIds = @($script:items | Where-Object { $_.Elevated } | ForEach-Object { $_.Id })
        $actualElevatedIds.Count | Should -Be 17
        $actualElevatedIds | Should -Be $expectedElevatedIds
    }

    It '의존 순서: nvm < node < pnpm.pnpm < @openai/codex, GoLang.Go < 두 go 항목' {
        $ids = [System.Collections.Generic.List[string]]::new()
        foreach ($item in $script:items) {
            $ids.Add($item.Id)
        }

        $ids.IndexOf('nvm') | Should -BeLessThan $ids.IndexOf('node')
        $ids.IndexOf('node') | Should -BeLessThan $ids.IndexOf('pnpm.pnpm')
        $ids.IndexOf('pnpm.pnpm') | Should -BeLessThan $ids.IndexOf('@openai/codex')

        $goIdx = $ids.IndexOf('GoLang.Go')
        $goIdx | Should -BeLessThan $ids.IndexOf('golang.org/x/tools/gopls')
        $goIdx | Should -BeLessThan $ids.IndexOf('honnef.co/go/tools/cmd/staticcheck')
    }
}

Describe 'Setup 기본 단계 등록' {
    It 'Setup.psm1 의 기본 단계가 둘이고, 두 번째가 앱 단계다 (Windows 설정 -> 앱)' {
        $providersCount = InModuleScope Setup { $script:DefaultStageProviders.Count }
        $providersCount | Should -Be 2

        Mock -ModuleName Setup Get-WindowsSettingItems {
            @(@{
                Id       = 'FakeWinSetting'
                Stage    = 'Windows 설정'
                Elevated = $false
                Invoke   = { param($c) @{ Status = '그대로'; Detail = '' } }
            })
        }
        Mock -ModuleName Setup Get-AppItems {
            @(@{
                Id       = 'FakeApp'
                Stage    = '앱'
                Elevated = $false
                Invoke   = { param($c) @{ Status = '그대로'; Detail = '' } }
            })
        }

        $testRoot = (Get-Item 'TestDrive:/').FullName
        $resultFile = Join-Path $testRoot 'setup-stage-order.json'
        $exitCode = Invoke-Setup -Root $testRoot -Check -ResultPath $resultFile
        $exitCode | Should -Be 0

        $json = Get-Content -LiteralPath $resultFile -Raw | ConvertFrom-Json
        $json.Results.Count | Should -Be 2
        $json.Results[0].Stage | Should -Be 'Windows 설정'
        $json.Results[0].Id | Should -Be 'FakeWinSetting'
        $json.Results[1].Stage | Should -Be '앱'
        $json.Results[1].Id | Should -Be 'FakeApp'
    }
}
