using module ../lib/Declaration.psm1

BeforeAll {
    $declarationPath = Join-Path $PSScriptRoot '..' 'lib' 'Declaration.psm1'
    Import-Module $declarationPath -Force
    $itemScriptPath = Join-Path $PSScriptRoot '..' 'lib' 'ItemScript.psm1'
    Import-Module $itemScriptPath -Force
    $windowsSettingsPath = Join-Path $PSScriptRoot '..' 'lib' 'WindowsSettings.psm1'
    Import-Module $windowsSettingsPath -Force
}

Describe 'Invoke-RegistrySetting' {
    It 'DWord 같음 -> 그대로 (-Check 및 고치는 실행, Send-SettingChange 0번)' {
        $script:changeCalls = 0
        Mock -ModuleName WindowsSettings Send-SettingChange { $script:changeCalls++ }

        $path = 'TestRegistry:\CaseDwordSame'
        New-Item -Path $path -Force | Out-Null
        Set-ItemProperty -Path $path -Name 'dw' -Value 1 -Type DWord

        $entry = @{ Path = $path; Name = 'dw'; Type = 'DWord'; Value = 1 }

        $resCheck = Invoke-RegistrySetting -Entry $entry -Check $true
        $resCheck.Status | Should -Be '그대로'
        $resCheck.Detail | Should -Be ''

        $resFix = Invoke-RegistrySetting -Entry $entry -Check $false
        $resFix.Status | Should -Be '그대로'
        $resFix.Detail | Should -Be ''

        $script:changeCalls | Should -Be 0
    }

    It 'DWord 다름 -> -Check 는 다름 (지금 0, 선언 1), 고치는 실행은 바꿈 및 Send-SettingChange 1번' {
        $script:changeCalls = 0
        Mock -ModuleName WindowsSettings Send-SettingChange { $script:changeCalls++ }

        $path = 'TestRegistry:\CaseDwordDiff'
        New-Item -Path $path -Force | Out-Null
        Set-ItemProperty -Path $path -Name 'dw' -Value 0 -Type DWord

        $entry = @{ Path = $path; Name = 'dw'; Type = 'DWord'; Value = 1 }

        $resCheck = Invoke-RegistrySetting -Entry $entry -Check $true
        $resCheck.Status | Should -Be '다름'
        $resCheck.Detail | Should -Be '지금 0, 선언 1'
        $script:changeCalls | Should -Be 0

        $resFix = Invoke-RegistrySetting -Entry $entry -Check $false
        $resFix.Status | Should -Be '바꿈'
        $resFix.Detail | Should -Be ''
        (Get-Item -LiteralPath $path).GetValue('dw') | Should -Be 1
        $script:changeCalls | Should -Be 1
    }

    It 'DWord 없음 (키 없음) -> -Check 는 다름 (없음), 고치는 실행은 키/값 만들고 바꿈 및 Send-SettingChange 1번' {
        $script:changeCalls = 0
        Mock -ModuleName WindowsSettings Send-SettingChange { $script:changeCalls++ }

        $path = 'TestRegistry:\CaseNoKey'
        $entry = @{ Path = $path; Name = 'dw'; Type = 'DWord'; Value = 1 }

        $resCheck = Invoke-RegistrySetting -Entry $entry -Check $true
        $resCheck.Status | Should -Be '다름'
        $resCheck.Detail | Should -Be '없음'
        $script:changeCalls | Should -Be 0

        $resFix = Invoke-RegistrySetting -Entry $entry -Check $false
        $resFix.Status | Should -Be '바꿈'
        $resFix.Detail | Should -Be ''
        Test-Path -LiteralPath $path | Should -BeTrue
        (Get-Item -LiteralPath $path).GetValue('dw') | Should -Be 1
        $script:changeCalls | Should -Be 1
    }

    It 'DWord 없음 (키는 있고 값 없음) -> -Check 는 다름 (없음), 고치는 실행은 값 쓰고 바꿈 및 Send-SettingChange 1번' {
        $script:changeCalls = 0
        Mock -ModuleName WindowsSettings Send-SettingChange { $script:changeCalls++ }

        $path = 'TestRegistry:\CaseKeyNoVal'
        New-Item -Path $path -Force | Out-Null
        $entry = @{ Path = $path; Name = 'dw'; Type = 'DWord'; Value = 1 }

        $resCheck = Invoke-RegistrySetting -Entry $entry -Check $true
        $resCheck.Status | Should -Be '다름'
        $resCheck.Detail | Should -Be '없음'
        $script:changeCalls | Should -Be 0

        $resFix = Invoke-RegistrySetting -Entry $entry -Check $false
        $resFix.Status | Should -Be '바꿈'
        $resFix.Detail | Should -Be ''
        (Get-Item -LiteralPath $path).GetValue('dw') | Should -Be 1
        $script:changeCalls | Should -Be 1
    }

    It 'String 같음 -> 그대로 (-Check 및 고치는 실행, Send-SettingChange 0번)' {
        $script:changeCalls = 0
        Mock -ModuleName WindowsSettings Send-SettingChange { $script:changeCalls++ }

        $path = 'TestRegistry:\CaseStrSame'
        New-Item -Path $path -Force | Out-Null
        Set-ItemProperty -Path $path -Name 'str' -Value 'RemoteSigned' -Type String

        $entry = @{ Path = $path; Name = 'str'; Type = 'String'; Value = 'RemoteSigned' }

        $resCheck = Invoke-RegistrySetting -Entry $entry -Check $true
        $resCheck.Status | Should -Be '그대로'
        $resCheck.Detail | Should -Be ''

        $resFix = Invoke-RegistrySetting -Entry $entry -Check $false
        $resFix.Status | Should -Be '그대로'
        $resFix.Detail | Should -Be ''

        $script:changeCalls | Should -Be 0
    }

    It 'String 대소문자만 다름 (remotesigned) -> 다름 (지금 remotesigned, 선언 RemoteSigned)' {
        $script:changeCalls = 0
        Mock -ModuleName WindowsSettings Send-SettingChange { $script:changeCalls++ }

        $path = 'TestRegistry:\CaseStrCase'
        New-Item -Path $path -Force | Out-Null
        Set-ItemProperty -Path $path -Name 'str' -Value 'remotesigned' -Type String

        $entry = @{ Path = $path; Name = 'str'; Type = 'String'; Value = 'RemoteSigned' }

        $resCheck = Invoke-RegistrySetting -Entry $entry -Check $true
        $resCheck.Status | Should -Be '다름'
        $resCheck.Detail | Should -Be '지금 remotesigned, 선언 RemoteSigned'
        $script:changeCalls | Should -Be 0

        $resFix = Invoke-RegistrySetting -Entry $entry -Check $false
        $resFix.Status | Should -Be '바꿈'
        $resFix.Detail | Should -Be ''
        (Get-Item -LiteralPath $path).GetValue('str') | Should -Be 'RemoteSigned'
        $script:changeCalls | Should -Be 1
    }

    It '종류 다름 (String 자리에 DWord) -> 다름 (종류 String, 선언 DWord) 및 고치는 실행 시 DWord 로 바꿈' {
        $script:changeCalls = 0
        Mock -ModuleName WindowsSettings Send-SettingChange { $script:changeCalls++ }

        $path = 'TestRegistry:\CaseKindDiff'
        New-Item -Path $path -Force | Out-Null
        Set-ItemProperty -Path $path -Name 'val' -Value '1' -Type String

        $entry = @{ Path = $path; Name = 'val'; Type = 'DWord'; Value = 1 }

        $resCheck = Invoke-RegistrySetting -Entry $entry -Check $true
        $resCheck.Status | Should -Be '다름'
        $resCheck.Detail | Should -Be '종류 String, 선언 DWord'
        $script:changeCalls | Should -Be 0

        $resFix = Invoke-RegistrySetting -Entry $entry -Check $false
        $resFix.Status | Should -Be '바꿈'
        $resFix.Detail | Should -Be ''
        $item = Get-Item -LiteralPath $path
        [string]$item.GetValueKind('val') | Should -Be 'DWord'
        $item.GetValue('val') | Should -Be 1
        $script:changeCalls | Should -Be 1
    }

    It '읽기 권한 오류 -> -Check 는 확인 못 함: 관리자 필요, 고치는 실행은 실패: 관리자 필요' {
        $path = 'TestRegistry:\CasePermErr'
        New-Item -Path $path -Force | Out-Null
        $entry = @{ Path = $path; Name = 'val'; Type = 'DWord'; Value = 1 }

        Mock -ModuleName WindowsSettings Get-Item { throw [System.UnauthorizedAccessException]::new('액세스가 거부되었습니다') }

        $resCheck = Invoke-RegistrySetting -Entry $entry -Check $true
        $resCheck.Status | Should -Be '확인 못 함'
        $resCheck.Detail | Should -Be '관리자 필요'

        $resFix = Invoke-RegistrySetting -Entry $entry -Check $false
        $resFix.Status | Should -Be '실패'
        $resFix.Detail | Should -Be '관리자 필요'
    }

    It '쓰기에서 오류 -> 실패: 예외 메시지' {
        $path = 'TestRegistry:\CaseWriteErr'
        New-Item -Path $path -Force | Out-Null
        Set-ItemProperty -Path $path -Name 'val' -Value 0 -Type DWord
        $entry = @{ Path = $path; Name = 'val'; Type = 'DWord'; Value = 1 }

        Mock -ModuleName WindowsSettings Set-ItemProperty { throw [System.Exception]::new('레지스트리 쓰기 오류 발생') }

        $resFix = Invoke-RegistrySetting -Entry $entry -Check $false
        $resFix.Status | Should -Be '실패'
        $resFix.Detail | Should -Be '레지스트리 쓰기 오류 발생'
    }
}

