Describe 'setup.ps1 뼈대' {
    It '-Check 는 종료 코드 0 으로 끝난다' {
        $setup = Join-Path $PSScriptRoot '..' 'setup.ps1'
        pwsh -NoProfile -File $setup -Check
        $LASTEXITCODE | Should -Be 0
    }
}
