BeforeAll {
    $script:toolPath = Join-Path $PSScriptRoot '..' 'tools' 'link-config.ps1'
    . $script:toolPath

    function Get-TreeSnapshot {
        # 폴더 아래 모든 항목의 경로·종류·링크 대상·내용을 한 글로 만든다. -Check 전후 비교에 쓴다.
        param([string]$Root)
        $lines = foreach ($item in @(Get-ChildItem -LiteralPath $Root -Recurse -Force | Sort-Object FullName)) {
            $content = ''
            if (-not $item.PSIsContainer -and $item.LinkType -ne 'SymbolicLink') {
                $content = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($item.FullName))
            }
            "$($item.FullName)|$($item.PSIsContainer)|$($item.LinkType)|$(@($item.Target)[0])|$content"
        }
        return ($lines -join "`n")
    }

    function Invoke-CheckUnchanged {
        # -Check 로 실행하고, 폴더 아래가 하나도 바뀌지 않았는지 확인한 뒤 결과를 돌려준다.
        param([string]$Root, [string]$Source, [string]$Target, [string]$Mode)
        $before = Get-TreeSnapshot -Root $Root
        $r = Invoke-Main -Source $Source -Target $Target -Mode $Mode -Check
        Get-TreeSnapshot -Root $Root | Should -Be $before
        return $r
    }
}

