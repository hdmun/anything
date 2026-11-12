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

function Invoke-PowercfgQuery {
    param(
        [Parameter(Mandatory)][string]$SubGroup,
        [Parameter(Mandatory)][string]$Setting
    )
    $output = & powercfg.exe /query SCHEME_CURRENT $SubGroup $Setting 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "powercfg /query SCHEME_CURRENT $SubGroup $Setting 실패 (종료 코드 $LASTEXITCODE)"
    }
    return ($output -join "`n")
}

function Invoke-PowercfgChange {
    param(
        [Parameter(Mandatory)][string]$Command
    )
    $argString = $Command -replace '^powercfg(\.exe)?\s+', ''
    $argList = @($argString -split '\s+')
    $proc = Start-Process -FilePath 'powercfg.exe' -ArgumentList $argList -NoNewWindow -Wait -PassThru
    return $proc.ExitCode
}

function Get-AcValue {
    param(
        [Parameter(Mandatory)][string]$Output
    )
    $hexMatches = [regex]::Matches($Output, '0x[0-9a-fA-F]+')
    if ($hexMatches.Count -lt 2) {
        throw 'powercfg 출력에서 16진수 값을 찾을 수 없다'
    }
    $acHex = $hexMatches[$hexMatches.Count - 2].Value
    return [Convert]::ToInt32($acHex, 16)
}

function Invoke-Power {
    param([switch]$Check)

    $sleepOutput = $null
    $videoOutput = $null
    try {
        $sleepOutput = Invoke-PowercfgQuery -SubGroup 'SUB_SLEEP' -Setting 'STANDBYIDLE'
        $videoOutput = Invoke-PowercfgQuery -SubGroup 'SUB_VIDEO' -Setting 'VIDEOIDLE'
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

    $standbySec = Get-AcValue -Output $sleepOutput
    $monitorSec = Get-AcValue -Output $videoOutput

    $standbyOk = ($standbySec -eq 0)
    $monitorOk = ($monitorSec -eq 900)

    if ($standbyOk -and $monitorOk) {
        Write-Output '그대로'
        return
    }

    $standbyText = if ($standbySec -eq 0) { '안 함' } else { "$([int]($standbySec / 60))분" }
    $monitorText = "$([int]($monitorSec / 60))분"

    if ($Check) {
        Write-Output "다름 (절전 $standbyText, 모니터 $monitorText)"
        return
    }

    if (-not $standbyOk) {
        $cmd = 'powercfg /change standby-timeout-ac 0'
        $exitCode = Invoke-PowercfgChange -Command $cmd
        if ($exitCode -ne 0) {
            Write-Output "실패: $cmd 종료 코드 $exitCode"
            return
        }
    }

    if (-not $monitorOk) {
        $cmd = 'powercfg /change monitor-timeout-ac 15'
        $exitCode = Invoke-PowercfgChange -Command $cmd
        if ($exitCode -ne 0) {
            Write-Output "실패: $cmd 종료 코드 $exitCode"
            return
        }
    }

    Write-Output '바꿈'
}

function Invoke-Main {
    param([switch]$Check)
    Invoke-Power -Check:$Check
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-Main -Check:$Check
}
