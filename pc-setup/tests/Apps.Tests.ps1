using module ../lib/Declaration.psm1

BeforeAll {
    $declarationPath = Join-Path $PSScriptRoot '..' 'lib' 'Declaration.psm1'
    Import-Module $declarationPath -Force
    $itemScriptPath = Join-Path $PSScriptRoot '..' 'lib' 'ItemScript.psm1'
    Import-Module $itemScriptPath -Force
    $appsPath = Join-Path $PSScriptRoot '..' 'lib' 'Apps.psm1'
    Import-Module $appsPath -Force
}

Describe 'Get-AppItems' {
    It '1: winget Scope=machine -> Elevated $true, Invoke-WingetApp 으로 넘김' {
        $content = @"
@{
    Items = @(
        @{ Id = 'Git.Git'; Scope = 'machine' }
    )
}
"@
        Set-Content -Path 'TestDrive:/apps.psd1' -Value $content
        $root = (Get-Item 'TestDrive:/').FullName

        $script:capturedEntry = $null
        Mock -ModuleName Apps Invoke-WingetApp {
            $script:capturedEntry = $Entry
            return @{ Status = '그대로'; Detail = '' }
        }

        $items = Get-AppItems -Root $root
        $items.Count | Should -Be 1
        $items[0].Stage | Should -Be '앱'
        $items[0].Id | Should -Be 'Git.Git'
        $items[0].Elevated | Should -BeTrue

        $res = & $items[0].Invoke $false
        $res.Status | Should -Be '그대로'
        $script:capturedEntry.Id | Should -Be 'Git.Git'
        $script:capturedEntry.Scope | Should -Be 'machine'
    }

    It '2: winget Scope=user -> Elevated $false' {
        $content = @"
@{
    Items = @(
        @{ Id = 'Microsoft.VSCode'; Scope = 'user' }
    )
}
"@
        Set-Content -Path 'TestDrive:/apps.psd1' -Value $content
        $root = (Get-Item 'TestDrive:/').FullName

        $items = Get-AppItems -Root $root
        $items.Count | Should -Be 1
        $items[0].Elevated | Should -BeFalse
    }

    It '3: winget Scope=user; Elevated=$true -> Elevated $true' {
        $content = @"
@{
    Items = @(
        @{ Id = 'Python.Python.3.13'; Scope = 'user'; Elevated = `$true }
    )
}
"@
        Set-Content -Path 'TestDrive:/apps.psd1' -Value $content
        $root = (Get-Item 'TestDrive:/').FullName

        $items = Get-AppItems -Root $root
        $items.Count | Should -Be 1
        $items[0].Elevated | Should -BeTrue
    }

    It '4: winget Scope 없음 -> winget 항목에는 ''Scope'' 가 있어야 한다' {
        $content = @"
@{
    Items = @(
        @{ Id = 'Git.Git' }
    )
}
"@
        Set-Content -Path 'TestDrive:/apps.psd1' -Value $content
        $root = (Get-Item 'TestDrive:/').FullName

        try {
            Get-AppItems -Root $root
            throw '예외가 발생해야 합니다'
        } catch [DeclarationException] {
            $_.Exception.Problems | Should -Contain "apps.psd1:3: winget 항목에는 'Scope' 가 있어야 한다"
        }
    }

    It '5: msstore, Scope 없음 -> Elevated $false, Invoke-WingetApp 으로 넘김' {
        $content = @"
@{
    Items = @(
        @{ Id = '9NKSQGP7F2NH'; WingetSource = 'msstore' }
    )
}
"@
        Set-Content -Path 'TestDrive:/apps.psd1' -Value $content
        $root = (Get-Item 'TestDrive:/').FullName

        $script:capturedEntry = $null
        Mock -ModuleName Apps Invoke-WingetApp {
            $script:capturedEntry = $Entry
            return @{ Status = '그대로'; Detail = '' }
        }

        $items = Get-AppItems -Root $root
        $items.Count | Should -Be 1
        $items[0].Elevated | Should -BeFalse

        $res = & $items[0].Invoke $false
        $res.Status | Should -Be '그대로'
        $script:capturedEntry.WingetSource | Should -Be 'msstore'
    }

    It '6: msstore + Scope=user -> winget msstore 항목에는 ''Scope'' 를 쓰지 않는다' {
        $content = @"
@{
    Items = @(
        @{ Id = '9NKSQGP7F2NH'; WingetSource = 'msstore'; Scope = 'user' }
    )
}
"@
        Set-Content -Path 'TestDrive:/apps.psd1' -Value $content
        $root = (Get-Item 'TestDrive:/').FullName

        try {
            Get-AppItems -Root $root
            throw '예외가 발생해야 합니다'
        } catch [DeclarationException] {
            $_.Exception.Problems | Should -Contain "apps.psd1:3: winget msstore 항목에는 'Scope' 를 쓰지 않는다"
        }
    }

    It '7: scoop Bucket=extras -> Elevated $false, Invoke-ScoopApp' {
        $content = @"
@{
    Items = @(
        @{ Id = 'nvm'; Origin = 'scoop'; Bucket = 'extras' }
    )
}
"@
        Set-Content -Path 'TestDrive:/apps.psd1' -Value $content
        $root = (Get-Item 'TestDrive:/').FullName

        $script:capturedEntry = $null
        Mock -ModuleName Apps Invoke-ScoopApp {
            $script:capturedEntry = $Entry
            return @{ Status = '설치함'; Detail = '' }
        }

        $items = Get-AppItems -Root $root
        $items.Count | Should -Be 1
        $items[0].Elevated | Should -BeFalse

        $res = & $items[0].Invoke $false
        $res.Status | Should -Be '설치함'
        $script:capturedEntry.Bucket | Should -Be 'extras'
    }

    It '8: scoop Bucket 없음 / Bucket=versions -> 필수 키 문제 / 허용 값 문제' {
        $contentMissing = @"
@{
    Items = @(
        @{ Id = 'ripgrep'; Origin = 'scoop' }
    )
}
"@
        Set-Content -Path 'TestDrive:/apps.psd1' -Value $contentMissing
        $root = (Get-Item 'TestDrive:/').FullName

        try {
            Get-AppItems -Root $root
            throw '예외가 발생해야 합니다'
        } catch [DeclarationException] {
            $_.Exception.Problems | Should -Contain "apps.psd1:3: scoop 항목에는 'Bucket' 가 있어야 한다"
        }

        $contentBadBucket = @"
@{
    Items = @(
        @{ Id = 'ripgrep'; Origin = 'scoop'; Bucket = 'versions' }
    )
}
"@
        Set-Content -Path 'TestDrive:/apps.psd1' -Value $contentBadBucket

        try {
            Get-AppItems -Root $root
            throw '예외가 발생해야 합니다'
        } catch [DeclarationException] {
            $_.Exception.Problems[0] | Should -Match "apps\.psd1:3: 'Bucket' 값 'versions' 은 허용되지 않는다"
        }
    }

    It '9: nvm NodeLine=26 -> Invoke-NvmApp' {
        $content = @"
@{
    Items = @(
        @{ Id = 'node-26'; Origin = 'nvm'; NodeLine = '26' }
    )
}
"@
        Set-Content -Path 'TestDrive:/apps.psd1' -Value $content
        $root = (Get-Item 'TestDrive:/').FullName

        $script:capturedEntry = $null
        Mock -ModuleName Apps Invoke-NvmApp {
            $script:capturedEntry = $Entry
            return @{ Status = '그대로'; Detail = '' }
        }

        $items = Get-AppItems -Root $root
        $items.Count | Should -Be 1
        $items[0].Elevated | Should -BeFalse

        $res = & $items[0].Invoke $false
        $res.Status | Should -Be '그대로'
        $script:capturedEntry.NodeLine | Should -Be '26'
    }

    It '10: nvm NodeLine 없음 -> 필수 키 문제' {
        $content = @"
@{
    Items = @(
        @{ Id = 'node-26'; Origin = 'nvm' }
    )
}
"@
        Set-Content -Path 'TestDrive:/apps.psd1' -Value $content
        $root = (Get-Item 'TestDrive:/').FullName

        try {
            Get-AppItems -Root $root
            throw '예외가 발생해야 합니다'
        } catch [DeclarationException] {
            $_.Exception.Problems | Should -Contain "apps.psd1:3: nvm 항목에는 'NodeLine' 가 있어야 한다"
        }
    }

    It '11: pnpm / go -> 각각 Invoke-PnpmApp / Invoke-GoApp, Elevated $false' {
        $content = @"
@{
    Items = @(
        @{ Id = 'typescript'; Origin = 'pnpm' }
        @{ Id = 'golang.org/x/tools/gopls'; Origin = 'go' }
    )
}
"@
        Set-Content -Path 'TestDrive:/apps.psd1' -Value $content
        $root = (Get-Item 'TestDrive:/').FullName

        $script:pnpmCalled = $false
        $script:goCalled = $false
        Mock -ModuleName Apps Invoke-PnpmApp { $script:pnpmCalled = $true; return @{ Status = '그대로'; Detail = '' } }
        Mock -ModuleName Apps Invoke-GoApp   { $script:goCalled = $true;   return @{ Status = '그대로'; Detail = '' } }

        $items = Get-AppItems -Root $root
        $items.Count | Should -Be 2
        $items[0].Elevated | Should -BeFalse
        $items[1].Elevated | Should -BeFalse

        $null = & $items[0].Invoke $false
        $null = & $items[1].Invoke $false
        $script:pnpmCalled | Should -BeTrue
        $script:goCalled | Should -BeTrue
    }

    It '12: pnpm + Scope -> pnpm 항목에는 ''Scope'' 를 쓰지 않는다' {
        $content = @"
@{
    Items = @(
        @{ Id = 'typescript'; Origin = 'pnpm'; Scope = 'user' }
    )
}
"@
        Set-Content -Path 'TestDrive:/apps.psd1' -Value $content
        $root = (Get-Item 'TestDrive:/').FullName

        try {
            Get-AppItems -Root $root
            throw '예외가 발생해야 합니다'
        } catch [DeclarationException] {
            $_.Exception.Problems | Should -Contain "apps.psd1:3: pnpm 항목에는 'Scope' 를 쓰지 않는다"
        }
    }

    It '13: official + apps/<Id>.ps1 있음, Elevated=$true -> Elevated $true, Invoke 가 스크립트 결과를 돌려줌' {
        $content = @"
@{
    Items = @(
        @{ Id = 'CustomApp'; Origin = 'official'; Elevated = `$true }
    )
}
"@
        Set-Content -Path 'TestDrive:/apps.psd1' -Value $content
        $appsDir = Join-Path 'TestDrive:/' 'apps'
        New-Item -Path $appsDir -ItemType Directory -Force | Out-Null
        $scriptContent = @"
param([switch]`$Check)
if (`$Check) {
    Write-Output '다름'
} else {
    Write-Output '바꿈'
}
"@
        Set-Content -Path (Join-Path $appsDir 'CustomApp.ps1') -Value $scriptContent

        $root = (Get-Item 'TestDrive:/').FullName
        $items = Get-AppItems -Root $root
        $items.Count | Should -Be 1
        $items[0].Elevated | Should -BeTrue

        $resCheck = & $items[0].Invoke $true
        $resCheck.Status | Should -Be '다름'

        $resFix = & $items[0].Invoke $false
        $resFix.Status | Should -Be '바꿈'
    }

    It '14: official + 스크립트 없음 -> 스크립트가 없다: apps/<Id>.ps1' {
        $content = @"
@{
    Items = @(
        @{ Id = 'MissingApp'; Origin = 'official' }
    )
}
"@
        Set-Content -Path 'TestDrive:/apps.psd1' -Value $content
        $root = (Get-Item 'TestDrive:/').FullName

        try {
            Get-AppItems -Root $root
            throw '예외가 발생해야 합니다'
        } catch [DeclarationException] {
            $_.Exception.Problems | Should -Contain 'apps.psd1:3: 스크립트가 없다: apps/MissingApp.ps1'
        }
    }

    It '15: Origin=brew -> 허용 값 문제' {
        $content = @"
@{
    Items = @(
        @{ Id = 'wget'; Origin = 'brew' }
    )
}
"@
        Set-Content -Path 'TestDrive:/apps.psd1' -Value $content
        $root = (Get-Item 'TestDrive:/').FullName

        try {
            Get-AppItems -Root $root
            throw '예외가 발생해야 합니다'
        } catch [DeclarationException] {
            $_.Exception.Problems[0] | Should -Match "apps\.psd1:3: 'Origin' 값 'brew' 은 허용되지 않는다"
        }
    }

    It '16: Invoke 에 $Check=$true -> 원천 함수가 -Check $true 를 받음' {
        $content = @"
@{
    Items = @(
        @{ Id = 'Git.Git'; Scope = 'user' }
    )
}
"@
        Set-Content -Path 'TestDrive:/apps.psd1' -Value $content
        $root = (Get-Item 'TestDrive:/').FullName

        $script:capturedCheck = $null
        Mock -ModuleName Apps Invoke-WingetApp {
            $script:capturedCheck = $Check
            return @{ Status = '할 일'; Detail = '' }
        }

        $items = Get-AppItems -Root $root
        $res = & $items[0].Invoke $true
        $script:capturedCheck | Should -BeTrue
        $res.Status | Should -Be '할 일'
    }

    It '17: 원천 함수 자리(Mock 없이) -> 아직 구현되지 않은 원천: <원천> 예외' {
        $content = @"
@{
    Items = @(
        @{ Id = 'b'; Origin = 'scoop'; Bucket = 'main' }
        @{ Id = 'c'; Origin = 'nvm'; NodeLine = '26' }
        @{ Id = 'd'; Origin = 'pnpm' }
        @{ Id = 'e'; Origin = 'go' }
    )
}
"@
        Set-Content -Path 'TestDrive:/apps.psd1' -Value $content
        $root = (Get-Item 'TestDrive:/').FullName

        $items = Get-AppItems -Root $root
        $expectedOrigins = @('scoop', 'nvm', 'pnpm', 'go')
        for ($i = 0; $i -lt $expectedOrigins.Count; $i++) {
            $orig = $expectedOrigins[$i]
            { & $items[$i].Invoke $false } | Should -Throw "아직 구현되지 않은 원천: $orig"
        }
    }
}
