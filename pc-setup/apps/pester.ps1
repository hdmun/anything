[CmdletBinding()]
param([switch]$Check)

function Get-InstalledPesterResources {
    return @(Get-InstalledPSResource -Name 'Pester' -Scope 'CurrentUser' -ErrorAction SilentlyContinue)
}

function Test-Pester6Installed {
    foreach ($res in @(Get-InstalledPesterResources)) {
        if ($null -ne $res.Version -and $res.Version.Major -eq 6) {
            return $true
        }
    }
    return $false
}

function Install-PesterResource {
    param(
        [string]$Name = 'Pester',
        [string]$Version = '[6.0,7.0)',
        [string]$Scope = 'CurrentUser'
    )
    Install-PSResource -Name $Name -Version $Version -Scope $Scope -TrustRepository -Quiet
}

function Invoke-Main {
    param([switch]$Check)

    if (Test-Pester6Installed) {
        Write-Output '그대로'
        return
    }

    if ($Check) {
        Write-Output '다름 (Pester 6 없음)'
        return
    }

    Install-PesterResource -Name 'Pester' -Version '[6.0,7.0)' -Scope 'CurrentUser'

    if (Test-Pester6Installed) {
        Write-Output '바꿈'
    } else {
        Write-Output '실패: Pester 6 이 설치되지 않았다'
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-Main -Check:$Check
}
