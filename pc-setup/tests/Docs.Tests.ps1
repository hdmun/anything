Describe 'Hyper-V VM 검증 체크리스트 문서' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:docPath = Join-Path $script:repoRoot 'pc-setup' 'test' 'vm-checklist.md'
        $script:expectedHeadings = @(
            '언제'
            '1. 이미지 준비 (처음 한 번)'
            '2. 부트스트랩'
            '3. 재부팅과 셋업 다시 실행'
            '4. 확인'
            '5. 재실행 (멱등)'
            '6. 결과 기록'
        )
    }

    It 'pc-setup/test/vm-checklist.md 가 있고 ## 제목이 시그니처 일곱 개, 그 순서다' {
        Test-Path -LiteralPath $script:docPath -PathType Leaf | Should -BeTrue
        $lines = Get-Content -LiteralPath $script:docPath -Encoding UTF8
        $actualHeadings = @(
            foreach ($line in $lines) {
                if ($line -match '^##\s+(.+?)\s*$') {
                    $Matches[1]
                }
            }
        )
        $actualHeadings.Count | Should -Be $script:expectedHeadings.Count
        for ($i = 0; $i -lt $script:expectedHeadings.Count; $i++) {
            $actualHeadings[$i] | Should -Be $script:expectedHeadings[$i]
        }
    }

    It '문서에 clean·after-setup 체크포인트 이름이 있다' {
        $content = Get-Content -LiteralPath $script:docPath -Raw -Encoding UTF8
        $content | Should -Match '(?m)`clean`'
        $content | Should -Match '(?m)`after-setup`'
    }
}

Describe '검증 PC 체크리스트 문서' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:verifyDocPath = Join-Path $script:repoRoot 'pc-setup' 'test' 'verify-pc-checklist.md'
        $script:vmDocPath = Join-Path $script:repoRoot 'pc-setup' 'test' 'vm-checklist.md'
        $script:expectedHeadings = @(
            '이 문서를 읽는 Claude 세션에게'
            '0. 사람: Claude Code 설치'
            '1. 미리보기 보고'
            '2. 사람: 보고 확인'
            '3. 셋업 전 정리 (해당할 때만)'
            '4. 부트스트랩'
            '5. 재부팅과 셋업 다시 실행'
            '6. 재실행 (멱등)'
            '7. 결과 기록'
        )
    }

    It 'pc-setup/test/verify-pc-checklist.md 가 있고 ## 제목이 시그니처 아홉 개, 그 순서다' {
        Test-Path -LiteralPath $script:verifyDocPath -PathType Leaf | Should -BeTrue
        $lines = Get-Content -LiteralPath $script:verifyDocPath -Encoding UTF8
        $actualHeadings = @(
            foreach ($line in $lines) {
                if ($line -match '^##\s+(.+?)\s*$') {
                    $Matches[1]
                }
            }
        )
        $actualHeadings.Count | Should -Be $script:expectedHeadings.Count
        for ($i = 0; $i -lt $script:expectedHeadings.Count; $i++) {
            $actualHeadings[$i] | Should -Be $script:expectedHeadings[$i]
        }
    }

    It '3번 절에 세 조건(nvm-windows, pnpm, .gitconfig)과 npm 전역 패키지는 지우지 않는다 문장이 있다' {
        $content = Get-Content -LiteralPath $script:verifyDocPath -Raw -Encoding UTF8
        $sectionMatch = [regex]::Match($content, '(?ms)^## 3\. 셋업 전 정리 \(해당할 때만\)\r?\n(?<body>.*?)(?=^## |\z)')
        $sectionMatch.Success | Should -BeTrue
        $section3 = $sectionMatch.Groups['body'].Value

        $section3 | Should -Match 'nvm-windows'
        $section3 | Should -Match 'pnpm'
        $section3 | Should -Match '\.gitconfig'
        $section3 | Should -Match 'npm 전역 패키지는 지우지 않는다'
    }

    It 'vm-checklist.md 와 verify-pc-checklist.md 의 상대 링크가 가리키는 파일이 모두 있다' {
        foreach ($docPath in @($script:vmDocPath, $script:verifyDocPath)) {
            $docDir = Split-Path -Path $docPath -Parent
            $content = Get-Content -LiteralPath $docPath -Raw -Encoding UTF8
            $linkMatches = [regex]::Matches($content, '\]\(([^)]+)\)')
            foreach ($m in $linkMatches) {
                $target = $m.Groups[1].Value.Trim()
                if ($target -match '^https?://') {
                    continue
                }
                $pathOnly = ($target -replace '#.*$', '').Trim()
                if ([string]::IsNullOrEmpty($pathOnly)) {
                    continue
                }
                $resolved = Join-Path $docDir $pathOnly
                Test-Path -LiteralPath $resolved | Should -BeTrue -Because "$docPath 의 상대 링크 '$target' ($resolved) 가 존재해야 한다"
            }
        }
    }
}