Describe 'link-config.ps1 -Mode Link' {
    BeforeEach {
        $testDriveFull = (Get-Item -LiteralPath 'TestDrive:/').FullName
        $script:caseRoot = Join-Path $testDriveFull ([guid]::NewGuid().ToString('N'))
        New-Item -Path $script:caseRoot -ItemType Directory -Force | Out-Null
        $script:srcFile = (New-Item -Path (Join-Path $script:caseRoot 'source.txt') -ItemType File -Value 'repo-content' -Force).FullName
    }

    It '① 없음(부모 폴더 있음) -> -Check 다름: 없음(안 바꿈), 실행 바꿈: 링크 만듦, 두 번째 그대로' {
        $dest = Join-Path $script:caseRoot 'target.txt'

        $rCheck = Invoke-CheckUnchanged -Root $script:caseRoot -Source $script:srcFile -Target $dest -Mode Link
        $rCheck.Line | Should -Be '다름: 없음'
        $rCheck.ExitCode | Should -Be 0

        $rFix = Invoke-Main -Source $script:srcFile -Target $dest -Mode Link
        $rFix.Line | Should -Be '바꿈: 링크 만듦'
        $rFix.ExitCode | Should -Be 0
        (Get-Item -LiteralPath $dest -Force).LinkType | Should -Be 'SymbolicLink'

        (Invoke-Main -Source $script:srcFile -Target $dest -Mode Link).Line | Should -Be '그대로'
    }

    It '② 없음(부모 폴더도 없음) -> -Check 는 폴더도 안 만듦, 실행은 부모 폴더+링크 만듦, 두 번째 그대로' {
        $dest = Join-Path $script:caseRoot 'nested\sub\target.txt'

        $rCheck = Invoke-CheckUnchanged -Root $script:caseRoot -Source $script:srcFile -Target $dest -Mode Link
        $rCheck.Line | Should -Be '다름: 없음'
        Test-Path -LiteralPath (Split-Path -Parent $dest) | Should -BeFalse

        (Invoke-Main -Source $script:srcFile -Target $dest -Mode Link).Line | Should -Be '바꿈: 링크 만듦'
        (Get-Item -LiteralPath $dest -Force).LinkType | Should -Be 'SymbolicLink'

        (Invoke-Main -Source $script:srcFile -Target $dest -Mode Link).Line | Should -Be '그대로'
    }

    It '③ Source 를 가리키는 링크(상대 경로 대상) -> -Check·실행 모두 그대로' {
        $dest = Join-Path $script:caseRoot 'target.txt'
        New-Item -ItemType SymbolicLink -Path $dest -Target 'source.txt' -Force | Out-Null

        (Invoke-CheckUnchanged -Root $script:caseRoot -Source $script:srcFile -Target $dest -Mode Link).Line | Should -Be '그대로'
        (Invoke-Main -Source $script:srcFile -Target $dest -Mode Link).Line | Should -Be '그대로'
    }

    It '③ Source 를 가리키는 링크(절대 경로 대상) -> 그대로' {
        $dest = Join-Path $script:caseRoot 'target.txt'
        New-Item -ItemType SymbolicLink -Path $dest -Target $script:srcFile -Force | Out-Null

        (Invoke-CheckUnchanged -Root $script:caseRoot -Source $script:srcFile -Target $dest -Mode Link).Line | Should -Be '그대로'
        (Invoke-Main -Source $script:srcFile -Target $dest -Mode Link).Line | Should -Be '그대로'
    }

    It '④ 다른 곳을 가리키는 링크 -> -Check 다름(안 바꿈), 실행 바꿈(백업 없음), 두 번째 그대로' {
        $other = (New-Item -Path (Join-Path $script:caseRoot 'other.txt') -ItemType File -Value 'other' -Force).FullName
        $dest = Join-Path $script:caseRoot 'target.txt'
        New-Item -ItemType SymbolicLink -Path $dest -Target $other -Force | Out-Null

        (Invoke-CheckUnchanged -Root $script:caseRoot -Source $script:srcFile -Target $dest -Mode Link).Line | Should -Be '다름: 다른 곳을 가리키는 링크'

        (Invoke-Main -Source $script:srcFile -Target $dest -Mode Link).Line | Should -Be '바꿈: 링크 만듦'
        @((Get-Item -LiteralPath $dest -Force).Target)[0] | Should -Be $script:srcFile
        (Get-ChildItem -LiteralPath $script:caseRoot -Filter '*.bak-*').Count | Should -Be 0

        (Invoke-Main -Source $script:srcFile -Target $dest -Mode Link).Line | Should -Be '그대로'
    }

    It '⑤ 끊어진 링크 -> -Check 다름: 다른 곳을 가리키는 링크(안 바꿈), 실행 다시 걸어 바꿈, 두 번째 그대로' {
        $missing = Join-Path $script:caseRoot 'gone.txt'
        $dest = Join-Path $script:caseRoot 'broken.txt'
        New-Item -ItemType SymbolicLink -Path $dest -Target $missing -Force | Out-Null

        (Invoke-CheckUnchanged -Root $script:caseRoot -Source $script:srcFile -Target $dest -Mode Link).Line | Should -Be '다름: 다른 곳을 가리키는 링크'
        (Invoke-Main -Source $script:srcFile -Target $dest -Mode Link).Line | Should -Be '바꿈: 링크 만듦'
        (Invoke-Main -Source $script:srcFile -Target $dest -Mode Link).Line | Should -Be '그대로'
    }

    It '⑥ 내용이 다른 일반 파일 -> -Check 다름: 일반 파일(안 바꿈), 실행 백업 후 링크, 백업 내용 유지, 두 번째 그대로' {
        Mock Get-BackupStamp { '20261111-101500' }
        $dest = Join-Path $script:caseRoot 'target.txt'
        [System.IO.File]::WriteAllText($dest, 'local-original-content')

        (Invoke-CheckUnchanged -Root $script:caseRoot -Source $script:srcFile -Target $dest -Mode Link).Line | Should -Be '다름: 일반 파일'

        $expectedBackup = "${dest}.bak-20261111-101500"
        (Invoke-Main -Source $script:srcFile -Target $dest -Mode Link).Line | Should -Be "바꿈: 링크 만듦 (백업: $expectedBackup)"
        [System.IO.File]::ReadAllText($expectedBackup) | Should -Be 'local-original-content'
        (Get-Item -LiteralPath $dest -Force).LinkType | Should -Be 'SymbolicLink'

        (Invoke-Main -Source $script:srcFile -Target $dest -Mode Link).Line | Should -Be '그대로'
    }

    It '⑦ 바이트까지 같은 일반 파일 -> -Check 다름: 일반 파일(안 바꿈), 실행 백업 없이 링크, 두 번째 그대로' {
        $dest = Join-Path $script:caseRoot 'target.txt'
        [System.IO.File]::Copy($script:srcFile, $dest, $true)

        (Invoke-CheckUnchanged -Root $script:caseRoot -Source $script:srcFile -Target $dest -Mode Link).Line | Should -Be '다름: 일반 파일'

        (Invoke-Main -Source $script:srcFile -Target $dest -Mode Link).Line | Should -Be '바꿈: 링크 만듦'
        (Get-ChildItem -LiteralPath $script:caseRoot -Filter '*.bak-*').Count | Should -Be 0
        (Get-Item -LiteralPath $dest -Force).LinkType | Should -Be 'SymbolicLink'

        (Invoke-Main -Source $script:srcFile -Target $dest -Mode Link).Line | Should -Be '그대로'
    }

    It '⑧ 폴더가 있음 -> -Check 이어도 실패: 링크 자리에 폴더가 있다, 종료 코드 1' {
        $dest = Join-Path $script:caseRoot 'dir-here'
        New-Item -Path $dest -ItemType Directory -Force | Out-Null

        $rCheck = Invoke-CheckUnchanged -Root $script:caseRoot -Source $script:srcFile -Target $dest -Mode Link
        $rCheck.Line | Should -Be '실패: 링크 자리에 폴더가 있다'
        $rCheck.ExitCode | Should -Be 1

        $rFix = Invoke-Main -Source $script:srcFile -Target $dest -Mode Link
        $rFix.Line | Should -Be '실패: 링크 자리에 폴더가 있다'
        $rFix.ExitCode | Should -Be 1
    }

    It '⑨ 링크 만들기 예외 + Developer Mode 꺼짐 -> 실패: Developer Mode 꺼짐, 종료 코드 1' {
        Mock New-SymbolicLink { throw 'x' }
        Mock Test-DeveloperMode { $false }
        $dest = Join-Path $script:caseRoot 'target.txt'

        $r = Invoke-Main -Source $script:srcFile -Target $dest -Mode Link
        $r.Line | Should -Be '실패: Developer Mode 꺼짐'
        $r.ExitCode | Should -Be 1
    }

    It '⑩ 링크 만들기 예외 + Developer Mode 켜짐 -> 실패: 링크를 만들지 못했다: x, 종료 코드 1' {
        Mock New-SymbolicLink { throw 'x' }
        Mock Test-DeveloperMode { $true }
        $dest = Join-Path $script:caseRoot 'target.txt'

        $r = Invoke-Main -Source $script:srcFile -Target $dest -Mode Link
        $r.Line | Should -Be '실패: 링크를 만들지 못했다: x'
        $r.ExitCode | Should -Be 1
    }

    It '-Target 의 ~ 와 $env:이름 과 / 를 펼친다' {
        $env:PC_SETUP_TEST_LINKCONFIG_DEST = $script:caseRoot
        try {
            $dest = Join-Path $script:caseRoot 'env\target.txt'
            (Invoke-Main -Source $script:srcFile -Target '$env:PC_SETUP_TEST_LINKCONFIG_DEST/env/target.txt' -Mode Link).Line | Should -Be '바꿈: 링크 만듦'
            (Get-Item -LiteralPath $dest -Force).LinkType | Should -Be 'SymbolicLink'
        } finally {
            Remove-Item Env:PC_SETUP_TEST_LINKCONFIG_DEST -ErrorAction SilentlyContinue
        }

        Expand-SetupPath -Path '~/a/b' | Should -Be ($HOME + '\a\b')
        Expand-SetupPath -Path '~' | Should -Be $HOME
    }
}

