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
