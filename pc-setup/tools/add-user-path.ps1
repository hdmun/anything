# 사용자 PATH(HKCU\Environment\Path)에 경로 하나를 넣는 단독 스크립트.
# 사용: pwsh -NoProfile -File add-user-path.ps1 -Entry <경로> [-Prepend] [-Check]
# 표준 출력에 한 줄(그대로 | 다름: … | 바꿈: … | 실패: …)을 쓰고, 실패면 종료 코드 1, 나머지는 0 이다.
# PATH 는 REG_EXPAND_SZ 로 읽고 쓴다. setx 와 [Environment]::SetEnvironmentVariable 은 값을 자르거나 형식을 바꾸므로 쓰지 않는다.
param(
    [string]$Entry,
    [switch]$Prepend,
    [switch]$Check
)

function Get-EnvironmentPath {
    param([Parameter(Mandatory)][System.EnvironmentVariableTarget]$Target)
    [System.Environment]::GetEnvironmentVariable('Path', $Target)
}

function Update-SessionPath {
    # 시스템 PATH(HKLM) 다음에 사용자 PATH(HKCU)를 이어 현재 프로세스 $env:Path 로 둔다. 환경 변수(%...%)는 펼친다.
    $machinePath = Get-EnvironmentPath -Target ([System.EnvironmentVariableTarget]::Machine)
    $userPath = Get-EnvironmentPath -Target ([System.EnvironmentVariableTarget]::User)

    $parts = [System.Collections.Generic.List[string]]::new()
    foreach ($raw in @($machinePath, $userPath)) {
        if (-not [string]::IsNullOrEmpty($raw)) {
            foreach ($piece in ($raw -split ';')) {
                if (-not [string]::IsNullOrWhiteSpace($piece)) {
                    $parts.Add([System.Environment]::ExpandEnvironmentVariables($piece))
                }
            }
        }
    }

    $env:Path = $parts -join ';'
}

function Get-UserPathEntries {
    # 사용자 PATH 를 ';' 로 나눈 목록. %VAR% 표기는 펼치지 않는다. 테스트는 Mock 한다.
    $raw = ''
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $false)
    if ($null -ne $key) {
        try {
            $val = $key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            if ($null -ne $val) {
                $raw = [string]$val
            }
        } finally {
            $key.Dispose()
        }
    }

    if ([string]::IsNullOrEmpty($raw)) {
        return [string[]]@()
    }

    $entries = [string[]]@($raw -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    return $entries
}

function Set-UserPathEntries {
    # 사용자 PATH 를 REG_EXPAND_SZ 로 쓰고 WM_SETTINGCHANGE 를 알린다. 테스트는 Mock 한다.
    param([string[]]$Entries)

    $filtered = @($Entries | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $joined = $filtered -join ';'

    $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Environment')
    try {
        $key.SetValue('Path', $joined, [Microsoft.Win32.RegistryValueKind]::ExpandString)
    } finally {
        $key.Dispose()
    }

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
    $result = [UIntPtr]::Zero
    [Win32SettingChange]::SendMessageTimeout([IntPtr]0xffff, 0x001A, [UIntPtr]::Zero, 'Environment', 2, 5000, [ref]$result) | Out-Null
}

function ConvertTo-PathKey {
    # 비교용 꼴: 환경 변수를 펼치고 끝 '\' 를 뗀다. 비교는 대소문자 구분 없이(-ieq) 한다.
    param([string]$Path)
    [System.Environment]::ExpandEnvironmentVariables($Path).TrimEnd('\')
}

function Invoke-AddUserPath {
    # 사용자 PATH 에 $Entry 가 있게 한다(-Prepend 면 맨 앞) → @{ Status; Detail }
    # 바꿨을 때만 Set-UserPathEntries 와 Update-SessionPath 를 부른다. -Check 면 아무것도 바꾸지 않는다.
    param(
        [Parameter(Mandatory)][string]$Entry,
        [switch]$Prepend,
        [switch]$Check
    )

    $normalizedTarget = ConvertTo-PathKey $Entry
    $entries = @(Get-UserPathEntries)

    if (-not $Prepend) {
        foreach ($existing in $entries) {
            if ((ConvertTo-PathKey $existing) -ieq $normalizedTarget) {
                return @{ Status = '그대로'; Detail = '' }
            }
        }

        if ($Check) {
            return @{ Status = '다름'; Detail = "사용자 PATH 에 $Entry 없음" }
        }

        $newEntries = $entries + @($Entry)
        Set-UserPathEntries -Entries $newEntries
        Update-SessionPath
        return @{ Status = '바꿈'; Detail = "사용자 PATH 끝에 $Entry 추가" }
    }

    if ($entries.Count -gt 0 -and (ConvertTo-PathKey $entries[0]) -ieq $normalizedTarget) {
        return @{ Status = '그대로'; Detail = '' }
    }

    if ($Check) {
        return @{ Status = '다름'; Detail = "$Entry 가 맨 앞이 아님" }
    }

    $firstMatch = $null
    $remaining = [System.Collections.Generic.List[string]]::new()
    foreach ($existing in $entries) {
        if ((ConvertTo-PathKey $existing) -ieq $normalizedTarget) {
            if ($null -eq $firstMatch) {
                $firstMatch = $existing
            }
        } else {
            $remaining.Add($existing)
        }
    }

    $head = if ($null -ne $firstMatch) { $firstMatch } else { $Entry }
    $newEntries = @($head) + @($remaining)
    Set-UserPathEntries -Entries $newEntries
    Update-SessionPath
    return @{ Status = '바꿈'; Detail = "사용자 PATH 맨 앞에 $Entry" }
}

function Format-ResultLine {
    param([hashtable]$Result)
    if ($Result.Status -eq '그대로') {
        return '그대로'
    }
    return "$($Result.Status): $($Result.Detail)"
}

function Invoke-Main {
    # 매개변수 검사와 예외 처리를 맡는다 → [pscustomobject]@{ Line; ExitCode }
    param(
        [string]$Entry,
        [switch]$Prepend,
        [switch]$Check
    )

    try {
        if ([string]::IsNullOrWhiteSpace($Entry)) {
            return [pscustomobject]@{ Line = '실패: Entry 가 없다'; ExitCode = 1 }
        }
        $result = Invoke-AddUserPath -Entry $Entry -Prepend:$Prepend -Check:$Check
    } catch {
        return [pscustomobject]@{ Line = "실패: $($_.Exception.Message)"; ExitCode = 1 }
    }

    $code = if ($result.Status -eq '실패') { 1 } else { 0 }
    return [pscustomobject]@{ Line = (Format-ResultLine $result); ExitCode = $code }
}

if ($MyInvocation.InvocationName -ne '.') {
    $outcome = Invoke-Main -Entry $Entry -Prepend:$Prepend -Check:$Check
    Write-Output $outcome.Line
    exit $outcome.ExitCode
}
