using module ../lib/Declaration.psm1

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'lib' 'Declaration.psm1'
    Import-Module $modulePath -Force

    $script:defaultSchema = @{
        Key      = 'Id'
        Required = @('Id')
        Allowed  = @('Id', 'Path', 'Name', 'Type', 'Value', 'Script', 'Elevated')
        Enums    = @{ Type = @('DWord', 'String') }
    }
}

Describe 'Read-Declaration' {
    It '1: 정상 파일, 항목 3개, 주석 줄 있음 -> 항목 3개, 각 Line 이 실제 줄 번호' {
        $content = @"
@{
    # 최상위 주석
    Items = @(
        # 항목 1 주석
        @{
            Id   = 'item1'
            Path = 'C:\path1'
        }
        # 항목 2 주석
        @{
            Id   = 'item2'
            Path = 'C:\path2'
        }
        # 항목 3 주석
        @{
            Id   = 'item3'
            Path = 'C:\path3'
        }
    )
}
"@
        Set-Content -Path 'TestDrive:/case1.psd1' -Value $content
        $result = Read-Declaration -Path 'TestDrive:/case1.psd1' -Schema $script:defaultSchema
        $result.Count | Should -Be 3
        $result[0].Id | Should -Be 'item1'
        $result[0].Line | Should -Be 5
        $result[1].Id | Should -Be 'item2'
        $result[1].Line | Should -Be 10
        $result[2].Id | Should -Be 'item3'
        $result[2].Line | Should -Be 15

        $props = $result[0].PSObject.Properties | ForEach-Object { $_.Name }
        $props[0] | Should -Be 'Id'
        $props[1] | Should -Be 'Path'
        $props[2] | Should -Be 'Line'
    }

    It '2: Items = @() -> 빈 배열, 문제 없음' {
        Set-Content -Path 'TestDrive:/case2.psd1' -Value '@{ Items = @() }'
        $result = Read-Declaration -Path 'TestDrive:/case2.psd1' -Schema $script:defaultSchema
        $null -ne $result | Should -BeTrue
        $result -is [array] | Should -BeTrue
        $result.Count | Should -Be 0
    }

    It '3: 닫는 괄호 빠짐 -> 문법 오류 문제' {
        Set-Content -Path 'TestDrive:/case3.psd1' -Value '@{ Items = @( '
        try {
            Read-Declaration -Path 'TestDrive:/case3.psd1' -Schema $script:defaultSchema
            throw '예외가 발생해야 합니다'
        } catch [DeclarationException] {
            $_.Exception.Problems.Count | Should -BeGreaterThan 0
            $_.Exception.Problems[0] | Should -Match '^case3\.psd1:\d+: 문법 오류:'
        }
    }

    It '4: 최상위에 Items 대신 Apps -> 최상위 모양 문제' {
        Set-Content -Path 'TestDrive:/case4.psd1' -Value '@{ Apps = @() }'
        try {
            Read-Declaration -Path 'TestDrive:/case4.psd1' -Schema $script:defaultSchema
            throw '예외가 발생해야 합니다'
        } catch [DeclarationException] {
            $_.Exception.Problems.Count | Should -Be 1
            $_.Exception.Problems[0] | Should -Be 'case4.psd1:1: 최상위는 @{ Items = @( ... ) } 이어야 한다'
        }
    }

    It '5: 항목에 모르는 키 -> 모르는 키 문제, 줄 번호 맞음' {
        $content = @"
@{
    Items = @(
        @{
            Id      = 'test'
            Unknown = 'value'
        }
    )
}
"@
        Set-Content -Path 'TestDrive:/case5.psd1' -Value $content
        try {
            Read-Declaration -Path 'TestDrive:/case5.psd1' -Schema $script:defaultSchema
            throw '예외가 발생해야 합니다'
        } catch [DeclarationException] {
            $_.Exception.Problems.Count | Should -Be 1
            $_.Exception.Problems[0] | Should -Be "case5.psd1:3: 모르는 키 'Unknown'"
        }
    }

    It '6: 필수 키 빠짐 -> 필수 키 문제' {
        $content = @"
@{
    Items = @(
        @{
            Path = 'C:\foo'
        }
    )
}
"@
        Set-Content -Path 'TestDrive:/case6.psd1' -Value $content
        try {
            Read-Declaration -Path 'TestDrive:/case6.psd1' -Schema $script:defaultSchema
            throw '예외가 발생해야 합니다'
        } catch [DeclarationException] {
            $_.Exception.Problems.Count | Should -Be 1
            $_.Exception.Problems[0] | Should -Be "case6.psd1:3: 필수 키 'Id' 가 없다"
        }
    }

    It '7: 같은 Id 두 항목(2번째 줄·5번째 줄) -> 5번째 줄에 2번 줄과 겹친다' {
        $content = "@{ Items = @(`n  @{ Id = 'same' }`n  # 주석1`n  # 주석2`n  @{ Id = 'same' }`n) }"
        Set-Content -Path 'TestDrive:/case7.psd1' -Value $content
        try {
            Read-Declaration -Path 'TestDrive:/case7.psd1' -Schema $script:defaultSchema
            throw '예외가 발생해야 합니다'
        } catch [DeclarationException] {
            $_.Exception.Problems.Count | Should -Be 1
            $_.Exception.Problems[0] | Should -Be "case7.psd1:5: 'Id' 값 'same' 이 2번 줄과 겹친다"
        }
    }

    It '8: 열거형 키 값이 목록 밖 -> 허용 값 문제(허용 값 나열)' {
        $content = @"
@{
    Items = @(
        @{
            Id   = 'item1'
            Type = 'Invalid'
        }
    )
}
"@
        Set-Content -Path 'TestDrive:/case8.psd1' -Value $content
        try {
            Read-Declaration -Path 'TestDrive:/case8.psd1' -Schema $script:defaultSchema
            throw '예외가 발생해야 합니다'
        } catch [DeclarationException] {
            $_.Exception.Problems.Count | Should -Be 1
            $_.Exception.Problems[0] | Should -Be "case8.psd1:3: 'Type' 값 'Invalid' 은 허용되지 않는다 (허용: DWord, String)"
        }
    }

    It '9: 값에 식(큰따옴표, $(...), 변수) -> 값에 식이 들어 있다, 작은따옴표는 정상' {
        $content = @"
@{
    Items = @(
        @{
            Id   = 'item1'
            Path = "`$env:USERPROFILE"
        }
        @{
            Id   = 'item2'
            Path = `$(Get-Date)
        }
        @{
            Id   = 'item3'
            Path = `$x
        }
        @{
            Id   = 'item4'
            Path = '`$env:USERPROFILE'
        }
    )
}
"@
        Set-Content -Path 'TestDrive:/case9.psd1' -Value $content
        try {
            Read-Declaration -Path 'TestDrive:/case9.psd1' -Schema $script:defaultSchema
            throw '예외가 발생해야 합니다'
        } catch [DeclarationException] {
            $_.Exception.Problems.Count | Should -Be 3
            $_.Exception.Problems[0] | Should -Be 'case9.psd1:3: 값에 식이 들어 있다'
            $_.Exception.Problems[1] | Should -Be 'case9.psd1:7: 값에 식이 들어 있다'
            $_.Exception.Problems[2] | Should -Be 'case9.psd1:11: 값에 식이 들어 있다'
        }
    }

    It '10: 한 파일에 문제 3개(서로 다른 줄) -> 예외 하나에 Problems 3개' {
        $content = @"
@{
    Items = @(
        @{
            Id     = 'item1'
            BadKey = 'val'
        }
        @{
            Id   = 'item2'
            Type = 'Invalid'
        }
        @{
            Path = 'C:\foo'
        }
    )
}
"@
        Set-Content -Path 'TestDrive:/case10.psd1' -Value $content
        try {
            Read-Declaration -Path 'TestDrive:/case10.psd1' -Schema $script:defaultSchema
            throw '예외가 발생해야 합니다'
        } catch [DeclarationException] {
            $_.Exception.Problems.Count | Should -Be 3
            $_.Exception.Problems[0] | Should -Be "case10.psd1:3: 모르는 키 'BadKey'"
            $_.Exception.Problems[1] | Should -Be "case10.psd1:7: 'Type' 값 'Invalid' 은 허용되지 않는다 (허용: DWord, String)"
            $_.Exception.Problems[2] | Should -Be "case10.psd1:11: 필수 키 'Id' 가 없다"
        }
    }

    It '11: Validate 가 문자열 하나 돌려줌 -> 그 문자열이 줄 번호와 함께 문제로' {
        $schemaWithValidate = @{
            Key      = 'Id'
            Required = @('Id')
            Allowed  = @('Id', 'Path')
            Validate = {
                param($item)
                if ($item.Path -eq 'bad') {
                    return @('Path 값이 올바르지 않다')
                }
            }
        }
        $content = @"
@{
    Items = @(
        @{
            Id   = 'item1'
            Path = 'bad'
        }
    )
}
"@
        Set-Content -Path 'TestDrive:/case11.psd1' -Value $content
        try {
            Read-Declaration -Path 'TestDrive:/case11.psd1' -Schema $schemaWithValidate
            throw '예외가 발생해야 합니다'
        } catch [DeclarationException] {
            $_.Exception.Problems.Count | Should -Be 1
            $_.Exception.Problems[0] | Should -Be 'case11.psd1:3: Path 값이 올바르지 않다'
        }
    }

    It '12: 키 대소문자 다름(id) -> 모르는 키 + 빠진 필수 키' {
        $content = @"
@{
    Items = @(
        @{
            id = 'test'
        }
    )
}
"@
        Set-Content -Path 'TestDrive:/case12.psd1' -Value $content
        try {
            Read-Declaration -Path 'TestDrive:/case12.psd1' -Schema $script:defaultSchema
            throw '예외가 발생해야 합니다'
        } catch [DeclarationException] {
            $_.Exception.Problems.Count | Should -Be 2
            $_.Exception.Problems[0] | Should -Be "case12.psd1:3: 모르는 키 'id'"
            $_.Exception.Problems[1] | Should -Be "case12.psd1:3: 필수 키 'Id' 가 없다"
        }
    }

    It '파일이 없으면 DeclarationException 을 던진다' {
        try {
            Read-Declaration -Path 'TestDrive:/nonexistent.psd1' -Schema $script:defaultSchema
            throw '예외가 발생해야 합니다'
        } catch [DeclarationException] {
            $_.Exception.Problems.Count | Should -Be 1
            $_.Exception.Problems[0] | Should -Be 'nonexistent.psd1:0: 파일이 없다'
        }
    }

    It '선언 파일 안의 코드를 실행하지 않는다 ($(New-Item) 미실행)' {
        $canaryPath = Join-Path ([System.IO.Path]::GetTempPath()) "canary-$([System.Guid]::NewGuid().ToString()).txt"
        if (Test-Path $canaryPath) { Remove-Item $canaryPath -Force }
        $content = "@{ Items = @( @{ Id = 'test'; Script = `$(New-Item -Path '$canaryPath' -ItemType File) } ) }"
        Set-Content -Path 'TestDrive:/security.psd1' -Value $content
        try {
            Read-Declaration -Path 'TestDrive:/security.psd1' -Schema $script:defaultSchema
            throw '예외가 발생해야 합니다'
        } catch [DeclarationException] {
            $_.Exception.Problems[0] | Should -Match '값에 식이 들어 있다'
        }
        (Test-Path $canaryPath) | Should -BeFalse
    }
}

