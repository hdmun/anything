BeforeAll {
    $script:pcSetupDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path

    function Get-MarkdownTables {
        # md 파일의 표를 읽는다 → @( @{ Header = [string[]]; Rows = @([string[]], ...) }, ... )
        # 연속한 '|' 줄 묶음 하나가 표 하나다. 둘째 줄(구분 줄)은 건너뛴다.
        param([Parameter(Mandatory)][string]$Path)

        $tables = [System.Collections.Generic.List[object]]::new()
        $block = [System.Collections.Generic.List[string]]::new()
        $lines = @(Get-Content -LiteralPath $Path -Encoding UTF8) + @('')
        foreach ($line in $lines) {
            if ($line -match '^\s*\|') {
                $block.Add($line.Trim())
                continue
            }
            if ($block.Count -gt 0) {
                $cells = @($block | ForEach-Object {
                        , [string[]]@(($_.Trim('|') -split '\|') | ForEach-Object { $_.Trim() })
                    })
                $rows = [System.Collections.Generic.List[object]]::new()
                for ($i = 2; $i -lt $cells.Count; $i++) {
                    $rows.Add($cells[$i])
                }
                $tables.Add(@{ Header = $cells[0]; Rows = $rows.ToArray() })
                $block.Clear()
            }
        }
        return , $tables.ToArray()
    }

    function Get-RelativeLinkProblems {
        # md 파일의 상대 링크 가운데 가리키는 파일이 없는 것 → [string[]]
        param([Parameter(Mandatory)][string]$Path)

        $docDir = Split-Path -Path $Path -Parent
        $content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        $problems = [System.Collections.Generic.List[string]]::new()
        foreach ($m in [regex]::Matches($content, '\]\(([^)]+)\)')) {
            $target = $m.Groups[1].Value.Trim()
            if ($target -match '^[a-zA-Z][a-zA-Z0-9+.-]*:') {
                continue
            }
            $pathOnly = ($target -replace '#.*$', '').Trim()
            if ([string]::IsNullOrEmpty($pathOnly)) {
                continue
            }
            if (-not (Test-Path -LiteralPath (Join-Path $docDir $pathOnly))) {
                $problems.Add($target)
            }
        }
        return , [string[]]$problems.ToArray()
    }
}

Describe '선언 md 4개' {
    It '<File> 에 표가 있고, 모든 표가 정해진 칸을 쓰며 줄마다 칸 수가 같다' -ForEach @(
        @{ File = 'apps.md'; Columns = @('앱', '원천', '원천 힌트', '범위', '버전 줄', '승격', '왜') }
        @{ File = 'config-files.md'; Columns = @('설정 파일', '원래 자리', '거는 방법', '저장소 정본') }
        @{ File = 'windows-settings.md'; Columns = @('설정', '원하는 상태', '승격', '왜') }
        @{ File = 'repo-tools.md'; Columns = @('도구', '저장소 위치', '승격') }
    ) {
        $path = Join-Path $script:pcSetupDir $File
        Test-Path -LiteralPath $path -PathType Leaf | Should -BeTrue

        $tables = Get-MarkdownTables -Path $path
        $tables.Count | Should -BeGreaterThan 0
        foreach ($table in $tables) {
            ($table.Header -join ' | ') | Should -Be ($Columns -join ' | ')
            $table.Rows.Count | Should -BeGreaterThan 0
            foreach ($row in $table.Rows) {
                $row.Count | Should -Be $Columns.Count -Because "$File 의 줄 '$($row -join ' | ')' 칸 수"
                [string]::IsNullOrWhiteSpace($row[0]) | Should -BeFalse -Because "$File 의 첫 칸(항목 이름)은 비지 않는다"
            }
        }
    }

    It '<File> 에 http URL 이 없다 (선언에는 "어떻게"를 적지 않는다)' -ForEach @(
        @{ File = 'apps.md' }
        @{ File = 'config-files.md' }
        @{ File = 'windows-settings.md' }
        @{ File = 'repo-tools.md' }
    ) {
        $content = Get-Content -LiteralPath (Join-Path $script:pcSetupDir $File) -Raw -Encoding UTF8
        $content | Should -Not -Match '(?i)https?://'
    }

    It 'repo-tools.md 의 저장소 위치마다 install.ps1 이 있다' {
        $tables = Get-MarkdownTables -Path (Join-Path $script:pcSetupDir 'repo-tools.md')
        $locationIndex = [Array]::IndexOf($tables[0].Header, '저장소 위치')
        foreach ($table in $tables) {
            foreach ($row in $table.Rows) {
                $location = $row[$locationIndex].Trim('`').Trim()
                $installPath = Join-Path $script:repoRoot $location 'install.ps1'
                Test-Path -LiteralPath $installPath -PathType Leaf | Should -BeTrue -Because "$location 에 install.ps1 이 있어야 한다"
            }
        }
    }
}

Describe '셋업 문서의 상대 링크' {
    It '<File> 의 상대 링크가 가리키는 파일이 모두 있다' -ForEach @(
        @{ File = 'SETUP.md' }
        @{ File = 'README.md' }
        @{ File = 'apps.md' }
        @{ File = 'config-files.md' }
        @{ File = 'windows-settings.md' }
        @{ File = 'repo-tools.md' }
        @{ File = 'dev-tools.md' }
    ) {
        $path = Join-Path $script:pcSetupDir $File
        Test-Path -LiteralPath $path -PathType Leaf | Should -BeTrue
        $problems = Get-RelativeLinkProblems -Path $path
        $problems | Should -BeNullOrEmpty -Because "$File 의 깨진 상대 링크: $($problems -join ', ')"
    }
}

Describe 'Declarations.Tests 의 검사 함수' {
    It '깨진 상대 링크와 URL 을 구분한다' {
        $doc = Join-Path $TestDrive 'doc.md'
        Set-Content -LiteralPath (Join-Path $TestDrive 'there.md') -Value 'x' -Encoding UTF8
        Set-Content -LiteralPath $doc -Encoding UTF8 -Value @(
            '[있음](there.md) [없음](missing.md) [절](#anchor) [밖](https://example.com/a)'
        )
        $problems = Get-RelativeLinkProblems -Path $doc
        $problems | Should -Be @('missing.md')
    }

    It '표 두 개를 나눠 읽고, 칸 수가 다른 줄을 그대로 돌려준다' {
        $doc = Join-Path $TestDrive 'tables.md'
        Set-Content -LiteralPath $doc -Encoding UTF8 -Value @(
            '| a | b |'
            '|---|---|'
            '| 1 | |'
            ''
            '| c |'
            '|---|'
            '| 2 | 3 |'
        )
        $tables = Get-MarkdownTables -Path $doc
        $tables.Count | Should -Be 2
        $tables[0].Header | Should -Be @('a', 'b')
        $tables[0].Rows[0] | Should -Be @('1', '')
        $tables[1].Rows[0].Count | Should -Be 2
    }
}
