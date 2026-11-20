[CmdletBinding()]
param([switch]$Check)

function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    ([Security.Principal.WindowsPrincipal]$identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-RdpNotifyTask {
    Get-ScheduledTask -TaskName 'RdpNotify' -ErrorAction SilentlyContinue
}

function Get-ExpectedArguments {
    $psExe = (Get-Process -Id $PID).Path
    $xmlText = & $psExe -NoProfile -File "$PSScriptRoot\register.ps1" -PrintXml
    if ($LASTEXITCODE -ne 0) {
        throw "register.ps1 -PrintXml 종료 코드 $LASTEXITCODE"
    }
    if ($xmlText -is [array]) {
        $xmlText = $xmlText -join "`n"
    }
    $doc = [xml]$xmlText
    return [string]$doc.Task.Actions.Exec.Arguments
}

function Invoke-Register {
    $psExe = (Get-Process -Id $PID).Path
    & $psExe -NoProfile -File "$PSScriptRoot\register.ps1" | Out-Host
    return $LASTEXITCODE
}

function Test-EnvFile {
    Test-Path -LiteralPath (Join-Path $PSScriptRoot 'rdp-notify.env') -PathType Leaf
}

function Invoke-Main {
    param([switch]$Check)

    if (-not (Test-Admin)) {
        if ($Check) {
            Write-Output '확인 못 함: 관리자 필요'
        } else {
            Write-Output '실패: 관리자 필요'
        }
        return
    }

    $task = Get-RdpNotifyTask
    $expectedArgs = Get-ExpectedArguments

    $diffReason = $null
    if ($null -eq $task) {
        $diffReason = '작업 없음'
    } else {
        $actualArgs = $null
        if ($null -ne $task.Actions) {
            $firstAction = @($task.Actions)[0]
            if ($null -ne $firstAction) {
                $actualArgs = [string]$firstAction.Arguments
            }
        }
        if ($actualArgs -cne $expectedArgs) {
            $diffReason = '작업 경로 다름'
        } elseif ("$($task.State)" -eq 'Disabled') {
            $diffReason = '작업 꺼짐'
        }
    }

    $envPath = Join-Path $PSScriptRoot 'rdp-notify.env'
    $todoLine = "할 일: $envPath 만들기 (rdp-notify/README.md 설치 1~2번)"
    $hasEnv = Test-EnvFile

    if ($Check) {
        if (-not $hasEnv) {
            Write-Output $todoLine
        } elseif ($null -ne $diffReason) {
            Write-Output "다름 ($diffReason)"
        } else {
            Write-Output '그대로'
        }
        return
    }

    if ($null -ne $diffReason) {
        $exitCode = Invoke-Register
        if ($exitCode -ne 0) {
            Write-Output "실패: register.ps1 종료 코드 $exitCode"
            return
        }
        if (-not $hasEnv) {
            Write-Output $todoLine
        } else {
            Write-Output '바꿈'
        }
        return
    }

    if (-not $hasEnv) {
        Write-Output $todoLine
    } else {
        Write-Output '그대로'
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-Main -Check:$Check
}