Describe 'Get-WindowsSettingItems' {
    It '레지스트리 줄 HKLM -> Elevated=$true, HKCU -> Elevated=$false, Stage=Windows 설정' {
        $content = @"
@{
    Items = @(
        @{
            Id    = 'RegHklm'
            Path  = 'HKLM:\SOFTWARE\Test'
            Name  = 'HklmVal'
            Type  = 'DWord'
            Value = 1
        }
        @{
            Id    = 'RegHkcu'
            Path  = 'HKCU:\Software\Test'
            Name  = 'HkcuVal'
            Type  = 'DWord'
            Value = 1
        }
    )
}
"@
        Set-Content -Path 'TestDrive:/windows-settings.psd1' -Value $content
        $root = (Get-Item 'TestDrive:/').FullName
        $items = Get-WindowsSettingItems -Root $root

        $items.Count | Should -Be 2
        $items[0].Id | Should -Be 'RegHklm'
        $items[0].Stage | Should -Be 'Windows 설정'
        $items[0].Elevated | Should -BeTrue

        $items[1].Id | Should -Be 'RegHkcu'
        $items[1].Stage | Should -Be 'Windows 설정'
        $items[1].Elevated | Should -BeFalse
    }

    It '스크립트 줄 + windows/<Id>.ps1 있음 -> 항목, Invoke 가 그 스크립트 결과를 돌려줌' {
        $content = @"
@{
    Items = @(
        @{
            Id       = 'CustomScript'
            Script   = `$true
            Elevated = `$true
        }
    )
}
"@
        Set-Content -Path 'TestDrive:/windows-settings.psd1' -Value $content
        $winDir = Join-Path 'TestDrive:/' 'windows'
        New-Item -Path $winDir -ItemType Directory -Force | Out-Null
        $scriptContent = @"
param([switch]`$Check)
if (`$Check) {
    Write-Output '다름'
} else {
    Write-Output '바꿈'
}
"@
        Set-Content -Path (Join-Path $winDir 'CustomScript.ps1') -Value $scriptContent

        $root = (Get-Item 'TestDrive:/').FullName
        $items = Get-WindowsSettingItems -Root $root
        $items.Count | Should -Be 1
        $items[0].Id | Should -Be 'CustomScript'
        $items[0].Stage | Should -Be 'Windows 설정'
        $items[0].Elevated | Should -BeTrue

        $resCheck = & $items[0].Invoke $true
        $resCheck.Status | Should -Be '다름'

        $resFix = & $items[0].Invoke $false
        $resFix.Status | Should -Be '바꿈'
    }

    It '스크립트 줄 + 스크립트 없음 -> DeclarationException 에 「스크립트가 없다」' {
        $content = @"
@{
    Items = @(
        @{
            Id     = 'MissingScript'
            Script = `$true
        }
    )
}
"@
        Set-Content -Path 'TestDrive:/windows-settings.psd1' -Value $content
        $root = (Get-Item 'TestDrive:/').FullName

        try {
            Get-WindowsSettingItems -Root $root
            throw '예외가 발생해야 합니다'
        } catch [DeclarationException] {
            $_.Exception.Problems.Count | Should -Be 1
            $_.Exception.Problems[0] | Should -Be 'windows-settings.psd1:3: 스크립트가 없다: windows/MissingScript.ps1'
        }
    }

    Context 'Validate 문제 문구 다섯 가지 각각' {
        It '1: 스크립트 항목에 Path·Name·Type·Value 중 키가 있음 -> 스크립트 항목에는 ''<키>'' 를 쓰지 않는다' {
            $content = @"
@{
    Items = @(
        @{
            Id     = 'ScriptWithRegKeys'
            Script = `$true
            Path   = 'HKCU:\Software\Test'
            Name   = 'Val'
        }
    )
}
"@
            Set-Content -Path 'TestDrive:/windows-settings.psd1' -Value $content
            $root = (Get-Item 'TestDrive:/').FullName
            try {
                Get-WindowsSettingItems -Root $root
                throw '예외가 발생해야 합니다'
            } catch [DeclarationException] {
                $_.Exception.Problems | Should -Contain "windows-settings.psd1:3: 스크립트 항목에는 'Path' 를 쓰지 않는다"
                $_.Exception.Problems | Should -Contain "windows-settings.psd1:3: 스크립트 항목에는 'Name' 를 쓰지 않는다"
            }
        }

        It '2: 레지스트리 항목에 필수 키 빠짐 -> 레지스트리 항목에 ''<키>'' 가 없다' {
            $content = @"
@{
    Items = @(
        @{
            Id   = 'RegMissingKeys'
            Path = 'HKCU:\Software\Test'
            Name = 'Val'
        }
    )
}
"@
            Set-Content -Path 'TestDrive:/windows-settings.psd1' -Value $content
            $root = (Get-Item 'TestDrive:/').FullName
            try {
                Get-WindowsSettingItems -Root $root
                throw '예외가 발생해야 합니다'
            } catch [DeclarationException] {
                $_.Exception.Problems | Should -Contain "windows-settings.psd1:3: 레지스트리 항목에 'Type' 가 없다"
                $_.Exception.Problems | Should -Contain "windows-settings.psd1:3: 레지스트리 항목에 'Value' 가 없다"
            }
        }

        It '3: 레지스트리 항목에 Elevated 키 있음 -> 레지스트리 항목의 승격 여부는 Path 로 정한다' {
            $content = @"
@{
    Items = @(
        @{
            Id       = 'RegWithElevated'
            Path     = 'HKCU:\Software\Test'
            Name     = 'Val'
            Type     = 'DWord'
            Value    = 1
            Elevated = `$true
        }
    )
}
"@
            Set-Content -Path 'TestDrive:/windows-settings.psd1' -Value $content
            $root = (Get-Item 'TestDrive:/').FullName
            try {
                Get-WindowsSettingItems -Root $root
                throw '예외가 발생해야 합니다'
            } catch [DeclarationException] {
                $_.Exception.Problems | Should -Contain 'windows-settings.psd1:3: 레지스트리 항목의 승격 여부는 Path 로 정한다'
            }
        }

        It '4: 레지스트리 항목 Path 가 HKLM:\ 또는 HKCU:\ 로 시작하지 않음 -> Path 는 HKLM:\ 또는 HKCU:\ 로 시작한다' {
            $content = @"
@{
    Items = @(
        @{
            Id    = 'RegBadPath'
            Path  = 'HKCR:\Software\Test'
            Name  = 'Val'
            Type  = 'DWord'
            Value = 1
        }
    )
}
"@
            Set-Content -Path 'TestDrive:/windows-settings.psd1' -Value $content
            $root = (Get-Item 'TestDrive:/').FullName
            try {
                Get-WindowsSettingItems -Root $root
                throw '예외가 발생해야 합니다'
            } catch [DeclarationException] {
                $_.Exception.Problems | Should -Contain 'windows-settings.psd1:3: Path 는 HKLM:\ 또는 HKCU:\ 로 시작한다'
            }
        }

        It '5: Script 또는 Elevated 값이 `$true`/`$false` 가 아님 -> Script·Elevated 값은 `$true`/`$false` 여야 한다' {
            $content = @"
@{
    Items = @(
        @{
            Id     = 'BadBoolScript'
            Script = 'invalid'
        }
        @{
            Id       = 'BadBoolElevated'
            Path     = 'HKCU:\Software\Test'
            Name     = 'Val'
            Type     = 'DWord'
            Value    = 1
            Elevated = 123
        }
    )
}
"@
            Set-Content -Path 'TestDrive:/windows-settings.psd1' -Value $content
            $root = (Get-Item 'TestDrive:/').FullName
            try {
                Get-WindowsSettingItems -Root $root
                throw '예외가 발생해야 합니다'
            } catch [DeclarationException] {
                $_.Exception.Problems | Should -Contain 'windows-settings.psd1:3: Script·Elevated 값은 $true/$false 여야 한다'
                $_.Exception.Problems | Should -Contain 'windows-settings.psd1:7: Script·Elevated 값은 $true/$false 여야 한다'
            }
        }
    }
}

Describe '실제 선언' {
    It '저장소의 pc-setup/windows-settings.psd1 이 검사를 통과하고, Id 11개가 표 순서이며, DeveloperMode·LongPaths·RemoteDesktop·Hibernate 만 Elevated' {
        $pcSetupRoot = Join-Path $PSScriptRoot '..'
        $items = Get-WindowsSettingItems -Root $pcSetupRoot

        $items.Count | Should -Be 11

        $expectedIds = @(
            'PowerShell51ExecutionPolicy',
            'DeveloperMode',
            'LongPaths',
            'RemoteDesktop',
            'Hibernate',
            'Power',
            'ShowFileExtensions',
            'ShowHiddenFiles',
            'DarkModeApps',
            'DarkModeSystem',
            'TaskbarSearchIcon'
        )

        for ($i = 0; $i -lt 11; $i++) {
            $items[$i].Id | Should -Be $expectedIds[$i]
            $items[$i].Stage | Should -Be 'Windows 설정'
        }

        $elevatedIds = @($items | Where-Object { $_.Elevated } | ForEach-Object { $_.Id })
        $elevatedIds | Should -Be @('DeveloperMode', 'LongPaths', 'RemoteDesktop', 'Hibernate')

        $nonElevatedIds = @($items | Where-Object { -not $_.Elevated } | ForEach-Object { $_.Id })
        $nonElevatedIds.Count | Should -Be 7
    }
}
