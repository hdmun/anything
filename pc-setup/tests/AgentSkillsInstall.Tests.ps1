Describe 'agent-skills/install.ps1' {
    BeforeAll {
        $script:repoSkills = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' 'agent-skills')).Path
        $script:install = Join-Path $script:repoSkills 'install.ps1'
        $script:caseCounter = 0
        $script:utf8 = [System.Text.UTF8Encoding]::new($false)

        function Write-TextFile([string]$Path, [string]$Text) {
            $parent = Split-Path -Parent $Path
            if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            [System.IO.File]::WriteAllText($Path, $Text, $script:utf8)
        }

        # 홈 폴더(.claude·.agents)와 원본 폴더를 TestDrive 안에 만든다.
        # Sources: '<묶음>/<스킬>/<상대 경로>' → 내용
        function New-Case {
            param([hashtable]$Sources = @{}, [string[]]$ToolDirs = @('.claude', '.agents'))
            $script:caseCounter++
            $base = Join-Path (Get-Item 'TestDrive:/').FullName "case-$($script:caseCounter)"
            $homeDir = Join-Path $base 'home'
            $src = Join-Path $base 'src'
            New-Item -ItemType Directory -Path $homeDir, $src -Force | Out-Null
            foreach ($d in $ToolDirs) { New-Item -ItemType Directory -Path (Join-Path $homeDir $d) | Out-Null }
            foreach ($rel in $Sources.Keys) { Write-TextFile (Join-Path $src $rel) $Sources[$rel] }
            return [pscustomobject]@{ Base = $base; Home = $homeDir; Src = $src }
        }

        function Invoke-Install {
            param($Case, [switch]$Check, [switch]$Force, [string]$SourceDir)
            $s = if ($SourceDir) { $SourceDir } else { $Case.Src }
            & $script:install -HomeDir $Case.Home -SourceDir $s -Check:$Check -Force:$Force
        }

        # 폴더 안 파일 목록과 내용(상대 경로 → 내용)을 돌려준다. 비교용 스냅숏이다.
        function Get-Snapshot([string]$Dir) {
            if (-not (Test-Path -LiteralPath $Dir)) { return '<없음>' }
            $root = (Get-Item -LiteralPath $Dir -Force).FullName.TrimEnd('\')
            $lines = foreach ($f in Get-ChildItem -LiteralPath $Dir -Recurse -Force | Sort-Object FullName) {
                $rel = $f.FullName.Substring($root.Length + 1)
                if ($f.LinkType) { "$rel -> link"; continue }
                if ($f.PSIsContainer) { "$rel/"; continue }
                "$rel = $([System.IO.File]::ReadAllText($f.FullName))"
            }
            return ($lines -join "`n")
        }

        function Get-HomeSnapshot($Case) { return Get-Snapshot $Case.Base }

        $script:one = @{
            'claude/demo/SKILL.md'        = "# demo`n"
            'claude/demo/scripts/run.py'  = "print(1)`n"
        }
        $script:demoDest = { param($Case) Join-Path $Case.Home '.claude/skills/demo' }
    }

    It '1. 없음: -Check 는 다름이고 아무것도 만들지 않는다, 맞춤은 복사하고 표시를 쓴다' {
        $case = New-Case -Sources $script:one
        $before = Get-HomeSnapshot $case

        Invoke-Install $case -Check | Should -Be '다름 (~/.claude/skills/demo)'
        Get-HomeSnapshot $case | Should -Be $before

        Invoke-Install $case | Should -Be '바꿈 (~/.claude/skills/demo)'
        $dest = & $script:demoDest $case
        [System.IO.File]::ReadAllText((Join-Path $dest 'SKILL.md')) | Should -BeExactly "# demo`n"
        [System.IO.File]::ReadAllText((Join-Path $dest 'scripts/run.py')) | Should -BeExactly "print(1)`n"
        [System.IO.File]::ReadAllText((Join-Path $dest '.agent-skills')) | Should -BeExactly "생성 폴더: 직접 고치지 않는다. 원본은 hdmun/anything 저장소의 agent-skills/claude/demo/ 이고 그 저장소 루트에서 pwsh -NoProfile -File agent-skills/install.ps1 로 다시 만든다`n"

        Invoke-Install $case | Should -Be '그대로'
    }

    It '2. junction: 링크만 지우고 복사하며, 가리키던 폴더의 파일은 남는다 (-Check 는 그대로 둔다)' {
        $case = New-Case -Sources $script:one
        $elsewhere = Join-Path $case.Base 'elsewhere'
        Write-TextFile (Join-Path $elsewhere 'SKILL.md') "keep`n"
        New-Item -ItemType Directory -Path (Join-Path $case.Home '.claude/skills') | Out-Null
        $dest = & $script:demoDest $case
        New-Item -ItemType Junction -Path $dest -Target $elsewhere | Out-Null
        $before = Get-HomeSnapshot $case

        Invoke-Install $case -Check | Should -Be '다름 (~/.claude/skills/demo)'
        Get-HomeSnapshot $case | Should -Be $before

        Invoke-Install $case | Should -Be '바꿈 (~/.claude/skills/demo)'
        (Get-Item -LiteralPath $dest -Force).LinkType | Should -BeNullOrEmpty
        [System.IO.File]::ReadAllText((Join-Path $dest 'SKILL.md')) | Should -BeExactly "# demo`n"
        [System.IO.File]::ReadAllText((Join-Path $elsewhere 'SKILL.md')) | Should -BeExactly "keep`n"
        Invoke-Install $case | Should -Be '그대로'
    }

    It '2. 디렉터리 심볼릭 링크: 링크만 지우고 복사하며, 가리키던 폴더의 파일은 남는다' {
        $case = New-Case -Sources $script:one
        $elsewhere = Join-Path $case.Base 'elsewhere'
        Write-TextFile (Join-Path $elsewhere 'SKILL.md') "keep`n"
        New-Item -ItemType Directory -Path (Join-Path $case.Home '.claude/skills') | Out-Null
        $dest = & $script:demoDest $case
        New-Item -ItemType SymbolicLink -Path $dest -Target $elsewhere | Out-Null
        $before = Get-HomeSnapshot $case

        Invoke-Install $case -Check | Should -Be '다름 (~/.claude/skills/demo)'
        Get-HomeSnapshot $case | Should -Be $before

        Invoke-Install $case | Should -Be '바꿈 (~/.claude/skills/demo)'
        (Get-Item -LiteralPath $dest -Force).LinkType | Should -BeNullOrEmpty
        [System.IO.File]::ReadAllText((Join-Path $dest 'SKILL.md')) | Should -BeExactly "# demo`n"
        [System.IO.File]::ReadAllText((Join-Path $elsewhere 'SKILL.md')) | Should -BeExactly "keep`n"
    }

    It '3·4. 표시 있음: 내용 같으면 그대로, 내용 다르면 다름/바꿈' {
        $case = New-Case -Sources $script:one
        Invoke-Install $case | Should -Be '바꿈 (~/.claude/skills/demo)'
        $dest = & $script:demoDest $case
        Invoke-Install $case -Check | Should -Be '그대로'

        Write-TextFile (Join-Path $dest 'SKILL.md') "# edited`n"
        $before = Get-HomeSnapshot $case
        Invoke-Install $case -Check | Should -Be '다름 (~/.claude/skills/demo)'
        Get-HomeSnapshot $case | Should -Be $before

        Invoke-Install $case | Should -Be '바꿈 (~/.claude/skills/demo)'
        [System.IO.File]::ReadAllText((Join-Path $dest 'SKILL.md')) | Should -BeExactly "# demo`n"
        Test-Path -LiteralPath (Join-Path $case.Home '.claude/skills.prev') | Should -BeFalse
        Invoke-Install $case | Should -Be '그대로'
    }

    It '4. 표시 있음, 정본에 없는 파일이 더 있으면 맞춘 뒤 그 파일은 없다' {
        $case = New-Case -Sources $script:one
        Invoke-Install $case | Out-Null
        $dest = & $script:demoDest $case
        Write-TextFile (Join-Path $dest 'extra/notes.md') "x`n"

        Invoke-Install $case -Check | Should -Be '다름 (~/.claude/skills/demo)'
        Invoke-Install $case | Should -Be '바꿈 (~/.claude/skills/demo)'
        Test-Path -LiteralPath (Join-Path $dest 'extra') | Should -BeFalse
        Invoke-Install $case | Should -Be '그대로'
    }

    It '4. 표시 있음, 정본의 파일 하나가 빠졌으면 다시 채운다' {
        $case = New-Case -Sources $script:one
        Invoke-Install $case | Out-Null
        $dest = & $script:demoDest $case
        Remove-Item -LiteralPath (Join-Path $dest 'scripts/run.py')

        Invoke-Install $case -Check | Should -Be '다름 (~/.claude/skills/demo)'
        Invoke-Install $case | Should -Be '바꿈 (~/.claude/skills/demo)'
        Test-Path -LiteralPath (Join-Path $dest 'scripts/run.py') | Should -BeTrue
    }

    It '5. 표시 없음, 내용 같음(줄바꿈만 다름): 다름 → 표시만 쓰고 파일은 그대로 둔다' {
        $case = New-Case -Sources @{ 'claude/demo/SKILL.md' = "# demo`r`nline`r`n" }
        $dest = & $script:demoDest $case
        Write-TextFile (Join-Path $dest 'SKILL.md') "# demo`nline`n"
        $before = Get-HomeSnapshot $case

        Invoke-Install $case -Check | Should -Be '다름 (~/.claude/skills/demo)'
        Get-HomeSnapshot $case | Should -Be $before

        Invoke-Install $case | Should -Be '바꿈 (~/.claude/skills/demo)'
        [System.IO.File]::ReadAllText((Join-Path $dest 'SKILL.md')) | Should -BeExactly "# demo`nline`n"
        Test-Path -LiteralPath (Join-Path $dest '.agent-skills') -PathType Leaf | Should -BeTrue
        Invoke-Install $case | Should -Be '그대로'
    }

    It '줄바꿈만 다름(정본 LF, 대상 CRLF, 표시 있음)은 내용 같음이다' {
        $case = New-Case -Sources @{ 'claude/demo/SKILL.md' = "a`nb`n" }
        Invoke-Install $case | Out-Null
        $dest = & $script:demoDest $case
        Write-TextFile (Join-Path $dest 'SKILL.md') "a`r`nb`r`n"

        Invoke-Install $case -Check | Should -Be '그대로'
    }

    It '6. 표시 없음, 내용 다름: -Check·맞춤 모두 할 일이고 아무것도 바꾸지 않는다' {
        $case = New-Case -Sources $script:one
        $dest = & $script:demoDest $case
        Write-TextFile (Join-Path $dest 'SKILL.md') "# mine`n"
        $before = Get-HomeSnapshot $case
        $todo = '할 일: ~/.claude/skills/demo 에 생성 표시가 없고 내용이 다르다. 손으로 고친 내용을 agent-skills/claude/demo/ 로 옮긴 뒤 -Force 로 다시 실행한다'

        Invoke-Install $case -Check | Should -Be $todo
        Invoke-Install $case -Check -Force | Should -Be $todo
        Invoke-Install $case | Should -Be $todo
        Get-HomeSnapshot $case | Should -Be $before
    }

    It '6. -Force: skills.prev 아래로 옮긴 뒤 복사한다, 이전 백업이 있으면 바꾼다' {
        $case = New-Case -Sources $script:one
        $dest = & $script:demoDest $case
        $backup = Join-Path $case.Home '.claude/skills.prev/demo'
        Write-TextFile (Join-Path $backup 'old.md') "older`n"
        Write-TextFile (Join-Path $dest 'SKILL.md') "# mine`n"

        Invoke-Install $case -Force | Should -Be '바꿈 (~/.claude/skills/demo)'
        [System.IO.File]::ReadAllText((Join-Path $backup 'SKILL.md')) | Should -BeExactly "# mine`n"
        Test-Path -LiteralPath (Join-Path $backup 'old.md') | Should -BeFalse
        [System.IO.File]::ReadAllText((Join-Path $dest 'SKILL.md')) | Should -BeExactly "# demo`n"
        Invoke-Install $case | Should -Be '그대로'
    }

    It '7. 스킬 자리에 파일이 있으면 -Check·맞춤 모두 실패다' {
        $case = New-Case -Sources $script:one
        Write-TextFile (& $script:demoDest $case) "file`n"

        Invoke-Install $case -Check | Should -Be '실패: ~/.claude/skills/demo 자리에 파일이 있다'
        Invoke-Install $case | Should -Be '실패: ~/.claude/skills/demo 자리에 파일이 있다'
    }

    It '실패·할 일이 있어도 다른 대상은 맞춘다' {
        $case = New-Case -Sources @{
            'claude/aaa/SKILL.md' = "a`n"
            'claude/bbb/SKILL.md' = "b`n"
        }
        Write-TextFile (Join-Path $case.Home '.claude/skills/aaa') "file`n"

        Invoke-Install $case | Should -Be '실패: ~/.claude/skills/aaa 자리에 파일이 있다'
        Test-Path -LiteralPath (Join-Path $case.Home '.claude/skills/bbb/SKILL.md') | Should -BeTrue
    }

    It 'shared 는 두 대상에, 처리 순서는 shared → claude → agents, 대상은 .claude → .agents 다' {
        $case = New-Case -Sources @{
            'agents/zeta/SKILL.md'  = "z`n"
            'claude/beta/SKILL.md'  = "b`n"
            'shared/alpha/SKILL.md' = "a`n"
        }
        Invoke-Install $case | Should -Be '바꿈 (~/.claude/skills/alpha, ~/.agents/skills/alpha, ~/.claude/skills/beta, ~/.agents/skills/zeta)'
        Test-Path -LiteralPath (Join-Path $case.Home '.agents/skills/beta') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $case.Home '.claude/skills/zeta') | Should -BeFalse
    }

    It '.agents 가 없으면 .agents 대상만 건너뛴다' {
        $case = New-Case -Sources @{ 'shared/alpha/SKILL.md' = "a`n" } -ToolDirs @('.claude')

        Invoke-Install $case | Should -Be '바꿈 (~/.claude/skills/alpha)'
        Test-Path -LiteralPath (Join-Path $case.Home '.agents') | Should -BeFalse
    }

    It '대상 폴더가 하나도 없으면 그대로다' {
        $case = New-Case -Sources $script:one -ToolDirs @()
        Invoke-Install $case | Should -Be '그대로'
    }

    It '.claude 는 있고 skills 가 없으면 -Check 는 만들지 않고, 맞춤은 만든다' {
        $case = New-Case -Sources $script:one
        Invoke-Install $case -Check | Should -Be '다름 (~/.claude/skills/demo)'
        Test-Path -LiteralPath (Join-Path $case.Home '.claude/skills') | Should -BeFalse

        Invoke-Install $case | Should -Be '바꿈 (~/.claude/skills/demo)'
        Test-Path -LiteralPath (Join-Path $case.Home '.claude/skills/demo/SKILL.md') | Should -BeTrue
    }

    It '같은 스킬이 shared 와 claude 에 함께 있으면 실패이고 아무것도 쓰지 않는다' {
        $case = New-Case -Sources @{
            'shared/dup/SKILL.md'   = "s`n"
            'claude/dup/SKILL.md'   = "c`n"
            'agents/other/SKILL.md' = "o`n"
        }
        $before = Get-HomeSnapshot $case

        Invoke-Install $case | Should -Be '실패: dup 이 shared, claude 에 함께 있다'
        Get-HomeSnapshot $case | Should -Be $before
    }

    It '원본 폴더가 없으면 실패다' {
        $case = New-Case
        $missing = Join-Path $case.Base 'nope'
        Invoke-Install $case -SourceDir $missing | Should -Be "실패: 원본 폴더 $missing 가 없다"
    }

    It '묶음 아래의 파일과 묶음이 아닌 폴더는 무시한다' {
        $case = New-Case -Sources @{
            'claude/README.md'      = "readme`n"
            'other/skip/SKILL.md'   = "x`n"
            'claude/demo/SKILL.md'  = "# demo`n"
        }
        Invoke-Install $case | Should -Be '바꿈 (~/.claude/skills/demo)'
        Test-Path -LiteralPath (Join-Path $case.Home '.claude/skills/README.md') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $case.Home '.claude/skills/skip') | Should -BeFalse
    }

    It '저장소의 실제 agent-skills/ 로 빈 홈에 맞추면 네 대상을 만들고, 두 번째는 그대로다' {
        $case = New-Case
        Invoke-Install $case -SourceDir $script:repoSkills | Should -Be '바꿈 (~/.claude/skills/orca-handoff, ~/.agents/skills/orca-handoff, ~/.claude/skills/rename-session, ~/.agents/skills/rename-session)'
        Invoke-Install $case -SourceDir $script:repoSkills | Should -Be '그대로'
    }

    It 'pwsh -File 로 실행해도 표준 출력이 한 줄이다' {
        $case = New-Case -Sources $script:one
        $saved = [Console]::OutputEncoding
        try {
            [Console]::OutputEncoding = $script:utf8
            $out = @(& pwsh -NoProfile -File $script:install -HomeDir $case.Home -SourceDir $case.Src -Check)
        } finally {
            [Console]::OutputEncoding = $saved
        }
        $out.Count | Should -Be 1
        $out[0] | Should -Be '다름 (~/.claude/skills/demo)'
    }
}