Describe 'pc-setup README 문서' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:readmePath = Join-Path $script:repoRoot 'pc-setup' 'README.md'
        $script:expectedHeadings = @(
            '새 PC'
            '손으로 할 일'
            '이미 셋업한 PC'
            '선언'
            '검증'
        )
        $script:expectedManualSubheadings = @(
            '비밀값'
            '작업 저장소'
            '에이전트 폴더'
            'Flutter'
            'VS Code'
            '셋업이 알린 할 일'
        )
    }

    It 'pc-setup/README.md 가 있고 ## 제목이 시그니처 다섯 개, 그 순서다' {
        Test-Path -LiteralPath $script:readmePath -PathType Leaf | Should -BeTrue
        $lines = Get-Content -LiteralPath $script:readmePath -Encoding UTF8
        $actualHeadings = @(
            foreach ($line in $lines) {
                if ($line -match '^##\s+(.+?)\s*$') {
                    $Matches[1]
                }
            }
        )
        $actualHeadings.Count | Should -Be $script:expectedHeadings.Count
        for ($i = 0; $i -lt $script:expectedHeadings.Count; $i++) {
            $actualHeadings[$i] | Should -Be $script:expectedHeadings[$i]
        }
    }

    It '## 새 PC 절에 부트스트랩 한 줄 명령이 있다' {
        $content = Get-Content -LiteralPath $script:readmePath -Raw -Encoding UTF8
        $sectionMatch = [regex]::Match($content, '(?ms)^## 새 PC\r?\n(?<body>.*?)(?=^## |\z)')
        $sectionMatch.Success | Should -BeTrue
        $sectionMatch.Groups['body'].Value | Should -Match ([regex]::Escape('irm https://raw.githubusercontent.com/hdmun/anything/main/pc-setup/bootstrap.ps1 | iex'))
    }

    It '## 손으로 할 일 절이 ## 새 PC 바로 다음이고 ### 소제목 6개가 순서대로 있다' {
        $content = Get-Content -LiteralPath $script:readmePath -Raw -Encoding UTF8
        $lines = Get-Content -LiteralPath $script:readmePath -Encoding UTF8
        $h2Headings = @(
            foreach ($line in $lines) {
                if ($line -match '^##\s+(.+?)\s*$') {
                    $Matches[1]
                }
            }
        )
        $newPcIndex = [Array]::IndexOf($h2Headings, '새 PC')
        $manualIndex = [Array]::IndexOf($h2Headings, '손으로 할 일')
        $newPcIndex | Should -BeGreaterOrEqual 0
        $manualIndex | Should -Be ($newPcIndex + 1)

        $sectionMatch = [regex]::Match($content, '(?ms)^## 손으로 할 일\r?\n(?<body>.*?)(?=^## |\z)')
        $sectionMatch.Success | Should -BeTrue
        $subHeadings = @(
            foreach ($m in [regex]::Matches($sectionMatch.Groups['body'].Value, '(?m)^###\s+(.+?)\s*$')) {
                $m.Groups[1].Value
            }
        )
        $subHeadings.Count | Should -Be $script:expectedManualSubheadings.Count
        for ($i = 0; $i -lt $script:expectedManualSubheadings.Count; $i++) {
            $subHeadings[$i] | Should -Be $script:expectedManualSubheadings[$i]
        }
    }

    It 'pc-setup/README.md 의 상대 링크가 가리키는 파일이 모두 있다' {
        $docDir = Split-Path -Path $script:readmePath -Parent
        $content = Get-Content -LiteralPath $script:readmePath -Raw -Encoding UTF8
        $linkMatches = [regex]::Matches($content, '\]\(([^)]+)\)')
        foreach ($m in $linkMatches) {
            $target = $m.Groups[1].Value.Trim()
            if ($target -match '^https?://') {
                continue
            }
            $pathOnly = ($target -replace '#.*$', '').Trim()
            if ([string]::IsNullOrEmpty($pathOnly)) {
                continue
            }
            $resolved = Join-Path $docDir $pathOnly
            Test-Path -LiteralPath $resolved | Should -BeTrue -Because "README.md 의 상대 링크 '$target' ($resolved) 가 존재해야 한다"
        }
    }
}
