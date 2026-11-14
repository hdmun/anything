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

function Get-HibernateEnabled {
    if (-not (Test-Path -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Power')) {
        return $null
    }
    $key = Get-Item -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'
    return $key.GetValue('HibernateEnabled')
}

function Invoke-Powercfg {
    param([string[]]$Arguments)
    $proc = Start-Process -FilePath 'powercfg.exe' -ArgumentList $Arguments -NoNewWindow -Wait -PassThru
    return $proc.ExitCode
}

function Invoke-Hibernate {
    param([switch]$Check)

    $val = $null
    try {
        $val = Get-HibernateEnabled
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

    if ($null -eq $val -or [int]$val -eq 0) {
        Write-Output '그대로'
        return
    }

    if ($Check) {
        Write-Output "다름 (HibernateEnabled $val)"
        return
    }

    $exitCode = Invoke-Powercfg -Arguments @('/h', 'off')
    if ($exitCode -ne 0) {
        Write-Output "실패: powercfg /h off 종료 코드 $exitCode"
        return
    }

    $after = $null
    try {
        $after = Get-HibernateEnabled
    } catch {
        if (Test-AccessDeniedException -Exception $_.Exception) {
            Write-Output '실패: 관리자 필요'
            return
        }
        throw
    }

    if ($null -eq $after -or [int]$after -eq 0) {
        Write-Output '바꿈'
    } else {
        Write-Output '실패: 최대 절전이 꺼지지 않았다'
    }
}

function Invoke-Main {
    param([switch]$Check)
    Invoke-Hibernate -Check:$Check
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-Main -Check:$Check
}
