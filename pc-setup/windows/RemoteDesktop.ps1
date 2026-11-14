[CmdletBinding()]
param([switch]$Check)

function Test-AccessDeniedException {
    param($Exception)
    if ($null -eq $Exception) { return $false }
    if ($Exception -is [System.UnauthorizedAccessException] -or $Exception -is [System.Security.SecurityException]) {
        return $true
    }
    if ($Exception.Message -match 'Access is denied|액세스가 거부되었습니다') {
        return $true
    }
    if ($Exception.InnerException) {
        return (Test-AccessDeniedException -Exception $Exception.InnerException)
    }
    return $false
}

function Get-RemoteDesktopRegistry {
    $fDeny = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections' -ErrorAction Stop).fDenyTSConnections
    $userAuth = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name 'UserAuthentication' -ErrorAction Stop).UserAuthentication
    return @{
        fDenyTSConnections = $fDeny
        UserAuthentication = $userAuth
    }
}

function Set-RemoteDesktopRegistry {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][int]$Value
    )
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type DWord
}

function Get-RemoteDesktopFirewallRules {
    Get-NetFirewallRule -Group '@FirewallAPI.dll,-28752'
}

function Enable-RemoteDesktopFirewallRules {
    Enable-NetFirewallRule -Group '@FirewallAPI.dll,-28752'
}

function Test-FirewallRuleEnabled {
    param($Rule)
    if ($null -eq $Rule) { return $false }
    if ($Rule.Enabled -eq $true -or $Rule.Enabled -eq 'True' -or $Rule.Enabled -eq 1 -or "$($Rule.Enabled)" -eq 'True') {
        return $true
    }
    return $false
}

function Invoke-RemoteDesktop {
    param([switch]$Check)

    $regValues = $null
    $rules = $null
    try {
        $regValues = Get-RemoteDesktopRegistry
        $rules = @(Get-RemoteDesktopFirewallRules)
    } catch {
        if (Test-AccessDeniedException -Exception $_.Exception) {
            if ($Check) {
                Write-Output '확인 못 함: 관리자 필요'
            } else {
                Write-Output '실패: 관리자 필요'
            }
            return
        }
        throw
    }

    if ($rules.Count -eq 0) {
        Write-Output '실패: 원격 데스크톱 방화벽 규칙이 없다'
        return
    }

    $disabledRules = @($rules | Where-Object { -not (Test-FirewallRuleEnabled -Rule $_) })

    $fDenyOk = ($null -ne $regValues.fDenyTSConnections -and [int]$regValues.fDenyTSConnections -eq 0)
    $userAuthOk = ($null -ne $regValues.UserAuthentication -and [int]$regValues.UserAuthentication -eq 1)
    $firewallOk = ($disabledRules.Count -eq 0)

    if ($fDenyOk -and $userAuthOk -and $firewallOk) {
        Write-Output '그대로'
        return
    }

    $diffs = [System.Collections.Generic.List[string]]::new()
    if (-not $fDenyOk) {
        $diffs.Add("fDenyTSConnections $($regValues.fDenyTSConnections)")
    }
    if (-not $userAuthOk) {
        $diffs.Add("UserAuthentication $($regValues.UserAuthentication)")
    }
    if (-not $firewallOk) {
        $diffs.Add("방화벽 규칙 꺼짐 $($disabledRules.Count)개")
    }

    if ($Check) {
        Write-Output "다름 ($($diffs -join ', '))"
        return
    }

    try {
        if (-not $fDenyOk) {
            Set-RemoteDesktopRegistry -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections' -Value 0
        }
        if (-not $userAuthOk) {
            Set-RemoteDesktopRegistry -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name 'UserAuthentication' -Value 1
        }
        if (-not $firewallOk) {
            Enable-RemoteDesktopFirewallRules
        }
        Write-Output '바꿈'
    } catch {
        if (Test-AccessDeniedException -Exception $_.Exception) {
            Write-Output '실패: 관리자 필요'
            return
        }
        throw
    }
}

function Invoke-Main {
    param([switch]$Check)
    Invoke-RemoteDesktop -Check:$Check
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-Main -Check:$Check
}
