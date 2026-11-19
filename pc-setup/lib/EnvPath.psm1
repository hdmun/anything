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
    # 사용자 PATH 를 ';' 로 나눈 목록. 테스트는 Mock 한다.
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
    # 사용자 PATH 를 쓴다. 테스트는 Mock 한다.
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

function Add-UserPath {
    # 사용자 PATH 에 $Path 를 넣는다(-Prepend 면 맨 앞, 아니면 맨 뒤). 바꿨으면 $true, 이미 제자리에 있으면 $false.
    # 바꿨을 때만 Set-UserPathEntries 와 Update-SessionPath 를 부른다.
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$Prepend
    )

    $normalizedTarget = [System.Environment]::ExpandEnvironmentVariables($Path).TrimEnd('\')
    $entries = @(Get-UserPathEntries)

    if (-not $Prepend) {
        foreach ($entry in $entries) {
            if ([System.Environment]::ExpandEnvironmentVariables($entry).TrimEnd('\') -ieq $normalizedTarget) {
                return $false
            }
        }

        $newEntries = $entries + @($Path)
    } else {
        if ($entries.Count -gt 0 -and [System.Environment]::ExpandEnvironmentVariables($entries[0]).TrimEnd('\') -ieq $normalizedTarget) {
            return $false
        }

        $firstMatch = $null
        $remaining = [System.Collections.Generic.List[string]]::new()
        foreach ($entry in $entries) {
            if ([System.Environment]::ExpandEnvironmentVariables($entry).TrimEnd('\') -ieq $normalizedTarget) {
                if ($null -eq $firstMatch) {
                    $firstMatch = $entry
                }
            } else {
                $remaining.Add($entry)
            }
        }

        $head = if ($null -ne $firstMatch) { $firstMatch } else { $Path }
        $newEntries = @($head) + @($remaining)
    }

    Set-UserPathEntries -Entries $newEntries
    Update-SessionPath
    return $true
}

Export-ModuleMember -Function Update-SessionPath, Add-UserPath, Get-UserPathEntries, Set-UserPathEntries