Describe 'link-config.ps1 -Mode GitInclude' {
    BeforeEach {
        $testDriveFull = (Get-Item -LiteralPath 'TestDrive:/').FullName
        $script:caseRoot = Join-Path $testDriveFull ([guid]::NewGuid().ToString('N'))
        $script:repoCfgDir = Join-Path $script:caseRoot 'pc-setup\config'
        New-Item -Path $script:repoCfgDir -ItemType Directory -Force | Out-Null
        $script:srcFile = (New-Item -Path (Join-Path $script:repoCfgDir 'gitconfig') -ItemType File -Value "[core]`n`tautocrlf = input`n" -Force).FullName
        $script:desiredForward = $script:srcFile.Replace('\', '/')
        $script:utf8NoBom = [System.Text.UTF8Encoding]::new($false)
        $script:dest = Join-Path $script:caseRoot '.gitconfig'
    }

    It '파일 없음 -> -Check 다름: 파일 없음(안 만듦), 실행 새 파일(LF, BOM 없음), 두 번째 그대로' {
        $rCheck = Invoke-CheckUnchanged -Root $script:caseRoot -Source $script:srcFile -Target $script:dest -Mode GitInclude
        $rCheck.Line | Should -Be '다름: 파일 없음'
        Test-Path -LiteralPath $script:dest | Should -BeFalse

        $rFix = Invoke-Main -Source $script:srcFile -Target $script:dest -Mode GitInclude
        $rFix.Line | Should -Be '바꿈: 새 파일에 [include] 넣음'
        $rFix.ExitCode | Should -Be 0

        $bytes = [System.IO.File]::ReadAllBytes($script:dest)
        ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should -BeFalse
        $raw = [System.IO.File]::ReadAllText($script:dest, $script:utf8NoBom)
        $raw.Contains("`r`n") | Should -BeFalse
        $raw | Should -Be "[include]`npath = `"$($script:desiredForward)`"`n"

        (Invoke-Main -Source $script:srcFile -Target $script:dest -Mode GitInclude).Line | Should -Be '그대로'
    }

    It '불러오는 줄 없음(다른 섹션만) -> -Check 다름(안 바꿈), 실행 맨 위에 넣고 기존 줄 유지, 두 번째 그대로' {
        $existing = "# local comment`n`n[user]`n`tname = Test User`n"
        [System.IO.File]::WriteAllText($script:dest, $existing, $script:utf8NoBom)

        (Invoke-CheckUnchanged -Root $script:caseRoot -Source $script:srcFile -Target $script:dest -Mode GitInclude).Line | Should -Be '다름: 불러오는 줄 없음'

        (Invoke-Main -Source $script:srcFile -Target $script:dest -Mode GitInclude).Line | Should -Be '바꿈: 맨 위에 [include] 넣음'
        [System.IO.File]::ReadAllText($script:dest, $script:utf8NoBom) | Should -Be "[include]`n`tpath = `"$($script:desiredForward)`"`n$existing"

        (Invoke-Main -Source $script:srcFile -Target $script:dest -Mode GitInclude).Line | Should -Be '그대로'
    }

    It '같은 path 가 이미 있음(위치·대소문자·따옴표·구분자 무시) -> -Check·실행 모두 그대로' {
        $backSlashLower = $script:desiredForward.Replace('/', '\').ToLowerInvariant()
        $content = "[user]`n`tname = Local`n[Include]`n`tPath = $backSlashLower`n"
        [System.IO.File]::WriteAllText($script:dest, $content, $script:utf8NoBom)

        (Invoke-CheckUnchanged -Root $script:caseRoot -Source $script:srcFile -Target $script:dest -Mode GitInclude).Line | Should -Be '그대로'
        (Invoke-Main -Source $script:srcFile -Target $script:dest -Mode GitInclude).Line | Should -Be '그대로'
        [System.IO.File]::ReadAllText($script:dest, $script:utf8NoBom) | Should -Be $content
    }

    It '끝 세 부분은 같고 앞 경로가 다름 -> -Check 다름: 경로 다름(안 바꿈), 실행 그 줄만 바꿈, 두 번째 그대로' {
        $content = "# top comment`n[include]`n`tpath = `"C:/old-repo/pc-setup/config/gitconfig`"`n`n[user]`n`tname = Local`n"
        [System.IO.File]::WriteAllText($script:dest, $content, $script:utf8NoBom)

        (Invoke-CheckUnchanged -Root $script:caseRoot -Source $script:srcFile -Target $script:dest -Mode GitInclude).Line | Should -Be '다름: 경로 다름'

        (Invoke-Main -Source $script:srcFile -Target $script:dest -Mode GitInclude).Line | Should -Be '바꿈: [include] 경로 고침'
        [System.IO.File]::ReadAllText($script:dest, $script:utf8NoBom) | Should -Be "# top comment`n[include]`n`tpath = `"$($script:desiredForward)`"`n`n[user]`n`tname = Local`n"

        (Invoke-Main -Source $script:srcFile -Target $script:dest -Mode GitInclude).Line | Should -Be '그대로'
    }

    It '다른 파일을 부르는 [include] 만 있음 -> -Check 다름: 불러오는 줄 없음(안 바꿈), 실행 맨 위에 새로 넣고 기존 유지' {
        $existing = "[include]`n`tpath = `"C:/other/work.gitconfig`"`n"
        [System.IO.File]::WriteAllText($script:dest, $existing, $script:utf8NoBom)

        (Invoke-CheckUnchanged -Root $script:caseRoot -Source $script:srcFile -Target $script:dest -Mode GitInclude).Line | Should -Be '다름: 불러오는 줄 없음'

        (Invoke-Main -Source $script:srcFile -Target $script:dest -Mode GitInclude).Line | Should -Be '바꿈: 맨 위에 [include] 넣음'
        [System.IO.File]::ReadAllText($script:dest, $script:utf8NoBom) | Should -Be "[include]`n`tpath = `"$($script:desiredForward)`"`n$existing"

        (Invoke-Main -Source $script:srcFile -Target $script:dest -Mode GitInclude).Line | Should -Be '그대로'
    }

    It 'CRLF 파일 -> -Check 는 안 바꿈, 실행은 CRLF 를 유지하며 BOM 없는 UTF-8 로 저장, 두 번째 그대로' {
        $existingCrlf = "[user]`r`n`tname = CrlfUser`r`n"
        [System.IO.File]::WriteAllText($script:dest, $existingCrlf, $script:utf8NoBom)

        (Invoke-CheckUnchanged -Root $script:caseRoot -Source $script:srcFile -Target $script:dest -Mode GitInclude).Line | Should -Be '다름: 불러오는 줄 없음'

        (Invoke-Main -Source $script:srcFile -Target $script:dest -Mode GitInclude).Line | Should -Be '바꿈: 맨 위에 [include] 넣음'
        [System.IO.File]::ReadAllText($script:dest, $script:utf8NoBom) | Should -Be "[include]`r`n`tpath = `"$($script:desiredForward)`"`r`n$existingCrlf"

        (Invoke-Main -Source $script:srcFile -Target $script:dest -Mode GitInclude).Line | Should -Be '그대로'
    }

    It 'SourceKey 는 Source 전체 경로의 끝 세 부분이다' {
        Get-SourceKey -Source $script:srcFile | Should -Be 'pc-setup/config/gitconfig'
        Get-SourceKey -Source 'C:\a\b\c\d.txt' | Should -Be 'b/c/d.txt'
    }
}

Describe 'link-config.ps1 에러 처리' {
    BeforeEach {
        $testDriveFull = (Get-Item -LiteralPath 'TestDrive:/').FullName
        $script:caseRoot = Join-Path $testDriveFull ([guid]::NewGuid().ToString('N'))
        New-Item -Path $script:caseRoot -ItemType Directory -Force | Out-Null
        $script:srcFile = (New-Item -Path (Join-Path $script:caseRoot 'source.txt') -ItemType File -Value 'repo-content' -Force).FullName
        $script:dest = Join-Path $script:caseRoot 'target.txt'
    }

    It '-Source 빠짐 -> 실패: Source 가 없다' {
        $r = Invoke-Main -Target $script:dest -Mode Link
        $r.Line | Should -Be '실패: Source 가 없다'
        $r.ExitCode | Should -Be 1
    }

    It '-Target 빠짐 -> 실패: Target 가 없다' {
        $r = Invoke-Main -Source $script:srcFile -Mode Link
        $r.Line | Should -Be '실패: Target 가 없다'
        $r.ExitCode | Should -Be 1
    }

    It '-Mode 빠짐 -> 실패: Mode 가 없다' {
        $r = Invoke-Main -Source $script:srcFile -Target $script:dest
        $r.Line | Should -Be '실패: Mode 가 없다'
        $r.ExitCode | Should -Be 1
    }

    It '-Mode 가 Link·GitInclude 가 아님 -> 실패: Mode 는 Link 또는 GitInclude 다' {
        $r = Invoke-Main -Source $script:srcFile -Target $script:dest -Mode Copy
        $r.Line | Should -Be '실패: Mode 는 Link 또는 GitInclude 다'
        $r.ExitCode | Should -Be 1
    }

    It '-Source 파일 없음 -> 실패: 정본 파일이 없다: Source 경로' {
        $missing = Join-Path $script:caseRoot 'missing.txt'
        $r = Invoke-Main -Source $missing -Target $script:dest -Mode Link
        $r.Line | Should -Be "실패: 정본 파일이 없다: $missing"
        $r.ExitCode | Should -Be 1
    }

    It '-Target 의 환경 변수 없음 -> 실패: 환경 변수 이름 이 없다, 아무것도 안 만듦' {
        $before = Get-TreeSnapshot -Root $script:caseRoot
        $r = Invoke-Main -Source $script:srcFile -Target '$env:PC_SETUP_NO_SUCH_ENV_VAR_I150/a' -Mode Link
        $r.Line | Should -Be "실패: 환경 변수 'PC_SETUP_NO_SUCH_ENV_VAR_I150' 이 없다"
        $r.ExitCode | Should -Be 1
        Get-TreeSnapshot -Root $script:caseRoot | Should -Be $before
    }

    It '그 밖의 예외 -> 실패: 예외 메시지' {
        Mock Invoke-LinkFile { throw 'boom' }
        $r = Invoke-Main -Source $script:srcFile -Target $script:dest -Mode Link
        $r.Line | Should -Be '실패: boom'
        $r.ExitCode | Should -Be 1
    }
}

Describe 'link-config.ps1 (자식 pwsh -File)' {
    BeforeEach {
        $testDriveFull = (Get-Item -LiteralPath 'TestDrive:/').FullName
        $script:caseRoot = Join-Path $testDriveFull ([guid]::NewGuid().ToString('N'))
        New-Item -Path $script:caseRoot -ItemType Directory -Force | Out-Null
        $script:srcFile = (New-Item -Path (Join-Path $script:caseRoot 'source.txt') -ItemType File -Value 'repo-content' -Force).FullName
        $script:dest = Join-Path $script:caseRoot 'target.txt'
    }

    It '-Check 다름 -> 한 줄, 종료 코드 0' {
        $out = @(& pwsh -NoProfile -File $script:toolPath -Source $script:srcFile -Target $script:dest -Mode Link -Check)
        $LASTEXITCODE | Should -Be 0
        $out.Count | Should -Be 1
        $out[0] | Should -Be '다름: 없음'
    }

    It 'GitInclude 바꿈 다음 그대로 -> 각 한 줄, 종료 코드 0' {
        $out = @(& pwsh -NoProfile -File $script:toolPath -Source $script:srcFile -Target $script:dest -Mode GitInclude)
        $LASTEXITCODE | Should -Be 0
        $out | Should -Be @('바꿈: 새 파일에 [include] 넣음')

        $out = @(& pwsh -NoProfile -File $script:toolPath -Source $script:srcFile -Target $script:dest -Mode GitInclude)
        $LASTEXITCODE | Should -Be 0
        $out | Should -Be @('그대로')
    }

    It '-Mode 잘못됨 -> 한 줄 실패, 종료 코드 1' {
        $out = @(& pwsh -NoProfile -File $script:toolPath -Source $script:srcFile -Target $script:dest -Mode Copy)
        $LASTEXITCODE | Should -Be 1
        $out | Should -Be @('실패: Mode 는 Link 또는 GitInclude 다')
    }

    It '폴더 자리 -> 한 줄 실패, 종료 코드 1' {
        New-Item -Path $script:dest -ItemType Directory -Force | Out-Null
        $out = @(& pwsh -NoProfile -File $script:toolPath -Source $script:srcFile -Target $script:dest -Mode Link -Check)
        $LASTEXITCODE | Should -Be 1
        $out | Should -Be @('실패: 링크 자리에 폴더가 있다')
    }
}

Describe 'link-config.ps1 의존성' {
    It '옛 모듈 폴더(lib)를 import 하거나 dot-source 하지 않는다' {
        $text = Get-Content -LiteralPath $script:toolPath -Raw
        $text | Should -Not -Match '(?im)^\s*(Import-Module|using\s+module|\.\s+\S)'
        $text | Should -Not -Match '(?i)[\\/]lib[\\/]|''lib'''
    }
}
