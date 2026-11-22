Describe 'agent-rules/install.ps1' {
    BeforeAll {
        $script:install = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' 'agent-rules' 'install.ps1')).Path
        $script:marker = '<!-- 생성 파일: 직접 고치지 않는다. 원본은 hdmun/anything 저장소의 agent-rules/global/ 이고 그 저장소 루트에서 pwsh -NoProfile -File agent-rules/install.ps1 로 다시 만든다 -->'
        $script:caseCounter = 0
        $script:utf8 = [System.Text.UTF8Encoding]::new($false)

        # 홈 폴더(.claude·.codex·.gemini)와 원본 폴더를 TestDrive 안에 만든다.
        function New-Case {
            param([hashtable]$Sources, [string[]]$ToolDirs = @('.claude', '.codex', '.gemini'))
            $script:caseCounter++
            $base = Join-Path (Get-Item 'TestDrive:/').FullName "case-$($script:caseCounter)"
            $homeDir = Join-Path $base 'home'
            $src = Join-Path $base 'global'
            New-Item -ItemType Directory -Path $homeDir, $src -Force | Out-Null
            foreach ($d in $ToolDirs) { New-Item -ItemType Directory -Path (Join-Path $homeDir $d) | Out-Null }
            foreach ($name in $Sources.Keys) {
                [System.IO.File]::WriteAllText((Join-Path $src $name), $Sources[$name], $script:utf8)
            }
            return [pscustomobject]@{ Home = $homeDir; Src = $src }
        }

        function Invoke-Install {
            param($Case, [switch]$Check, [switch]$Force)
            & $script:install -HomeDir $Case.Home -SourceDir $Case.Src -Check:$Check -Force:$Force
        }

        function Get-Target([string]$HomeDir, [string]$Rel) {
            $p = Join-Path $HomeDir $Rel
            if (Test-Path -LiteralPath $p) { return [System.IO.File]::ReadAllText($p) }
            return $null
        }

        $script:std = @{
            '10-all.md'                  = "## All`r`nall`r`n"
            '20-claude.claude.md'        = "## Claude`nclaude"
            '30-pair.codex.gemini.md'    = "## Pair`npair`n"
        }
    }

    It '접미사 조합: 없음은 3개 모두, .claude 는 Claude 만, .codex.gemini 는 Codex·Gemini 만 (LF, 끝 줄바꿈 정리)' {
        $case = New-Case -Sources $script:std

        Invoke-Install $case | Should -Be '바꿈 (CLAUDE.md, AGENTS.md, GEMINI.md)'

        Get-Target $case.Home '.claude/CLAUDE.md' | Should -BeExactly "$($script:marker)`n`n## All`nall`n`n## Claude`nclaude`n"
        Get-Target $case.Home '.codex/AGENTS.md' | Should -BeExactly "$($script:marker)`n`n## All`nall`n`n## Pair`npair`n"
        Get-Target $case.Home '.gemini/GEMINI.md' | Should -BeExactly "$($script:marker)`n`n## All`nall`n`n## Pair`npair`n"
    }

    It '모르는 조각이 있으면 실패: 를 출력하고 아무것도 쓰지 않는다' {
        $case = New-Case -Sources @{ '10-all.md' = "a`n"; '20-x.cladue.md' = "b`n" }

        $out = Invoke-Install $case
        $out | Should -Match '^실패: 20-x\.cladue\.md '
        Get-Target $case.Home '.claude/CLAUDE.md' | Should -BeNullOrEmpty
    }

    It '생성 표시 없음은 할 일: 이고 파일 그대로, -Force 는 덮어쓰고 .prev 를 남긴다' {
        $case = New-Case -Sources $script:std -ToolDirs @('.codex')
        $dest = Join-Path $case.Home '.codex/AGENTS.md'
        [System.IO.File]::WriteAllText($dest, "hand written`n")

        Invoke-Install $case | Should -Be '할 일: ~/.codex/AGENTS.md 에 생성 표시가 없다. 내용을 agent-rules/global/ 로 옮긴 뒤 -Force 로 다시 실행한다'
        [System.IO.File]::ReadAllText($dest) | Should -BeExactly "hand written`n"

        Invoke-Install $case -Force | Should -Be '바꿈 (AGENTS.md)'
        [System.IO.File]::ReadAllText($dest) | Should -Match '^<!-- 생성 파일'
        [System.IO.File]::ReadAllText("$dest.prev") | Should -BeExactly "hand written`n"
    }

    It '생성 표시가 없어도 비어 있거나 본문이 같으면 덮어쓰고 .prev 를 남기지 않는다' {
        $case = New-Case -Sources $script:std -ToolDirs @('.claude', '.gemini')
        $claude = Join-Path $case.Home '.claude/CLAUDE.md'
        $gemini = Join-Path $case.Home '.gemini/GEMINI.md'
        [System.IO.File]::WriteAllText($claude, " `r`n`t`n")
        [System.IO.File]::WriteAllText($gemini, "`r`n## All`r`nall`r`n`r`n## Pair`r`npair  `r`n`r`n")

        Invoke-Install $case | Should -Be '바꿈 (CLAUDE.md, GEMINI.md)'
        [System.IO.File]::ReadAllText($claude) | Should -Match '^<!-- 생성 파일'
        [System.IO.File]::ReadAllText($gemini) | Should -Match '^<!-- 생성 파일'
        Test-Path "$claude.prev" | Should -BeFalse
        Test-Path "$gemini.prev" | Should -BeFalse
    }

    It '대상이 심볼릭 링크면 쓴 뒤에도 링크이고 링크 대상 파일이 바뀐다' {
        $case = New-Case -Sources $script:std -ToolDirs @('.claude')
        $real = Join-Path $case.Home 'real-CLAUDE.md'
        $link = Join-Path $case.Home '.claude/CLAUDE.md'
        [System.IO.File]::WriteAllText($real, "$($script:marker)`nold`n")
        try {
            New-Item -ItemType SymbolicLink -Path $link -Target $real -ErrorAction Stop | Out-Null
        } catch {
            Set-ItResult -Skipped -Because "심볼릭 링크를 만들 수 없다: $($_.Exception.Message)"
            return
        }

        Invoke-Install $case | Should -Be '바꿈 (CLAUDE.md)'

        (Get-Item -LiteralPath $link).LinkType | Should -Be 'SymbolicLink'
        [System.IO.File]::ReadAllText($real) | Should -BeExactly "$($script:marker)`n`n## All`nall`n`n## Claude`nclaude`n"
    }

    It '한 줄 결과는 실패 > 할 일 > 다름 순서이고 -Check 는 아무것도 쓰지 않는다' {
        $case = New-Case -Sources $script:std
        $codex = Join-Path $case.Home '.codex/AGENTS.md'
        $gemini = Join-Path $case.Home '.gemini/GEMINI.md'
        [System.IO.File]::WriteAllText($codex, "hand`n")
        [System.IO.File]::WriteAllText($gemini, "hand2`n")

        Invoke-Install $case -Check | Should -Be '할 일: ~/.codex/AGENTS.md 에 생성 표시가 없다. 내용을 agent-rules/global/ 로 옮긴 뒤 -Force 로 다시 실행한다'
        Invoke-Install $case -Check -Force | Should -Be '다름 (CLAUDE.md, AGENTS.md, GEMINI.md)'
        Test-Path (Join-Path $case.Home '.claude/CLAUDE.md') | Should -BeFalse
        [System.IO.File]::ReadAllText($codex) | Should -BeExactly "hand`n"
        Test-Path "$codex.prev" | Should -BeFalse

        # 쓸 수 없는 대상(같은 이름의 폴더)은 실패가 할 일보다 앞선다
        New-Item -ItemType Directory -Path (Join-Path $case.Home '.claude/CLAUDE.md') | Out-Null
        Invoke-Install $case | Should -Match '^실패: ~/\.claude/CLAUDE\.md '
    }

    It '두 번째 실행은 그대로이고, 없는 도구 폴더는 만들지 않는다' {
        $case = New-Case -Sources $script:std -ToolDirs @('.claude', '.codex')

        Invoke-Install $case | Should -Be '바꿈 (CLAUDE.md, AGENTS.md)'
        Invoke-Install $case | Should -Be '그대로'
        Invoke-Install $case -Check | Should -Be '그대로'
        Test-Path (Join-Path $case.Home '.gemini') | Should -BeFalse
    }

    It '자식 pwsh -File 의 한 줄이 콘솔 코드 페이지(CP949)와 상관없이 BOM 없는 UTF-8 이다' {
        $case = New-Case -Sources $script:std -ToolDirs @('.claude')
        $saved = [Console]::OutputEncoding
        try {
            [Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding(949)
            $psi = [System.Diagnostics.ProcessStartInfo]::new('pwsh')
            foreach ($a in @('-NoProfile', '-File', $script:install, '-Check', '-HomeDir', $case.Home, '-SourceDir', $case.Src)) {
                $psi.ArgumentList.Add($a)
            }
            $psi.RedirectStandardOutput = $true
            $psi.UseShellExecute = $false
            $proc = [System.Diagnostics.Process]::Start($psi)
            $ms = [System.IO.MemoryStream]::new()
            $proc.StandardOutput.BaseStream.CopyTo($ms)
            $proc.WaitForExit()
        } finally {
            [Console]::OutputEncoding = $saved
        }
        $ms.ToArray() | Should -Be ([System.Text.UTF8Encoding]::new($false).GetBytes("다름 (CLAUDE.md)`r`n"))
    }
}
