Describe 'README 및 스크립트 저장소 경로 표기' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:targetFiles = @(
            'agent-accounts/README.md'
            'agent-accounts/AgentAccounts.ps1'
            'rdp-notify/README.md'
            'plugins/relay/README.md'
            'synology/README.md'
        )
        $script:readmeFiles = @(
            'agent-accounts/README.md'
            'rdp-notify/README.md'
            'plugins/relay/README.md'
            'synology/README.md'
        )
        $script:signatureLine = '`<저장소>` 는 이 저장소를 받은 폴더다(새 PC 는 `$HOME\anything`). 셋업을 돌린 PC 에서는 환경 변수 `ANYTHING_REPO` 에 이 경로가 들어 있다.'
    }

    It '대상 파일 <Path> 에 USERPROFILE\scripts (대소문자 무시)가 없다' -ForEach @(
        @{ Path = 'agent-accounts/README.md' }
        @{ Path = 'agent-accounts/AgentAccounts.ps1' }
        @{ Path = 'rdp-notify/README.md' }
        @{ Path = 'plugins/relay/README.md' }
        @{ Path = 'synology/README.md' }
    ) {
        $fullPath = Join-Path $script:repoRoot $Path
        $content = Get-Content -LiteralPath $fullPath -Raw -Encoding UTF8
        ($content -imatch 'USERPROFILE\\scripts') | Should -BeFalse
    }

    It '대상 파일 <Path> 에 C:\Users\<사용자>\scripts 형태 경로가 없다' -ForEach @(
        @{ Path = 'agent-accounts/README.md' }
        @{ Path = 'agent-accounts/AgentAccounts.ps1' }
        @{ Path = 'rdp-notify/README.md' }
        @{ Path = 'plugins/relay/README.md' }
        @{ Path = 'synology/README.md' }
    ) {
        $fullPath = Join-Path $script:repoRoot $Path
        $content = Get-Content -LiteralPath $fullPath -Raw -Encoding UTF8
        ($content -match '[A-Za-z]:[\\/]Users[\\/][^\\/\s]+[\\/]scripts') | Should -BeFalse
    }

    It 'README <Path> 에 <저장소> 와 시그니처 설명 문장이 있다' -ForEach @(
        @{ Path = 'agent-accounts/README.md' }
        @{ Path = 'rdp-notify/README.md' }
        @{ Path = 'plugins/relay/README.md' }
        @{ Path = 'synology/README.md' }
    ) {
        $fullPath = Join-Path $script:repoRoot $Path
        $content = Get-Content -LiteralPath $fullPath -Raw -Encoding UTF8
        $content | Should -Match ([regex]::Escape('<저장소>'))
        $content.Contains($script:signatureLine) | Should -BeTrue
    }
}
