using module ./Declaration.psm1

Import-Module (Join-Path $PSScriptRoot 'Declaration.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'ItemScript.psm1') -Force

if (-not ([System.Management.Automation.PSTypeName]'Win32SettingChange').Type) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class Win32SettingChange {
    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern IntPtr SendMessageTimeout(
        IntPtr hWnd,
        uint Msg,
        UIntPtr wParam,
        string lParam,
        uint fuFlags,
        uint uTimeout,
        out UIntPtr lpdwResult
    );
}
"@
}

function Send-SettingChange {
    # WM_SETTINGCHANGE 를 모든 최상위 창에 보낸다(SendMessageTimeout, HWND_BROADCAST, SMTO_ABORTIFHUNG, 5초). 테스트는 Mock 한다.
    $result = [UIntPtr]::Zero
    [Win32SettingChange]::SendMessageTimeout([IntPtr]0xffff, 0x001A, [UIntPtr]::Zero, 'Environment', 2, 5000, [ref]$result) | Out-Null
}

$script:WindowsSettingsSchema = @{
    Key      = 'Id'
    Required = @('Id')
    Allowed  = @('Id', 'Path', 'Name', 'Type', 'Value', 'Script', 'Elevated')
    Enums    = @{ Type = @('DWord', 'String') }
    Validate = {
        param($item)
        $problems = [System.Collections.Generic.List[string]]::new()
        $props = $item.PSObject.Properties

        $hasInvalidBool = $false
        if ($props['Script'] -and ($item.Script -isnot [bool])) {
            $hasInvalidBool = $true
        }
        if ($props['Elevated'] -and ($item.Elevated -isnot [bool])) {
            $hasInvalidBool = $true
        }
        if ($hasInvalidBool) {
            $problems.Add('Script·Elevated 값은 $true/$false 여야 한다')
        }

        $isScript = ($props['Script'] -and $item.Script -eq $true)
        if ($isScript) {
            foreach ($k in @('Path', 'Name', 'Type', 'Value')) {
                if ($props[$k]) {
                    $problems.Add("스크립트 항목에는 '$k' 를 쓰지 않는다")
                }
            }
        } else {
            foreach ($k in @('Path', 'Name', 'Type', 'Value')) {
                if (-not $props[$k]) {
                    $problems.Add("레지스트리 항목에 '$k' 가 없다")
                }
            }
            if ($props['Elevated']) {
                $problems.Add('레지스트리 항목의 승격 여부는 Path 로 정한다')
            }
            if ($props['Path']) {
                $pathVal = [string]$item.Path
                if (-not ($pathVal.StartsWith('HKLM:\') -or $pathVal.StartsWith('HKCU:\'))) {
                    $problems.Add('Path 는 HKLM:\ 또는 HKCU:\ 로 시작한다')
                }
            }
        }

        return [string[]]$problems.ToArray()
    }
}

function Get-WindowsSettingItems {
    # <Root>\windows-settings.psd1 을 읽고 검사해 항목 목록을 돌려준다(Stage = 'Windows 설정').
    # 문제가 있으면 DeclarationException.
    param([Parameter(Mandatory)][string]$Root)

    $settingsPath = Join-Path $Root 'windows-settings.psd1'
    $items = $null
    $problems = [System.Collections.Generic.List[string]]::new()

    try {
        $items = Read-Declaration -Path $settingsPath -Schema $script:WindowsSettingsSchema
    } catch [DeclarationException] {
        foreach ($p in $_.Exception.Problems) {
            $problems.Add($p)
        }
    }

    if ($null -ne $items) {
        $fileName = Split-Path -Leaf $settingsPath
        foreach ($item in $items) {
            $props = $item.PSObject.Properties
            if ($props['Script'] -and $item.Script -eq $true) {
                $scriptPath = Join-Path $Root 'windows' "$($item.Id).ps1"
                if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
                    $problems.Add("${fileName}:$($item.Line): 스크립트가 없다: windows/$($item.Id).ps1")
                }
            }
        }
    }

    if ($problems.Count -gt 0) {
        throw [DeclarationException]::new([string[]]$problems.ToArray())
    }

    $stageItems = [System.Collections.Generic.List[object]]::new()
    $thisModule = $ExecutionContext.SessionState.Module
    foreach ($item in $items) {
        $props = $item.PSObject.Properties
        $isScript = ($props['Script'] -and $item.Script -eq $true)
        if ($isScript) {
            $elevated = if ($props['Elevated']) { [bool]$item.Elevated } else { $false }
            $scriptPath = Join-Path $Root 'windows' "$($item.Id).ps1"
            $invoke = {
                param([bool]$Check)
                & $thisModule {
                    param($p, $c)
                    Invoke-ItemScript -Path $p -Check:$c
                } $scriptPath $Check
            }.GetNewClosure()

            $stageItems.Add([pscustomobject]@{
                Stage    = 'Windows 설정'
                Id       = $item.Id
                Elevated = $elevated
                Invoke   = $invoke
            })
        } else {
            $pathVal = [string]$item.Path
            $elevated = $pathVal.StartsWith('HKLM:')
            $entry = $item
            $invoke = {
                param([bool]$Check)
                & $thisModule {
                    param($e, $c)
                    Invoke-RegistrySetting -Entry $e -Check $c
                } $entry $Check
            }.GetNewClosure()

            $stageItems.Add([pscustomobject]@{
                Stage    = 'Windows 설정'
                Id       = $item.Id
                Elevated = $elevated
                Invoke   = $invoke
            })
        }
    }

    return ,([pscustomobject[]]$stageItems.ToArray())
}

function Invoke-RegistrySetting {
    # 레지스트리 값 하나를 확인하거나 맞춘다 → @{ Status; Detail }
    param(
        [Parameter(Mandatory)]$Entry,     # Path, Name, Type, Value 를 가진 객체
        [bool]$Check
    )

    $path = if ($Entry -is [System.Collections.IDictionary]) { $Entry['Path'] } else { $Entry.Path }
    $name = if ($Entry -is [System.Collections.IDictionary]) { $Entry['Name'] } else { $Entry.Name }
    $type = if ($Entry -is [System.Collections.IDictionary]) { $Entry['Type'] } else { $Entry.Type }
    $expectedValue = if ($Entry -is [System.Collections.IDictionary]) { $Entry['Value'] } else { $Entry.Value }

    $keyItem = $null
    $keyExists = $false
    try {
        if (Test-Path -LiteralPath $path) {
            $keyItem = Get-Item -LiteralPath $path
            $keyExists = $true
        }
    } catch [System.UnauthorizedAccessException], [System.Security.SecurityException] {
        if ($Check) {
            return @{ Status = '확인 못 함'; Detail = '관리자 필요' }
        } else {
            return @{ Status = '실패'; Detail = '관리자 필요' }
        }
    } catch {
        if ($_.Exception -is [System.UnauthorizedAccessException] -or $_.Exception -is [System.Security.SecurityException] -or $_.Exception.InnerException -is [System.UnauthorizedAccessException]) {
            if ($Check) {
                return @{ Status = '확인 못 함'; Detail = '관리자 필요' }
            } else {
                return @{ Status = '실패'; Detail = '관리자 필요' }
            }
        }
        return @{ Status = '실패'; Detail = $_.Exception.Message }
    }

    $valueExists = $false
    if ($keyExists) {
        try {
            $names = @($keyItem.GetValueNames())
            $valueExists = ($names -contains $name)
        } catch [System.UnauthorizedAccessException], [System.Security.SecurityException] {
            if ($Check) {
                return @{ Status = '확인 못 함'; Detail = '관리자 필요' }
            } else {
                return @{ Status = '실패'; Detail = '관리자 필요' }
            }
        } catch {
            if ($_.Exception -is [System.UnauthorizedAccessException] -or $_.Exception -is [System.Security.SecurityException] -or $_.Exception.InnerException -is [System.UnauthorizedAccessException]) {
                if ($Check) {
                    return @{ Status = '확인 못 함'; Detail = '관리자 필요' }
                } else {
                    return @{ Status = '실패'; Detail = '관리자 필요' }
                }
            }
            return @{ Status = '실패'; Detail = $_.Exception.Message }
        }
    }

    if (-not $keyExists -or -not $valueExists) {
        if ($Check) {
            return @{ Status = '다름'; Detail = '없음' }
        }
        try {
            if (-not $keyExists) {
                $null = New-Item -Path $path -Force
            }
            $targetVal = if ($type -eq 'DWord') { [int]$expectedValue } else { [string]$expectedValue }
            Set-ItemProperty -Path $path -Name $name -Value $targetVal -Type $type
            Send-SettingChange
            return @{ Status = '바꿈'; Detail = '' }
        } catch {
            return @{ Status = '실패'; Detail = $_.Exception.Message }
        }
    }

    $currentKind = $null
    $currentVal = $null
    try {
        $currentKind = [string]($keyItem.GetValueKind($name))
        $currentVal = $keyItem.GetValue($name)
    } catch [System.UnauthorizedAccessException], [System.Security.SecurityException] {
        if ($Check) {
            return @{ Status = '확인 못 함'; Detail = '관리자 필요' }
        } else {
            return @{ Status = '실패'; Detail = '관리자 필요' }
        }
    } catch {
        if ($_.Exception -is [System.UnauthorizedAccessException] -or $_.Exception -is [System.Security.SecurityException] -or $_.Exception.InnerException -is [System.UnauthorizedAccessException]) {
            if ($Check) {
                return @{ Status = '확인 못 함'; Detail = '관리자 필요' }
            } else {
                return @{ Status = '실패'; Detail = '관리자 필요' }
            }
        }
        return @{ Status = '실패'; Detail = $_.Exception.Message }
    }

    if ($currentKind -ne $type) {
        if ($Check) {
            return @{ Status = '다름'; Detail = "종류 $currentKind, 선언 $type" }
        }
        try {
            $targetVal = if ($type -eq 'DWord') { [int]$expectedValue } else { [string]$expectedValue }
            Set-ItemProperty -Path $path -Name $name -Value $targetVal -Type $type
            Send-SettingChange
            return @{ Status = '바꿈'; Detail = '' }
        } catch {
            return @{ Status = '실패'; Detail = $_.Exception.Message }
        }
    }

    $isEqual = $false
    if ($type -eq 'DWord') {
        $isEqual = ([int]$currentVal -eq [int]$expectedValue)
    } else {
        $isEqual = ([string]$currentVal -ceq [string]$expectedValue)
    }

    if ($isEqual) {
        return @{ Status = '그대로'; Detail = '' }
    }

    if ($Check) {
        return @{ Status = '다름'; Detail = "지금 $currentVal, 선언 $expectedValue" }
    }

    try {
        $targetVal = if ($type -eq 'DWord') { [int]$expectedValue } else { [string]$expectedValue }
        Set-ItemProperty -Path $path -Name $name -Value $targetVal -Type $type
        Send-SettingChange
        return @{ Status = '바꿈'; Detail = '' }
    } catch {
        return @{ Status = '실패'; Detail = $_.Exception.Message }
    }
}

Export-ModuleMember -Function Get-WindowsSettingItems, Invoke-RegistrySetting, Send-SettingChange
