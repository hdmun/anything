using module ../lib/Declaration.psm1

BeforeAll {
    $declarationPath = Join-Path $PSScriptRoot '..' 'lib' 'Declaration.psm1'
    Import-Module $declarationPath -Force
    $setupPath = Join-Path $PSScriptRoot '..' 'lib' 'Setup.psm1'
    Import-Module $setupPath -Force
    $repoToolsPath = Join-Path $PSScriptRoot '..' 'lib' 'RepoTools.psm1'
    Import-Module $repoToolsPath -Force -Global
}

Describe 'Get-RepoToolItems' {
    It '정상 두 줄(하나는 Elevated) -> 항목 2개, Elevated 맞음, Invoke 가 install.ps1 결과 반환(-Check 전달 포함)' {
        $fakeRepo = Join-Path (Get-Item 'TestDrive:/').FullName 'repo-valid'
        $fakeRoot = Join-Path $fakeRepo 'pc-setup'
        $toolA = Join-Path $fakeRepo 'tool-a'
        $toolB = Join-Path $fakeRepo 'tool-b'
        New-Item -Path $fakeRoot, $toolA, $toolB -ItemType Directory -Force | Out-Null

        Set-Content -Path (Join-Path $toolA 'install.ps1') -Value @'
param([switch]$Check)
if ($Check) { Write-Output '다름 (체크됨)' } else { Write-Output '바꿈' }
'@
        Set-Content -Path (Join-Path $toolB 'install.ps1') -Value @'
param([switch]$Check)
Write-Output '그대로'
'@

        $psd1 = @"
@{
    Items = @(
        @{ Id = 'tool-a'; Elevated = `$true }
        @{ Id = 'tool-b' }
    )
}
"@
        Set-Content -Path (Join-Path $fakeRoot 'repo-tools.psd1') -Value $psd1

        $items = Get-RepoToolItems -Root $fakeRoot
        $items.Count | Should -Be 2

        $items[0].Stage | Should -Be '저장소 도구'
        $items[0].Id | Should -Be 'tool-a'
        $items[0].Elevated | Should -BeTrue

        $items[1].Stage | Should -Be '저장소 도구'
        $items[1].Id | Should -Be 'tool-b'
        $items[1].Elevated | Should -BeFalse

        $resACheck = & $items[0].Invoke $true
        $resACheck.Status | Should -Be '다름'
        $resACheck.Detail | Should -Be '체크됨'

        $resAFix = & $items[0].Invoke $false
        $resAFix.Status | Should -Be '바꿈'

        $resBCheck = & $items[1].Invoke $true
        $resBCheck.Status | Should -Be '그대로'
    }

    It 'install.ps1 없음 -> DeclarationException 에 install.ps1 이 없다' {
        $fakeRepo = Join-Path (Get-Item 'TestDrive:/').FullName 'repo-missing-install'
        $fakeRoot = Join-Path $fakeRepo 'pc-setup'
        New-Item -Path $fakeRoot -ItemType Directory -Force | Out-Null

        $psd1 = @"
@{
    Items = @(
        @{ Id = 'no-such-tool'; Elevated = `$false }
    )
}
"@
        Set-Content -Path (Join-Path $fakeRoot 'repo-tools.psd1') -Value $psd1

        try {
            Get-RepoToolItems -Root $fakeRoot
            throw '예외가 발생해야 합니다'
        } catch [DeclarationException] {
            $_.Exception.Problems.Count | Should -Be 1
            $_.Exception.Problems[0] | Should -Be 'repo-tools.psd1:3: install.ps1 이 없다: no-such-tool/install.ps1'
        }
    }

    It 'Id = ..\x -> 저장소 루트 기준 폴더 이름 문제' {
        $fakeRepo = Join-Path (Get-Item 'TestDrive:/').FullName 'repo-dotdot'
        $fakeRoot = Join-Path $fakeRepo 'pc-setup'
        New-Item -Path $fakeRoot -ItemType Directory -Force | Out-Null

        $psd1 = @"
@{
    Items = @(
        @{ Id = '..\x' }
    )
}
"@
        Set-Content -Path (Join-Path $fakeRoot 'repo-tools.psd1') -Value $psd1

        try {
            Get-RepoToolItems -Root $fakeRoot
            throw '예외가 발생해야 합니다'
        } catch [DeclarationException] {
            $_.Exception.Problems | Should -Contain 'repo-tools.psd1:3: Id 는 저장소 루트 기준 폴더 이름이다'
        }
    }

    It '모르는 키(Script) -> 모르는 키 문제' {
        $fakeRepo = Join-Path (Get-Item 'TestDrive:/').FullName 'repo-unknown-key'
        $fakeRoot = Join-Path $fakeRepo 'pc-setup'
        $toolA = Join-Path $fakeRepo 'tool-a'
        New-Item -Path $fakeRoot, $toolA -ItemType Directory -Force | Out-Null
        Set-Content -Path (Join-Path $toolA 'install.ps1') -Value "param([switch]`$Check)`nWrite-Output '그대로'"

        $psd1 = @"
@{
    Items = @(
        @{ Id = 'tool-a'; Script = 'x.ps1' }
    )
}
"@
        Set-Content -Path (Join-Path $fakeRoot 'repo-tools.psd1') -Value $psd1

        try {
            Get-RepoToolItems -Root $fakeRoot
            throw '예외가 발생해야 합니다'
        } catch [DeclarationException] {
            $_.Exception.Problems[0] | Should -Match '모르는 키'
        }
    }
}

Describe '실제 저장소 도구 선언 (pc-setup/repo-tools.psd1)' {
    It 'pc-setup/repo-tools.psd1 이 검사를 통과하고 Id 가 rdp-notify, .githooks 순서며 Elevated 는 rdp-notify 만이다' {
        $pcSetupRoot = Join-Path $PSScriptRoot '..'
        $items = Get-RepoToolItems -Root $pcSetupRoot

        $items.Count | Should -Be 2
        $items[0].Stage | Should -Be '저장소 도구'
        $items[0].Id | Should -Be 'rdp-notify'
        $items[0].Elevated | Should -BeTrue

        $items[1].Stage | Should -Be '저장소 도구'
        $items[1].Id | Should -Be '.githooks'
        $items[1].Elevated | Should -BeFalse
    }

    It '기본 단계 목록으로 만든 항목의 Stage 순서가 Windows 설정 -> 앱 -> 설정 파일 -> 저장소 도구 다' {
        $pcSetupRoot = Join-Path $PSScriptRoot '..'
        $providers = InModuleScope Setup { $script:DefaultStageProviders }
        $providers.Count | Should -Be 4

        $stages = [System.Collections.Generic.List[string]]::new()
        foreach ($p in $providers) {
            $stageItems = & $p $pcSetupRoot
            $stageName = $stageItems[0].Stage
            if (-not $stages.Contains($stageName)) {
                $stages.Add($stageName)
            }
        }

        $stages | Should -Be @('Windows 설정', '앱', '설정 파일', '저장소 도구')
    }
}
