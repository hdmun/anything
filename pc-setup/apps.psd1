@{
    Items = @(
        # Git
        @{ Id = 'Git.Git'; Scope = 'machine' }
        @{ Id = 'Microsoft.PowerShell'; Scope = 'machine' }
        @{ Id = 'GitHub.GitLFS'; Scope = 'machine' }
        @{ Id = 'GitHub.cli'; Scope = 'machine' }
        @{ Id = 'Fork.Fork'; Scope = 'user' }
        @{ Id = 'TortoiseGit.TortoiseGit'; Scope = 'machine' }

        # 터미널·편집기·IDE·DB
        @{ Id = 'Microsoft.WindowsTerminal'; Scope = 'user' }
        @{ Id = 'Microsoft.VisualStudioCode'; Scope = 'user' }
        @{ Id = 'Notepad++.Notepad++'; Scope = 'machine' }
        @{ Id = 'Microsoft.VisualStudio.Enterprise'; Scope = 'machine' }
        @{ Id = 'JetBrains.Rider'; Scope = 'machine' }
        @{ Id = 'Google.Antigravity'; Scope = 'user' }
        @{ Id = 'DBBrowserForSQLite.DBBrowserForSQLite'; Scope = 'machine' }
        @{ Id = 'qishibo.AnotherRedisDesktopManager'; Scope = 'machine' }
        @{ Id = 'StablyAI.Orca'; Scope = 'user' }

        # 유틸리티·도구
        @{ Id = '7zip.7zip'; Scope = 'machine' }
        @{ Id = 'voidtools.Everything'; Scope = 'machine' }
        @{ Id = 'Obsidian.Obsidian'; Scope = 'user' }
        @{ Id = 'Google.Chrome'; Scope = 'machine' }
        @{ Id = 'Discord.Discord'; Scope = 'user' }
        @{ Id = 'Google.AndroidStudio'; Scope = 'machine' }
        @{ Id = 'WinMerge.WinMerge'; Scope = 'machine' }

        # 언어·런타임
        @{ Id = 'Python.Python.3.13'; Scope = 'user'; Elevated = $true }
        @{ Id = 'RubyInstallerTeam.RubyWithDevKit.3.4'; Scope = 'user' }
        @{ Id = 'Oven-sh.Bun'; Scope = 'user' }
        @{ Id = 'GoLang.Go'; Scope = 'machine' }
        @{ Id = 'golang.org/x/tools/gopls'; Origin = 'go' }
        @{ Id = 'honnef.co/go/tools/cmd/staticcheck'; Origin = 'go' }

        # Microsoft Store
        @{ Id = 'XP8CBJ40XLBWKX'; WingetSource = 'msstore' }   # Docker Desktop
        @{ Id = '9PKTQ5699M62'; WingetSource = 'msstore' }   # iCloud

        # Scoop
        @{ Id = 'lazygit'; Origin = 'scoop'; Bucket = 'extras' }
        @{ Id = 'cmake'; Origin = 'scoop'; Bucket = 'main' }
        @{ Id = 'dbeaver'; Origin = 'scoop'; Bucket = 'extras' }
        @{ Id = 'nano'; Origin = 'scoop'; Bucket = 'main' }
        @{ Id = 'nvm'; Origin = 'scoop'; Bucket = 'main' }

        # Node·전역 패키지
        @{ Id = 'node'; Origin = 'nvm'; NodeLine = '26' }
        @{ Id = 'pnpm.pnpm'; Scope = 'user' }
        @{ Id = '@openai/codex'; Origin = 'pnpm' }

        # 공식 배포
        @{ Id = 'wsl'; Origin = 'official'; Elevated = $true }
        @{ Id = 'ubuntu-24.04'; Origin = 'official' }
    )
}
