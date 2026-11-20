using module ../lib/Declaration.psm1

BeforeAll {
    $declarationPath = Join-Path $PSScriptRoot '..' 'lib' 'Declaration.psm1'
    Import-Module $declarationPath -Force
    $configFilesPath = Join-Path $PSScriptRoot '..' 'lib' 'ConfigFiles.psm1'
    Import-Module $configFilesPath -Force
}

Describe 'Get-ConfigFileItems' {
    It '정상 3줄(Link 2·GitInclude 1) -> 항목 3개, Stage=설정 파일, Id=Path 글, Elevated=$false' {
        $root = Join-Path 'TestDrive:/' 'cfg-valid'
        $cfgDir = Join-Path $root 'config'
        New-Item -Path $cfgDir -ItemType Directory -Force | Out-Null
        Set-Content -Path (Join-Path $cfgDir 'nanorc') -Value 'set linenumbers'
        Set-Content -Path (Join-Path $cfgDir 'wt-settings.json') -Value '{}'
        Set-Content -Path (Join-Path $cfgDir 'gitconfig') -Value "[core]`n`tautocrlf = input`n"

        $psd1 = @"
@{
    Items = @(
        @{ Path = '~/.nanorc'; Method = 'Link'; Source = 'config/nanorc' }
        @{ Path = '`$env:LOCALAPPDATA/Packages/WT/settings.json'; Method = 'Link'; Source = 'config/wt-settings.json' }
        @{ Path = '~/.gitconfig'; Method = 'GitInclude'; Source = 'config/gitconfig' }
    )
}
"@
        Set-Content -Path (Join-Path $root 'config-files.psd1') -Value $psd1

        $items = Get-ConfigFileItems -Root $root
        $items.Count | Should -Be 3

        $items[0].Stage | Should -Be '설정 파일'
        $items[0].Id | Should -Be '~/.nanorc'
        $items[0].Elevated | Should -BeFalse

        $items[1].Stage | Should -Be '설정 파일'
        $items[1].Id | Should -Be '$env:LOCALAPPDATA/Packages/WT/settings.json'
        $items[1].Elevated | Should -BeFalse

        $items[2].Stage | Should -Be '설정 파일'
        $items[2].Id | Should -Be '~/.gitconfig'
        $items[2].Elevated | Should -BeFalse
    }

    It 'Source 파일 없음 -> DeclarationException 에 저장소 파일이 없다' {
        $root = Join-Path 'TestDrive:/' 'cfg-missing-src'
        New-Item -Path $root -ItemType Directory -Force | Out-Null
        $psd1 = @"
@{
    Items = @(
        @{ Path = '~/.nanorc'; Method = 'Link'; Source = 'config/missing-nanorc' }
    )
}
"@
        Set-Content -Path (Join-Path $root 'config-files.psd1') -Value $psd1

        try {
            Get-ConfigFileItems -Root $root
            throw '예외가 발생해야 합니다'
        } catch [DeclarationException] {
            $_.Exception.Problems.Count | Should -Be 1
            $_.Exception.Problems[0] | Should -Be 'config-files.psd1:3: 저장소 파일이 없다: config/missing-nanorc'
        }
    }

    It 'Method = DotSource -> 허용 값 문제' {
        $root = Join-Path 'TestDrive:/' 'cfg-bad-method'
        $cfgDir = Join-Path $root 'config'
        New-Item -Path $cfgDir -ItemType Directory -Force | Out-Null
        Set-Content -Path (Join-Path $cfgDir 'profile.ps1') -Value '# ps'

        $psd1 = @"
@{
    Items = @(
        @{ Path = '~/profile.ps1'; Method = 'DotSource'; Source = 'config/profile.ps1' }
    )
}
"@
        Set-Content -Path (Join-Path $root 'config-files.psd1') -Value $psd1

        try {
            Get-ConfigFileItems -Root $root
            throw '예외가 발생해야 합니다'
        } catch [DeclarationException] {
            $_.Exception.Problems[0] | Should -Match "허용되지 않는다"
        }
    }

    It 'Source = ../x -> pc-setup 폴더 안의 상대 경로 문제' {
        $root = Join-Path 'TestDrive:/' 'cfg-dotdot-src'
        New-Item -Path $root -ItemType Directory -Force | Out-Null
        $psd1 = @"
@{
    Items = @(
        @{ Path = '~/.nanorc'; Method = 'Link'; Source = '../x' }
    )
}
"@
        Set-Content -Path (Join-Path $root 'config-files.psd1') -Value $psd1

        try {
            Get-ConfigFileItems -Root $root
            throw '예외가 발생해야 합니다'
        } catch [DeclarationException] {
            $_.Exception.Problems | Should -Contain 'config-files.psd1:3: Source 는 pc-setup 폴더 안의 상대 경로다'
        }
    }

    It '같은 Path 두 줄 -> 중복 문제' {
        $root = Join-Path 'TestDrive:/' 'cfg-dup-path'
        $cfgDir = Join-Path $root 'config'
        New-Item -Path $cfgDir -ItemType Directory -Force | Out-Null
        Set-Content -Path (Join-Path $cfgDir 'a') -Value 'a'
        Set-Content -Path (Join-Path $cfgDir 'b') -Value 'b'

        $psd1 = @"
@{
    Items = @(
        @{ Path = '~/.nanorc'; Method = 'Link'; Source = 'config/a' }
        @{ Path = '~/.nanorc'; Method = 'Link'; Source = 'config/b' }
    )
}
"@
        Set-Content -Path (Join-Path $root 'config-files.psd1') -Value $psd1

        try {
            Get-ConfigFileItems -Root $root
            throw '예외가 발생해야 합니다'
        } catch [DeclarationException] {
            $_.Exception.Problems[0] | Should -Match '겹친다'
        }
    }

    It '항목 Invoke: 없는 환경 변수가 든 Path -> 실패: 환경 변수 <이름> 이 없다' {
        $root = Join-Path 'TestDrive:/' 'cfg-missing-env'
        $cfgDir = Join-Path $root 'config'
        New-Item -Path $cfgDir -ItemType Directory -Force | Out-Null
        Set-Content -Path (Join-Path $cfgDir 'a') -Value 'a'

        $psd1 = @"
@{
    Items = @(
        @{ Path = '`$env:PC_SETUP_NO_SUCH_ENV_VAR_I106/a'; Method = 'Link'; Source = 'config/a' }
    )
}
"@
        Set-Content -Path (Join-Path $root 'config-files.psd1') -Value $psd1

        $items = Get-ConfigFileItems -Root $root
        $res = & $items[0].Invoke $true
        $res.Status | Should -Be '실패'
        $res.Detail | Should -Be "환경 변수 'PC_SETUP_NO_SUCH_ENV_VAR_I106' 이 없다"
    }

    It '항목 Invoke: TestDrive 환경 변수로 펼친 뒤 Link·GitInclude 실행' {
        $root = Join-Path 'TestDrive:/' 'cfg-invoke-ok'
        $cfgDir = Join-Path $root 'config'
        $destBase = Join-Path 'TestDrive:/' 'cfg-invoke-dest'
        New-Item -Path $cfgDir -ItemType Directory -Force | Out-Null
        New-Item -Path $destBase -ItemType Directory -Force | Out-Null
        Set-Content -Path (Join-Path $cfgDir 'nanorc') -Value 'set linenumbers'
        Set-Content -Path (Join-Path $cfgDir 'gitconfig') -Value '[core]'

        $destBaseFull = (Get-Item -LiteralPath $destBase).FullName
        $env:PC_SETUP_TEST_I106_DEST = $destBaseFull
        try {
            $psd1 = @"
@{
    Items = @(
        @{ Path = '`$env:PC_SETUP_TEST_I106_DEST/nanorc'; Method = 'Link'; Source = 'config/nanorc' }
        @{ Path = '`$env:PC_SETUP_TEST_I106_DEST/gitconfig'; Method = 'GitInclude'; Source = 'config/gitconfig' }
    )
}
"@
            Set-Content -Path (Join-Path $root 'config-files.psd1') -Value $psd1
            $items = Get-ConfigFileItems -Root $root

            (& $items[0].Invoke $false).Status | Should -Be '바꿈'
            (& $items[0].Invoke $true).Status | Should -Be '그대로'
            (& $items[1].Invoke $false).Status | Should -Be '바꿈'
            (& $items[1].Invoke $true).Status | Should -Be '그대로'
        } finally {
            Remove-Item Env:PC_SETUP_TEST_I106_DEST -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Invoke-LinkFile' {
    BeforeEach {
        $testDriveFull = (Get-Item -LiteralPath 'TestDrive:/').FullName
        $script:caseRoot = Join-Path $testDriveFull ([guid]::NewGuid().ToString('N'))
        New-Item -Path $script:caseRoot -ItemType Directory -Force | Out-Null
        $script:srcFile = (New-Item -Path (Join-Path $script:caseRoot 'source.txt') -ItemType File -Value 'repo-content' -Force).FullName
    }

    It '1: 비어 있음(부모 폴더 있음) -> -Check 다름 (없음), 고치는 실행 바꿈, 두 번째 그대로' {
        $dest = Join-Path $script:caseRoot 'target.txt'

        $rCheck = Invoke-LinkFile -Destination $dest -Source $script:srcFile -Check $true
        $rCheck.Status | Should -Be '다름'
        $rCheck.Detail | Should -Be '없음'
        Test-Path -LiteralPath $dest | Should -BeFalse

        $rFix = Invoke-LinkFile -Destination $dest -Source $script:srcFile -Check $false
        $rFix.Status | Should -Be '바꿈'
        $rFix.Detail | Should -Be ''
        (Get-Item -LiteralPath $dest -Force).LinkType | Should -Be 'SymbolicLink'

        $rAgain = Invoke-LinkFile -Destination $dest -Source $script:srcFile -Check $false
        $rAgain.Status | Should -Be '그대로'
    }

    It '2: 비어 있음(부모 폴더도 없음) -> -Check 다름 (없음), 고치는 실행 부모 폴더+링크 만들고 바꿈, 두 번째 그대로' {
        $dest = Join-Path $script:caseRoot 'nested\sub\target.txt'

        $rCheck = Invoke-LinkFile -Destination $dest -Source $script:srcFile -Check $true
        $rCheck.Status | Should -Be '다름'
        $rCheck.Detail | Should -Be '없음'
        Test-Path -LiteralPath (Split-Path -Parent $dest) | Should -BeFalse

        $rFix = Invoke-LinkFile -Destination $dest -Source $script:srcFile -Check $false
        $rFix.Status | Should -Be '바꿈'
        (Get-Item -LiteralPath $dest -Force).LinkType | Should -Be 'SymbolicLink'

        $rAgain = Invoke-LinkFile -Destination $dest -Source $script:srcFile -Check $false
        $rAgain.Status | Should -Be '그대로'
    }

    It '3: Source 를 가리키는 symlink (상대 경로 대상 포함) -> -Check 와 고치는 실행 모두 그대로' {
        $dest = Join-Path $script:caseRoot 'target.txt'
        New-Item -ItemType SymbolicLink -Path $dest -Target 'source.txt' -Force | Out-Null

        $rCheck = Invoke-LinkFile -Destination $dest -Source $script:srcFile -Check $true
        $rCheck.Status | Should -Be '그대로'

        $rFix = Invoke-LinkFile -Destination $dest -Source $script:srcFile -Check $false
        $rFix.Status | Should -Be '그대로'
    }

    It '4: 다른 곳을 가리키는 symlink -> -Check 다름 (다른 곳을 가리키는 링크), 고치는 실행 바꿈, 두 번째 그대로' {
        $other = (New-Item -Path (Join-Path $script:caseRoot 'other.txt') -ItemType File -Value 'other' -Force).FullName
        $dest = Join-Path $script:caseRoot 'target.txt'
        New-Item -ItemType SymbolicLink -Path $dest -Target $other -Force | Out-Null

        $rCheck = Invoke-LinkFile -Destination $dest -Source $script:srcFile -Check $true
        $rCheck.Status | Should -Be '다름'
        $rCheck.Detail | Should -Be '다른 곳을 가리키는 링크'

        $rFix = Invoke-LinkFile -Destination $dest -Source $script:srcFile -Check $false
        $rFix.Status | Should -Be '바꿈'
        @((Get-Item -LiteralPath $dest -Force).Target)[0] | Should -Be $script:srcFile
        (Get-ChildItem -LiteralPath $script:caseRoot -Filter '*.bak-*').Count | Should -Be 0

        $rAgain = Invoke-LinkFile -Destination $dest -Source $script:srcFile -Check $false
        $rAgain.Status | Should -Be '그대로'
    }

    It '4b: 대상이 없는(끊어진) symlink -> 다름 (다른 곳을 가리키는 링크) 및 다시 걸어 바꿈' {
        $missing = Join-Path $script:caseRoot 'gone.txt'
        $dest = Join-Path $script:caseRoot 'broken.txt'
        New-Item -ItemType SymbolicLink -Path $dest -Target $missing -Force | Out-Null

        $rCheck = Invoke-LinkFile -Destination $dest -Source $script:srcFile -Check $true
        $rCheck.Status | Should -Be '다름'
        $rCheck.Detail | Should -Be '다른 곳을 가리키는 링크'

        $rFix = Invoke-LinkFile -Destination $dest -Source $script:srcFile -Check $false
        $rFix.Status | Should -Be '바꿈'
        (Invoke-LinkFile -Destination $dest -Source $script:srcFile -Check $false).Status | Should -Be '그대로'
    }

    It '5: 일반 파일, 내용이 다름 -> -Check 다름 (일반 파일), 고치는 실행 백업 후 링크 바꿈, 백업 내용 유지, 두 번째 그대로' {
        Mock -ModuleName ConfigFiles Get-BackupStamp { '20261111-101500' }
        $dest = Join-Path $script:caseRoot 'target.txt'
        [System.IO.File]::WriteAllText($dest, 'local-original-content')

        $rCheck = Invoke-LinkFile -Destination $dest -Source $script:srcFile -Check $true
        $rCheck.Status | Should -Be '다름'
        $rCheck.Detail | Should -Be '일반 파일'

        $rFix = Invoke-LinkFile -Destination $dest -Source $script:srcFile -Check $false
        $expectedBackup = "${dest}.bak-20261111-101500"
        $rFix.Status | Should -Be '바꿈'
        $rFix.Detail | Should -Be "백업: $expectedBackup"
        Test-Path -LiteralPath $expectedBackup | Should -BeTrue
        [System.IO.File]::ReadAllText($expectedBackup) | Should -Be 'local-original-content'
        (Get-Item -LiteralPath $dest -Force).LinkType | Should -Be 'SymbolicLink'

        $rAgain = Invoke-LinkFile -Destination $dest -Source $script:srcFile -Check $false
        $rAgain.Status | Should -Be '그대로'
    }

    It '6: 일반 파일, 내용이 바이트까지 같음 -> -Check 다름 (일반 파일), 고치는 실행 백업 없이 링크 바꿈' {
        $dest = Join-Path $script:caseRoot 'target.txt'
        [System.IO.File]::Copy($script:srcFile, $dest, $true)

        $rCheck = Invoke-LinkFile -Destination $dest -Source $script:srcFile -Check $true
        $rCheck.Status | Should -Be '다름'
        $rCheck.Detail | Should -Be '일반 파일'

        $rFix = Invoke-LinkFile -Destination $dest -Source $script:srcFile -Check $false
        $rFix.Status | Should -Be '바꿈'
        $rFix.Detail | Should -Be ''
        (Get-ChildItem -LiteralPath $script:caseRoot -Filter '*.bak-*').Count | Should -Be 0
        (Get-Item -LiteralPath $dest -Force).LinkType | Should -Be 'SymbolicLink'
    }

    It '7: 폴더가 있음 -> -Check 와 고치는 실행 모두 실패: 링크 자리에 폴더가 있다' {
        $dest = Join-Path $script:caseRoot 'dir-here'
        New-Item -Path $dest -ItemType Directory -Force | Out-Null

        $rCheck = Invoke-LinkFile -Destination $dest -Source $script:srcFile -Check $true
        $rCheck.Status | Should -Be '실패'
        $rCheck.Detail | Should -Be '링크 자리에 폴더가 있다'

        $rFix = Invoke-LinkFile -Destination $dest -Source $script:srcFile -Check $false
        $rFix.Status | Should -Be '실패'
        $rFix.Detail | Should -Be '링크 자리에 폴더가 있다'
    }

    It '8: 링크 만들기 예외 + Developer Mode 꺼짐 -> 실패: Developer Mode 꺼짐' {
        Mock -ModuleName ConfigFiles New-SymbolicLink { throw 'x' }
        Mock -ModuleName ConfigFiles Test-DeveloperMode { $false }
        $dest = Join-Path $script:caseRoot 'target.txt'

        $rFix = Invoke-LinkFile -Destination $dest -Source $script:srcFile -Check $false
        $rFix.Status | Should -Be '실패'
        $rFix.Detail | Should -Be 'Developer Mode 꺼짐'
    }

    It '9: 링크 만들기 예외 + Developer Mode 켜짐 -> 실패: 링크를 만들지 못했다: x' {
        Mock -ModuleName ConfigFiles New-SymbolicLink { throw 'x' }
        Mock -ModuleName ConfigFiles Test-DeveloperMode { $true }
        $dest = Join-Path $script:caseRoot 'target.txt'

        $rFix = Invoke-LinkFile -Destination $dest -Source $script:srcFile -Check $false
        $rFix.Status | Should -Be '실패'
        $rFix.Detail | Should -Be '링크를 만들지 못했다: x'
    }
}

Describe 'Invoke-GitIncludeFile' {
    BeforeEach {
        $testDriveFull = (Get-Item -LiteralPath 'TestDrive:/').FullName
        $script:caseRoot = Join-Path $testDriveFull ([guid]::NewGuid().ToString('N'))
        $script:repoCfgDir = Join-Path $script:caseRoot 'pc-setup\config'
        New-Item -Path $script:repoCfgDir -ItemType Directory -Force | Out-Null
        $script:srcFile = (New-Item -Path (Join-Path $script:repoCfgDir 'gitconfig') -ItemType File -Value "[core]`n`tautocrlf = input`n" -Force).FullName
        $script:desiredForward = $script:srcFile.Replace('\', '/')
        $script:utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    }

    It '1: 파일 없음 -> -Check 다름 (파일 없음), 고치는 실행 새 파일(LF, BOM 없음) 만들고 바꿈, 두 번째 그대로' {
        $dest = Join-Path $script:caseRoot '.gitconfig'

        $rCheck = Invoke-GitIncludeFile -Destination $dest -Source $script:srcFile -Check $true
        $rCheck.Status | Should -Be '다름'
        $rCheck.Detail | Should -Be '파일 없음'
        Test-Path -LiteralPath $dest | Should -BeFalse

        $rFix = Invoke-GitIncludeFile -Destination $dest -Source $script:srcFile -Check $false
        $rFix.Status | Should -Be '바꿈'

        $bytes = [System.IO.File]::ReadAllBytes($dest)
        # BOM 없음 확인 (EF BB BF 가 아님)
        ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should -BeFalse
        $raw = [System.IO.File]::ReadAllText($dest, $script:utf8NoBom)
        $raw.Contains("`r`n") | Should -BeFalse
        $raw | Should -Be "[include]`npath = `"$($script:desiredForward)`"`n"

        $rAgain = Invoke-GitIncludeFile -Destination $dest -Source $script:srcFile -Check $false
        $rAgain.Status | Should -Be '그대로'
    }

    It '2: 불러오는 줄 없음(다른 섹션만 있음) -> -Check 다름 (불러오는 줄 없음), 맨 위에 넣고 기존 줄 그대로 유지' {
        $dest = Join-Path $script:caseRoot '.gitconfig'
        $existing = "# local comment`n`n[user]`n`tname = Test User`n"
        [System.IO.File]::WriteAllText($dest, $existing, $script:utf8NoBom)

        $rCheck = Invoke-GitIncludeFile -Destination $dest -Source $script:srcFile -Check $true
        $rCheck.Status | Should -Be '다름'
        $rCheck.Detail | Should -Be '불러오는 줄 없음'

        $rFix = Invoke-GitIncludeFile -Destination $dest -Source $script:srcFile -Check $false
        $rFix.Status | Should -Be '바꿈'

        $raw = [System.IO.File]::ReadAllText($dest, $script:utf8NoBom)
        $raw | Should -Be "[include]`n`tpath = `"$($script:desiredForward)`"`n$existing"

        $rAgain = Invoke-GitIncludeFile -Destination $dest -Source $script:srcFile -Check $false
        $rAgain.Status | Should -Be '그대로'
    }

    It '3: [Include] 의 path 값이 원하는 값과 같음(위치 무관, 대소문자·따옴표·구분자 무시) -> 그대로' {
        $dest = Join-Path $script:caseRoot '.gitconfig'
        $backSlashLower = $script:desiredForward.Replace('/', '\').ToLowerInvariant()
        $content = "[user]`n`tname = Local`n[Include]`n`tPath = $backSlashLower`n"
        [System.IO.File]::WriteAllText($dest, $content, $script:utf8NoBom)

        (Invoke-GitIncludeFile -Destination $dest -Source $script:srcFile -Check $true).Status | Should -Be '그대로'
        (Invoke-GitIncludeFile -Destination $dest -Source $script:srcFile -Check $false).Status | Should -Be '그대로'
    }

    It '4: [include] 의 path 값이 SourceKey 로 끝나지만 앞 경로가 다름 -> -Check 다름 (경로 다름), 그 줄만 바꾸고 다른 줄 그대로' {
        $dest = Join-Path $script:caseRoot '.gitconfig'
        $content = "# top comment`n[include]`n`tpath = `"C:/old-repo/pc-setup/config/gitconfig`"`n`n[user]`n`tname = Local`n"
        [System.IO.File]::WriteAllText($dest, $content, $script:utf8NoBom)

        $rCheck = Invoke-GitIncludeFile -Destination $dest -Source $script:srcFile -Check $true
        $rCheck.Status | Should -Be '다름'
        $rCheck.Detail | Should -Be '경로 다름'

        $rFix = Invoke-GitIncludeFile -Destination $dest -Source $script:srcFile -Check $false
        $rFix.Status | Should -Be '바꿈'

        $raw = [System.IO.File]::ReadAllText($dest, $script:utf8NoBom)
        $raw | Should -Be "# top comment`n[include]`n`tpath = `"$($script:desiredForward)`"`n`n[user]`n`tname = Local`n"

        $rAgain = Invoke-GitIncludeFile -Destination $dest -Source $script:srcFile -Check $false
        $rAgain.Status | Should -Be '그대로'
    }

    It '6: [include] 섹션이 있지만 path 가 다른 파일 -> -Check 다름 (불러오는 줄 없음), 맨 위에 새로 넣고 기존 [include] 유지' {
        $dest = Join-Path $script:caseRoot '.gitconfig'
        $existing = "[include]`n`tpath = `"C:/other/work.gitconfig`"`n"
        [System.IO.File]::WriteAllText($dest, $existing, $script:utf8NoBom)

        $rCheck = Invoke-GitIncludeFile -Destination $dest -Source $script:srcFile -Check $true
        $rCheck.Status | Should -Be '다름'
        $rCheck.Detail | Should -Be '불러오는 줄 없음'

        $rFix = Invoke-GitIncludeFile -Destination $dest -Source $script:srcFile -Check $false
        $rFix.Status | Should -Be '바꿈'

        $raw = [System.IO.File]::ReadAllText($dest, $script:utf8NoBom)
        $raw | Should -Be "[include]`n`tpath = `"$($script:desiredForward)`"`n$existing"

        $rAgain = Invoke-GitIncludeFile -Destination $dest -Source $script:srcFile -Check $false
        $rAgain.Status | Should -Be '그대로'
    }

    It 'CRLF 파일 유지: 기존 CRLF 줄바꿈을 유지하며 BOM 없는 UTF-8 로 저장' {
        $dest = Join-Path $script:caseRoot '.gitconfig'
        $existingCrlf = "[user]`r`n`tname = CrlfUser`r`n"
        [System.IO.File]::WriteAllText($dest, $existingCrlf, $script:utf8NoBom)

        $rFix = Invoke-GitIncludeFile -Destination $dest -Source $script:srcFile -Check $false
        $rFix.Status | Should -Be '바꿈'

        $raw = [System.IO.File]::ReadAllText($dest, $script:utf8NoBom)
        $raw | Should -Be "[include]`r`n`tpath = `"$($script:desiredForward)`"`r`n$existingCrlf"
    }
}
