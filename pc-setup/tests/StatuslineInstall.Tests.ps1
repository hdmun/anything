Describe 'statusline install.ps1 (claude·agy·codex)' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:claude = Join-Path $script:repoRoot 'claude-statusline' 'install.ps1'
        $script:agy = Join-Path $script:repoRoot 'agy-statusline' 'install.ps1'
        $script:codex = Join-Path $script:repoRoot 'codex-statusline' 'install.ps1'
        $script:utf8 = [System.Text.UTF8Encoding]::new($false)
        $script:caseCounter = 0

        function New-HomeDir([string[]]$Dirs) {
            $script:caseCounter++
            $homeDir = Join-Path (Get-Item 'TestDrive:/').FullName "home-$($script:caseCounter)"
            New-Item -ItemType Directory -Path $homeDir | Out-Null
            foreach ($d in $Dirs) { New-Item -ItemType Directory -Path (Join-Path $homeDir $d) -Force | Out-Null }
            return $homeDir
        }

        function Write-Text([string]$Path, [string]$Text) {
            [System.IO.File]::WriteAllText($Path, $Text, $script:utf8)
        }

        function Read-Text([string]$Path) { [System.IO.File]::ReadAllText($Path) }

        function Get-ExpectedCommand([string]$Tool) {
            "pwsh -NoProfile -File $((Join-Path $script:repoRoot "$Tool-statusline" 'statusline.ps1').Replace('\', '/'))"
        }

        $script:pythonPath = (& python -c 'import sys; print(sys.executable)').Trim().Replace('\', '/')
    }

    Context 'claude-statusline' {
        It '기존 값을 덮어쓰고 다른 키·키 순서를 보존하며, 두 번째 실행은 그대로다' {
            $homeDir = New-HomeDir @('.claude', '.agent-accounts/claude/a', '.agent-accounts/claude/b')
            $main = Join-Path $homeDir '.claude/settings.json'
            Write-Text $main "{`n  `"env`": {`n    `"A`": `"1`"`n  },`n  `"statusLine`": {`n    `"type`": `"command`",`n    `"command`": `"bash ~/.claude/statusline__.sh`",`n    `"padding`": 0`n  },`n  `"when`": `"2026-11-22T10:00:00Z`",`n  `"list`": [`n    `"x`"`n  ],`n  `"z`": true`n}`n"

            & $script:claude -HomeDir $homeDir -Check | Should -Be '다름 (~/.claude/settings.json, ~/.agent-accounts/claude/a/settings.json, ~/.agent-accounts/claude/b/settings.json)'
            Test-Path (Join-Path $homeDir '.agent-accounts/claude/a/settings.json') | Should -BeFalse

            & $script:claude -HomeDir $homeDir | Should -Be '바꿈 (~/.claude/settings.json, ~/.agent-accounts/claude/a/settings.json, ~/.agent-accounts/claude/b/settings.json)'
            & $script:claude -HomeDir $homeDir | Should -Be '그대로'
            & $script:claude -HomeDir $homeDir -Check | Should -Be '그대로'

            $cmd = Get-ExpectedCommand 'claude'
            $json = Read-Text $main
            $obj = $json | ConvertFrom-Json -DateKind String
            @($obj.PSObject.Properties.Name) | Should -Be @('env', 'statusLine', 'when', 'list', 'z')
            $obj.statusLine.type | Should -Be 'command'
            $obj.statusLine.command | Should -BeExactly $cmd
            $obj.statusLine.PSObject.Properties['padding'] | Should -BeNullOrEmpty
            $obj.when | Should -BeExactly '2026-11-22T10:00:00Z'
            @($obj.list) | Should -Be @('x')
            $obj.env.A | Should -Be '1'
            $json | Should -Not -Match "`r"
            $json | Should -Match "`n$"

            ((Read-Text (Join-Path $homeDir '.agent-accounts/claude/a/settings.json')) | ConvertFrom-Json).statusLine.command | Should -BeExactly $cmd
        }

        It '서브 계정 폴더는 settings.json 이나 .credentials.json 이 있을 때만 맞춘다' {
            $homeDir = New-HomeDir @('.claude', '.claude-x', '.claude-y', '.claude-z', '.agent-accounts/claude/a')
            Write-Text (Join-Path $homeDir '.claude-x/settings.json') "{`n  `"a`": 1`n}`n"
            Write-Text (Join-Path $homeDir '.claude-z/.credentials.json') "{}`n"
            Write-Text (Join-Path $homeDir '.claude-w.json') "{}`n"

            & $script:claude -HomeDir $homeDir -Check | Should -Be '다름 (~/.claude/settings.json, ~/.claude-x/settings.json, ~/.claude-z/settings.json, ~/.agent-accounts/claude/a/settings.json)'
            & $script:claude -HomeDir $homeDir | Should -Be '바꿈 (~/.claude/settings.json, ~/.claude-x/settings.json, ~/.claude-z/settings.json, ~/.agent-accounts/claude/a/settings.json)'
            & $script:claude -HomeDir $homeDir -Check | Should -Be '그대로'

            $cmd = Get-ExpectedCommand 'claude'
            $x = Read-Text (Join-Path $homeDir '.claude-x/settings.json') | ConvertFrom-Json
            @($x.PSObject.Properties.Name) | Should -Be @('a', 'statusLine')
            $x.statusLine.command | Should -BeExactly $cmd
            (Read-Text (Join-Path $homeDir '.claude-z/settings.json') | ConvertFrom-Json).statusLine.command | Should -BeExactly $cmd
            Test-Path (Join-Path $homeDir '.claude-y/settings.json') | Should -BeFalse
            Read-Text (Join-Path $homeDir '.claude-w.json') | Should -BeExactly "{}`n"
        }

        It 'CRLF 파일은 CRLF 로 쓰고, 링크면 링크 대상에 쓴다' {
            $homeDir = New-HomeDir @('.claude')
            $real = Join-Path $homeDir 'real-settings.json'
            $link = Join-Path $homeDir '.claude/settings.json'
            Write-Text $real "{`r`n  `"a`": 1`r`n}`r`n"
            try {
                New-Item -ItemType SymbolicLink -Path $link -Target $real -ErrorAction Stop | Out-Null
            } catch {
                Set-ItResult -Skipped -Because "심볼릭 링크를 만들 수 없다: $($_.Exception.Message)"
                return
            }

            & $script:claude -HomeDir $homeDir | Should -Be '바꿈 (~/.claude/settings.json)'
            (Get-Item -LiteralPath $link).LinkType | Should -Be 'SymbolicLink'
            $text = Read-Text $real
            $text | Should -Match "^\{`r`n  `"a`": 1,`r`n  `"statusLine`""
            ($text -replace "`r`n", '') | Should -Not -Match "`n"
        }

        It '깨진 JSON 은 실패: 이고 파일을 그대로 둔다. 폴더가 없으면 그대로다' {
            $homeDir = New-HomeDir @('.claude')
            $main = Join-Path $homeDir '.claude/settings.json'
            Write-Text $main '{ broken'
            & $script:claude -HomeDir $homeDir | Should -Match '^실패: ~/\.claude/settings\.json 의 JSON '
            Read-Text $main | Should -BeExactly '{ broken'

            & $script:claude -HomeDir (New-HomeDir @()) | Should -Be '그대로'
        }
    }

    Context 'agy-statusline' {
        It '기존 값을 덮어쓰고 다른 키를 보존하며, 두 번째 실행은 그대로다' {
            $homeDir = New-HomeDir @('.gemini/antigravity-cli')
            $path = Join-Path $homeDir '.gemini/antigravity-cli/settings.json'
            Write-Text $path "{`n  `"a`": 1,`n  `"statusLine`": {`n    `"type`": `"command`",`n    `"command`": `"python status.py`"`n  },`n  `"b`": [`n    `"C:\\x`"`n  ]`n}`n"

            & $script:agy -HomeDir $homeDir -Check | Should -Be '다름 (~/.gemini/antigravity-cli/settings.json)'
            & $script:agy -HomeDir $homeDir | Should -Be '바꿈 (~/.gemini/antigravity-cli/settings.json)'
            & $script:agy -HomeDir $homeDir -Check | Should -Be '그대로'

            $obj = Read-Text $path | ConvertFrom-Json
            @($obj.PSObject.Properties.Name) | Should -Be @('a', 'statusLine', 'b')
            $obj.statusLine.command | Should -BeExactly (Get-ExpectedCommand 'agy')
            @($obj.b) | Should -Be @('C:\x')
        }

        It '폴더가 있고 settings.json 이 없으면 만든다. ~/.gemini 만 있으면 건너뛴다' {
            $homeDir = New-HomeDir @('.gemini/antigravity-cli')
            & $script:agy -HomeDir $homeDir | Should -Be '바꿈 (~/.gemini/antigravity-cli/settings.json)'
            (Read-Text (Join-Path $homeDir '.gemini/antigravity-cli/settings.json') | ConvertFrom-Json).statusLine.type | Should -Be 'command'

            $only = New-HomeDir @('.gemini')
            & $script:agy -HomeDir $only | Should -Be '그대로'
            Test-Path (Join-Path $only '.gemini/antigravity-cli') | Should -BeFalse
        }
    }

    Context 'codex-statusline' {
        It '빈 폴더에 세 키와 복사본을 만들고, 두 번째 실행은 그대로다' {
            $homeDir = New-HomeDir @('.codex', '.agent-accounts/codex/a')

            & $script:codex -HomeDir $homeDir -Check | Should -Be '다름 (~/.codex/statusline/statusline.py, ~/.codex/config.toml, ~/.agent-accounts/codex/a/statusline/statusline.py, ~/.agent-accounts/codex/a/config.toml)'
            Test-Path (Join-Path $homeDir '.codex/config.toml') | Should -BeFalse

            & $script:codex -HomeDir $homeDir | Should -Match '^바꿈 \('
            & $script:codex -HomeDir $homeDir | Should -Be '그대로'
            & $script:codex -HomeDir $homeDir -Check | Should -Be '그대로'

            $pyPath = (Join-Path $homeDir '.agent-accounts/codex/a/statusline/statusline.py').Replace('\', '/')
            Read-Text (Join-Path $homeDir '.agent-accounts/codex/a/config.toml') | Should -BeExactly (@(
                    '[features]'
                    'tui_extensions_statusline = true'
                    ''
                    '[mcp_servers.codex-statusline]'
                    "command = `"$($script:pythonPath)`""
                    "args = [`"-u`", `"$pyPath`"]"
                    ''
                    '[tui]'
                    'status_line_provider = { server = "codex-statusline", tool = "statusline" }'
                    ''
                ) -join "`n")
            [System.IO.File]::ReadAllBytes($pyPath) | Should -Be ([System.IO.File]::ReadAllBytes((Join-Path $script:repoRoot 'codex-statusline/statusline.py')))
        }

        It '기존 표 안에 넣고, 다른 값은 덮어쓰며, 다른 키·주석·CRLF 를 보존한다' {
            $homeDir = New-HomeDir @('.codex')
            $config = Join-Path $homeDir '.codex/config.toml'
            Write-Text $config ((@(
                        'model = "gpt"'
                        ''
                        '[tui]'
                        '# 주석'
                        'terminal_title = ["app-name", "activity"]'
                        'status_line_provider = { server = "other", tool = "x" }'
                        ''
                        '[tui.model_availability_nux]'
                        '"gpt-5.5" = 4'
                        ''
                        '[features]'
                        'other = false'
                        'tui_extensions_statusline = false'
                        ''
                        '[mcp_servers.codex-statusline]'
                        'command = "old.exe"'
                        'args = ['
                        '  "-u",'
                        '  "old.py",'
                        ']'
                        'env = { A = "1" }'
                        ''
                        '[[skills]]'
                        'name = "s"'
                    ) -join "`r`n") + "`r`n")

            & $script:codex -HomeDir $homeDir | Should -Be '바꿈 (~/.codex/statusline/statusline.py, ~/.codex/config.toml)'
            & $script:codex -HomeDir $homeDir -Check | Should -Be '그대로'

            $pyPath = (Join-Path $homeDir '.codex/statusline/statusline.py').Replace('\', '/')
            Read-Text $config | Should -BeExactly ((@(
                        'model = "gpt"'
                        ''
                        '[tui]'
                        '# 주석'
                        'terminal_title = ["app-name", "activity"]'
                        'status_line_provider = { server = "codex-statusline", tool = "statusline" }'
                        ''
                        '[tui.model_availability_nux]'
                        '"gpt-5.5" = 4'
                        ''
                        '[features]'
                        'other = false'
                        'tui_extensions_statusline = true'
                        ''
                        '[mcp_servers.codex-statusline]'
                        "command = `"$($script:pythonPath)`""
                        "args = [`"-u`", `"$pyPath`"]"
                        'env = { A = "1" }'
                        ''
                        '[[skills]]'
                        'name = "s"'
                    ) -join "`r`n") + "`r`n")
        }

        It '표가 있고 키만 없으면 그 표의 끝에 넣는다' {
            $homeDir = New-HomeDir @('.codex')
            $config = Join-Path $homeDir '.codex/config.toml'
            Write-Text $config "[tui]`nterminal_title = []`n`n[x]`ny = 1`n"
            & $script:codex -HomeDir $homeDir | Out-Null
            (Read-Text $config) | Should -Match '(?s)^\[tui\]\nterminal_title = \[\]\nstatus_line_provider = \{ server = "codex-statusline", tool = "statusline" \}\n\n\[x\]\ny = 1\n'
        }

        It 'python 이 없으면 실패: 이고 아무것도 쓰지 않는다. 대상 폴더가 없으면 그대로다' {
            $homeDir = New-HomeDir @('.codex')
            & $script:codex -HomeDir $homeDir -Python 'no-such-python-xyz' | Should -Be '실패: no-such-python-xyz 을 실행하지 못했다 (Python 이 필요하다)'
            Test-Path (Join-Path $homeDir '.codex/config.toml') | Should -BeFalse
            Test-Path (Join-Path $homeDir '.codex/statusline') | Should -BeFalse

            & $script:codex -HomeDir (New-HomeDir @()) -Python 'no-such-python-xyz' | Should -Be '그대로'
        }
    }
}