Describe 'Expand-SetupPath' {
    It '~ 로 시작하면 $HOME 으로 바꾼다' {
        Expand-SetupPath '~' | Should -Be $HOME
        Expand-SetupPath '~/.nanorc' | Should -Be (Join-Path $HOME '.nanorc')
        Expand-SetupPath '~\.nanorc' | Should -Be (Join-Path $HOME '.nanorc')
    }

    It '~ 중간에 있는 경우는 그대로 둔다' {
        Expand-SetupPath 'foo/~/bar' | Should -Be 'foo\~\bar'
        Expand-SetupPath 'C:/foo~bar' | Should -Be 'C:\foo~bar'
    }

    It '$env: 하나를 환경 변수 값으로 바꾼다' {
        $env:TEST_EXPAND_A = 'hello'
        try {
            Expand-SetupPath '$env:TEST_EXPAND_A/world' | Should -Be 'hello\world'
        } finally {
            Remove-Item env:TEST_EXPAND_A -ErrorAction SilentlyContinue
        }
    }

    It '$env: 둘을 환경 변수 값으로 바꾼다' {
        $env:TEST_EXPAND_A = 'first'
        $env:TEST_EXPAND_B = 'second'
        try {
            Expand-SetupPath '$env:TEST_EXPAND_A/$env:TEST_EXPAND_B/file.txt' | Should -Be 'first\second\file.txt'
        } finally {
            Remove-Item env:TEST_EXPAND_A -ErrorAction SilentlyContinue
            Remove-Item env:TEST_EXPAND_B -ErrorAction SilentlyContinue
        }
    }

    It '없는 환경 변수이면 예외를 던진다' {
        { Expand-SetupPath '$env:DEFINITELY_NOT_EXISTING_ENV_VAR/sub' } | Should -Throw "환경 변수 'DEFINITELY_NOT_EXISTING_ENV_VAR' 이 없다*"
    }

    It '/ 가 섞여 있으면 \ 로 바꾼다' {
        Expand-SetupPath 'a/b/c/d' | Should -Be 'a\b\c\d'
    }
}
